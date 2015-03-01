//
//  Task.swift
//  ReactiveTask
//
//  Created by Justin Spahr-Summers on 2014-10-10.
//  Copyright (c) 2014 Carthage. All rights reserved.
//

import Foundation
import LlamaKit
import ReactiveCocoa

/// Describes how to execute a shell command.
public struct TaskDescription {
	/// The path to the executable that should be launched.
	public var launchPath: String

	/// Any arguments to provide to the executable.
	public var arguments: [String]

	/// The path to the working directory in which the process should be
	/// launched.
	///
	/// If nil, the launched task will inherit the working directory of its
	/// parent.
	public var workingDirectoryPath: String?

	/// Environment variables to set for the launched process.
	///
	/// If nil, the launched task will inherit the environment of its parent.
	public var environment: [String: String]?

	/// Data to stream to standard input of the launched process.
	///
	/// If nil, stdin will be inherited from the parent process.
	public var standardInput: SignalProducer<NSData, NoError>?

	public init(launchPath: String, arguments: [String] = [], workingDirectoryPath: String? = nil, environment: [String: String]? = nil, standardInput: SignalProducer<NSData, NoError>? = nil) {
		self.launchPath = launchPath
		self.arguments = arguments
		self.workingDirectoryPath = workingDirectoryPath
		self.environment = environment
		self.standardInput = standardInput
	}
}

extension TaskDescription: Printable {
	public var description: String {
		var str = "\(launchPath)"

		for arg in arguments {
			str += " \(arg)"
		}

		return str
	}
}

/// A private class used to encapsulate a Unix pipe.
private final class Pipe {
	/// The file descriptor for reading data.
	let readFD: Int32

	/// The file descriptor for writing data.
	let writeFD: Int32

	/// Creates an NSFileHandle corresponding to the `readFD`. The file handle
	/// will not automatically close the descriptor.
	var readHandle: NSFileHandle {
		return NSFileHandle(fileDescriptor: readFD, closeOnDealloc: false)
	}

	/// Creates an NSFileHandle corresponding to the `writeFD`. The file handle
	/// will not automatically close the descriptor.
	var writeHandle: NSFileHandle {
		return NSFileHandle(fileDescriptor: writeFD, closeOnDealloc: false)
	}

	/// Initializes a pipe object using existing file descriptors.
	init(readFD: Int32, writeFD: Int32) {
		precondition(readFD >= 0)
		precondition(writeFD >= 0)

		self.readFD = readFD
		self.writeFD = writeFD
	}

	/// Instantiates a new descriptor pair.
	class func create() -> Result<Pipe, ReactiveTaskError> {
		var fildes: [Int32] = [ 0, 0 ]
		if pipe(&fildes) == 0 {
			return success(self(readFD: fildes[0], writeFD: fildes[1]))
		} else {
			return failure(.POSIXError(errno))
		}
	}

	/// Closes both file descriptors of the receiver.
	func closePipe() {
		close(readFD)
		close(writeFD)
	}

	/// Creates a signal that will take ownership of the `readFD` using
	/// dispatch_io, then read it to completion.
	///
	/// After starting the returned producer, `readFD` should not be used
	/// anywhere else, as it may close unexpectedly.
	func transferReadsToProducer() -> SignalProducer<dispatch_data_t, ReactiveTaskError> {
		let queue = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0)

		return SignalProducer { observer, disposable in
			let channel = dispatch_io_create(DISPATCH_IO_STREAM, self.readFD, queue) { error in
				if error == 0 {
					sendCompleted(observer)
				} else {
					sendError(observer, .POSIXError(error))
				}

				close(self.readFD)
			}

			dispatch_io_set_low_water(channel, 1)
			dispatch_io_read(channel, 0, UInt.max, queue) { (done, data, error) in
				if let data = data {
					sendNext(observer, data)
				}

				if error != 0 {
					sendError(observer, .POSIXError(error))
				}

				if done {
					dispatch_io_close(channel, 0)
				}
			}

			disposable.addDisposable {
				dispatch_io_close(channel, DISPATCH_IO_STOP)
			}
		}
	}

	/// Creates a dispatch_io channel for writing all data that arrives on
	/// `signal` into `writeFD`, then closes `writeFD` when the input signal
	/// terminates.
	///
	/// After starting the returned producer, `writeFD` should not be used
	/// anywhere else, as it may close unexpectedly.
	///
	/// Returns a producer that will complete or error.
	func writeDataFromProducer(producer: SignalProducer<NSData, NoError>) -> SignalProducer<(), ReactiveTaskError> {
		let queue = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0)

		return SignalProducer { observer, disposable in
			let channel = dispatch_io_create(DISPATCH_IO_STREAM, self.writeFD, queue) { error in
				if error == 0 {
					sendCompleted(observer)
				} else {
					sendError(observer, .POSIXError(error))
				}

				close(self.writeFD)
			}

			producer.startWithSignal { signal, producerDisposable in
				disposable.addDisposable(producerDisposable)

				signal.observe(next: { data in
					let dispatchData = dispatch_data_create(data.bytes, UInt(data.length), queue, nil)

					dispatch_io_write(channel, 0, dispatchData, queue) { (done, data, error) in
						if error != 0 {
							sendError(observer, .POSIXError(error))
						}
					}
				}, completed: {
					dispatch_io_close(channel, 0)
				})
			}

			disposable.addDisposable {
				dispatch_io_close(channel, DISPATCH_IO_STOP)
			}
		}
	}
}

/// Takes ownership of the read handle from the given pipe, then aggregates all
/// data into one `NSData` object, which is then sent upon the returned signal.
///
/// If `forwardingSink` is non-nil, each incremental piece of data will be sent
/// to it as data is received.
private func aggregateDataReadFromPipe(pipe: Pipe, forwardingSink: SinkOf<NSData>?) -> SignalProducer<NSData, ReactiveTaskError> {
	let readProducer = pipe.transferReadsToProducer()

	return SignalProducer { observer, disposable in
		var buffer: dispatch_data_t? = nil

		readProducer.startWithSignal { signal, signalDisposable in
			disposable.addDisposable(signalDisposable)

			signal.observe(next: { data in
				forwardingSink?.put(data as NSData)

				if let existingBuffer = buffer {
					buffer = dispatch_data_create_concat(existingBuffer, data)
				} else {
					buffer = data
				}
			}, error: { error in
				sendError(observer, error)
			}, completed: {
				if let buffer = buffer {
					sendNext(observer, buffer as NSData)
				} else {
					sendNext(observer, NSData())
				}

				sendCompleted(observer)
			})
		}
	}
}

/// Launches a new shell task, using the parameters from `taskDescription`.
///
/// Returns a producer that will launch the task when started, then send one
/// `NSData` value (representing aggregated data from `stdout`) and complete
/// upon success.
public func launchTask(taskDescription: TaskDescription, standardOutput: SinkOf<NSData>? = nil, standardError: SinkOf<NSData>? = nil) -> SignalProducer<NSData, ReactiveTaskError> {
	return SignalProducer { observer, disposable in
		let task = NSTask()
		task.launchPath = taskDescription.launchPath
		task.arguments = taskDescription.arguments

		if let cwd = taskDescription.workingDirectoryPath {
			task.currentDirectoryPath = cwd
		}

		if let env = taskDescription.environment {
			task.environment = env
		}

		var stdinProducer: SignalProducer<(), ReactiveTaskError> = .empty

		if let input = taskDescription.standardInput {
			switch Pipe.create() {
			case let .Success(pipe):
				task.standardInput = pipe.unbox.readHandle

				// FIXME: This is basically a reimplementation of on(started:)
				// to avoid a compiler crash.
				stdinProducer = SignalProducer { observer, disposable in
					close(pipe.unbox.readFD)

					pipe.unbox.writeDataFromProducer(input).startWithSignal { signal, signalDisposable in
						disposable.addDisposable(signalDisposable)
						signal.observe(observer)
					}
				}

			case let .Failure(error):
				sendError(observer, error.unbox)
			}
		}

		SignalProducer(result: Pipe.create())
			|> zipWith(SignalProducer(result: Pipe.create()))
			|> joinMap(.Merge) { stdoutPipe, stderrPipe -> SignalProducer<NSData, ReactiveTaskError> in
				let stdoutProducer = aggregateDataReadFromPipe(stdoutPipe, standardOutput)
				let stderrProducer = aggregateDataReadFromPipe(stderrPipe, standardError)

				let terminationStatusProducer = SignalProducer<Int32, NoError> { observer, disposable in
					task.terminationHandler = { task in
						sendNext(observer, task.terminationStatus)
						sendCompleted(observer)
					}

					task.standardOutput = stdoutPipe.writeHandle
					task.standardError = stderrPipe.writeHandle

					if disposable.disposed {
						stdoutPipe.closePipe()
						stderrPipe.closePipe()
						stdinProducer.start().dispose()
						return
					}

					task.launch()
					close(stdoutPipe.writeFD)
					close(stderrPipe.writeFD)

					let stdinDisposable = stdinProducer.start()
					disposable.addDisposable(stdinDisposable)

					disposable.addDisposable {
						task.terminate()
					}
				}

				return
					combineLatest(
						stdoutProducer,
						stderrProducer,
						terminationStatusProducer |> promoteErrors(ReactiveTaskError.self)
					)
					|> tryMap { stdoutData, stderrData, terminationStatus -> Result<NSData, ReactiveTaskError> in
						if terminationStatus == EXIT_SUCCESS {
							return success(stdoutData)
						} else {
							let errorString = (stderrData.length > 0 ? NSString(data: stderrData, encoding: NSUTF8StringEncoding) : nil)
							return failure(.ShellTaskFailed(exitCode: terminationStatus, standardError: errorString))
						}
					}
			}
			|> startWithSignal { signal, taskDisposable in
				disposable.addDisposable(taskDisposable)
				signal.observe(observer)
			}
	}
}
