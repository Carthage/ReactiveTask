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

/// Sent when reading from a pipe.
private enum ReadData {
	/// A chunk of data, sent as soon as it is received.
	case Chunk(NSData)

	/// The aggregate of all data sent so far, sent right before completion.
	///
	/// No further chunks will occur after this has been sent.
	case Aggregated(NSData)

	/// Convenience constructor for a `Chunk` from `dispatch_data_t`.
	static func chunk(data: dispatch_data_t) -> ReadData {
		return .Chunk(data as! NSData)
	}

	/// Convenience constructor for an `Aggregated` from `dispatch_data_t`.
	static func aggregated(data: dispatch_data_t?) -> ReadData {
		if let data = data {
			return .Aggregated(data as! NSData)
		} else {
			return .Aggregated(NSData())
		}
	}
}

/// Takes ownership of the read handle from the given pipe, then sends
/// `ReadData` values for all data read.
private func aggregateDataReadFromPipe(pipe: Pipe) -> SignalProducer<ReadData, ReactiveTaskError> {
	let readProducer = pipe.transferReadsToProducer()

	return SignalProducer { observer, disposable in
		let buffer = MutableBox<dispatch_data_t?>(nil)

		readProducer.startWithSignal { signal, signalDisposable in
			disposable.addDisposable(signalDisposable)

			signal.observe(next: { data in
				sendNext(observer, .chunk(data))

				if let existingBuffer = buffer.value {
					buffer.value = dispatch_data_create_concat(existingBuffer, data)
				} else {
					buffer.value = data
				}
			}, error: { error in
				sendError(observer, error)
			}, completed: {
				sendNext(observer, .aggregated(buffer.value))
				sendCompleted(observer)
			}, interrupted: {
				sendInterrupted(observer)
			})
		}
	}
}

/// Represents events that can occur during the execution of a task that is
/// expected to terminate with a result of type T (upon success).
public enum TaskEvent<T> {
	/// Some data arrived from the task on `stdout`.
	case StandardOutput(NSData)

	/// Some data arrived from the task on `stderr`.
	case StandardError(NSData)

	/// The task exited successfully (with status 0), and value T was produced
	/// as a result.
	case Success(Box<T>)

	/// The resulting value, if the event is `Success`.
	public var value: T? {
		switch self {
		case .StandardOutput, .StandardError:
			return nil

		case let .Success(box):
			return box.value
		}
	}

	/// Maps over the value embedded in a `Success` event.
	public func map<U>(@noescape transform: T -> U) -> TaskEvent<U> {
		switch self {
		case let .StandardOutput(data):
			return .StandardOutput(data)

		case let .StandardError(data):
			return .StandardError(data)

		case let .Success(box):
			return .Success(Box(transform(box.value)))
		}
	}

	/// Convenience operator for mapping TaskEvents to SignalProducers.
	public func producerMap<U, Error>(@noescape transform: T -> SignalProducer<U, Error>) -> SignalProducer<TaskEvent<U>, Error> {
		switch self {
		case let .StandardOutput(data):
			return SignalProducer<TaskEvent<U>, Error>(value: .StandardOutput(data))

		case let .StandardError(data):
			return SignalProducer<TaskEvent<U>, Error>(value: .StandardError(data))

		case let .Success(box):
			return transform(box.value) |> ReactiveCocoa.map { .Success(Box($0)) }
		}
	}
}

public func == <T: Equatable>(lhs: TaskEvent<T>, rhs: TaskEvent<T>) -> Bool {
	switch (lhs, rhs) {
	case let (.StandardOutput(left), .StandardOutput(right)):
		return left == right
	
	case let (.StandardError(left), .StandardError(right)):
		return left == right
	
	case let (.Success(left), .Success(right)):
		return left == right
	
	default:
		return false
	}
}

extension TaskEvent: Printable {
	public var description: String {
		func dataDescription(data: NSData) -> String {
			return NSString(data: data, encoding: NSUTF8StringEncoding).map { $0 as String } ?? data.description
		}

		switch self {
		case let .StandardOutput(data):
			return "stdout: " + dataDescription(data)

		case let .StandardError(data):
			return "stderr: " + dataDescription(data)

		case let .Success(value):
			return "success(\(value))"
		}
	}
}

/// Maps the values inside a stream of TaskEvents into new SignalProducers.
public func flatMapTaskEvents<T, U, Error>(strategy: FlattenStrategy, transform: T -> SignalProducer<U, Error>) -> SignalProducer<TaskEvent<T>, Error> -> SignalProducer<TaskEvent<U>, Error> {
	return { producer in
		return producer |> flatMap(strategy) { taskEvent in
			return taskEvent.producerMap(transform)
		}
	}
}

/// Ignores incremental standard output and standard error data from the given
/// task, sending only a single value with the final, aggregated result.
public func ignoreTaskData<T, Error>(signal: Signal<TaskEvent<T>, Error>) -> Signal<T, Error> {
	return signal
		|> map { event in
			return event.value.map { $0 }
		}
		|> ignoreNil
}

/// Launches a new shell task, using the parameters from `taskDescription`.
///
/// Returns a producer that will launch the task when started, then send
/// `TaskEvent`s as execution proceeds.
public func launchTask(taskDescription: TaskDescription) -> SignalProducer<TaskEvent<NSData>, ReactiveTaskError> {
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
			|> flatMap(.Concat) { stdoutPipe -> SignalProducer<TaskEvent<NSData>, ReactiveTaskError> in
				let stdoutProducer = aggregateDataReadFromPipe(stdoutPipe)

				return SignalProducer(result: Pipe.create(queue))
					|> flatMap(.Merge) { stderrPipe -> SignalProducer<TaskEvent<NSData>, ReactiveTaskError> in
						let stderrProducer = aggregateDataReadFromPipe(stderrPipe)

						return SignalProducer { observer, disposable in
							let (stdoutAggregated, stdoutAggregatedSink) = SignalProducer<NSData, ReactiveTaskError>.buffer(1)
							let (stderrAggregated, stderrAggregatedSink) = SignalProducer<NSData, ReactiveTaskError>.buffer(1)

							stdoutProducer.startWithSignal { signal, signalDisposable in
								disposable += signalDisposable

								signal.observe(next: { readData in
									switch readData {
									case let .Chunk(data):
										sendNext(observer, .StandardOutput(data))

									case let .Aggregated(data):
										sendNext(stdoutAggregatedSink, data)
									}
								}, error: { error in
									sendError(observer, error)
									sendError(stdoutAggregatedSink, error)
								}, completed: {
									sendCompleted(stdoutAggregatedSink)
								}, interrupted: {
									sendInterrupted(stdoutAggregatedSink)
								})
							}

							stderrProducer.startWithSignal { signal, signalDisposable in
								disposable += signalDisposable

								signal.observe(next: { readData in
									switch readData {
									case let .Chunk(data):
										sendNext(observer, .StandardError(data))

									case let .Aggregated(data):
										sendNext(stderrAggregatedSink, data)
									}
								}, error: { error in
									sendError(observer, error)
									sendError(stderrAggregatedSink, error)
								}, completed: {
									sendCompleted(stderrAggregatedSink)
								}, interrupted: {
									sendInterrupted(stderrAggregatedSink)
								})
							}

							task.standardOutput = stdoutPipe.writeHandle
							task.standardError = stderrPipe.writeHandle

							task.terminationHandler = { task in
								let terminationStatus = task.terminationStatus
								if terminationStatus == EXIT_SUCCESS {
									// Wait for stderr to finish, then pass
									// through stdout.
									disposable += stderrAggregated
										|> then(stdoutAggregated)
										|> map { data in .Success(Box(data)) }
										|> start(observer)
								} else {
									// Wait for stdout to finish, then pass
									// through stderr.
									disposable += stdoutAggregated
										|> then(stderrAggregated)
										|> flatMap(.Concat) { data in
											let errorString = (data.length > 0 ? String(UTF8String: UnsafePointer<CChar>(data.bytes)) : nil)
											return SignalProducer(error: .ShellTaskFailed(exitCode: terminationStatus, standardError: errorString))
										}
										|> start(observer)
								}
							}

							task.launch()
							close(stdoutPipe.writeFD)
							close(stderrPipe.writeFD)

							stdinProducer.startWithSignal { signal, signalDisposable in
								disposable += signalDisposable
							}

							disposable.addDisposable {
								task.terminate()
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
