//
//  Task.swift
//  ReactiveTask
//
//  Created by Justin Spahr-Summers on 2014-10-10.
//  Copyright (c) 2014 Carthage. All rights reserved.
//

import Box
import Foundation
import ReactiveCocoa
import Result

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
		return arguments.reduce(launchPath) { str, arg in
			return str + " \(arg)"
		}
	}
}

/// A private class used to encapsulate a Unix pipe.
private final class Pipe {
	/// The file descriptor for reading data.
	let readFD: Int32

	/// The file descriptor for writing data.
	let writeFD: Int32

	/// A GCD queue upon which to deliver I/O callbacks.
	let queue: dispatch_queue_t

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
	init(readFD: Int32, writeFD: Int32, queue: dispatch_queue_t) {
		precondition(readFD >= 0)
		precondition(writeFD >= 0)

		self.readFD = readFD
		self.writeFD = writeFD
		self.queue = queue
	}

	/// Instantiates a new descriptor pair.
	class func create(queue: dispatch_queue_t) -> Result<Pipe, ReactiveTaskError> {
		var fildes: [Int32] = [ 0, 0 ]
		if pipe(&fildes) == 0 {
			return .success(self(readFD: fildes[0], writeFD: fildes[1], queue: queue))
		} else {
			return .failure(.POSIXError(errno))
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
		return SignalProducer { observer, disposable in
			let channel = dispatch_io_create(DISPATCH_IO_STREAM, self.readFD, self.queue) { error in
				if error == 0 {
					sendCompleted(observer)
				} else {
					sendError(observer, .POSIXError(error))
				}

				close(self.readFD)
			}

			dispatch_io_set_low_water(channel, 1)
			dispatch_io_read(channel, 0, Int.max, self.queue) { (done, data, error) in
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
		return SignalProducer { observer, disposable in
			let channel = dispatch_io_create(DISPATCH_IO_STREAM, self.writeFD, self.queue) { error in
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
					let dispatchData = dispatch_data_create(data.bytes, data.length, self.queue, nil)

					dispatch_io_write(channel, 0, dispatchData, self.queue) { (done, data, error) in
						if error != 0 {
							sendError(observer, .POSIXError(error))
						}
					}
				}, completed: {
					dispatch_io_close(channel, 0)
				}, interrupted: {
					sendInterrupted(observer)
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
		let buffer = MutableBox<dispatch_data_t?>(nil)

		readProducer.startWithSignal { signal, signalDisposable in
			disposable.addDisposable(signalDisposable)

			signal.observe(next: { data in
				forwardingSink?.put(data as! NSData)
				if let existingBuffer = buffer.value {
					buffer.value = dispatch_data_create_concat(existingBuffer, data)
				} else {
					buffer.value = data
				}
			}, error: { error in
				sendError(observer, error)
			}, completed: {
				if let existingBuffer = buffer.value {
					sendNext(observer, existingBuffer as! NSData)
				} else {
					sendNext(observer, NSData())
				}

				sendCompleted(observer)
			}, interrupted: {
				sendInterrupted(observer)
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
		let queue = dispatch_queue_create(taskDescription.description, DISPATCH_QUEUE_SERIAL)

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
			switch Pipe.create(queue) {
			case let .Success(pipe):
				task.standardInput = pipe.value.readHandle

				stdinProducer = pipe.value.writeDataFromProducer(input) |> on(started: {
					close(pipe.value.readFD)
				})

			case let .Failure(error):
				sendError(observer, error.value)
			}
		}

		SignalProducer(result: Pipe.create(queue))
			|> flatMap(.Concat) { stdoutPipe -> SignalProducer<NSData, ReactiveTaskError> in
				let stdoutProducer = aggregateDataReadFromPipe(stdoutPipe, standardOutput)

				return SignalProducer(result: Pipe.create(queue))
					|> flatMap(.Merge) { stderrPipe -> SignalProducer<NSData, ReactiveTaskError> in
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

								// Clean up the stdin pipe in a roundabout way.
								stdinProducer.startWithSignal { signal, signalDisposable in
									signalDisposable.dispose()
								}

								return
							}

							task.launch()
							close(stdoutPipe.writeFD)
							close(stderrPipe.writeFD)

							stdinProducer.startWithSignal { signal, signalDisposable in
								disposable.addDisposable(signalDisposable)
							}

							disposable.addDisposable {
								task.terminate()
							}
						}

						return
							zip(
								stdoutProducer,
								stderrProducer,
								terminationStatusProducer |> promoteErrors(ReactiveTaskError.self)
							)
							|> tryMap { stdoutData, stderrData, terminationStatus -> Result<NSData, ReactiveTaskError> in
								if terminationStatus == EXIT_SUCCESS {
									return .success(stdoutData)
								} else {
									let errorString = (stderrData.length > 0 ? String(UTF8String: UnsafePointer<CChar>(stderrData.bytes)) : nil)
									return .failure(.ShellTaskFailed(exitCode: terminationStatus, standardError: errorString))
								}
							}
					}
			}
			|> startWithSignal { signal, taskDisposable in
				disposable.addDisposable(taskDisposable)
				signal.observe(observer)
			}
	}
}
