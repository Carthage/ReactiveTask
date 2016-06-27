//
//  Task.swift
//  ReactiveTask
//
//  Created by Justin Spahr-Summers on 2014-10-10.
//  Copyright (c) 2014 Carthage. All rights reserved.
//

import Foundation
import ReactiveCocoa
import Result

/// Describes how to execute a shell command.
public struct Task {
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

	public init(_ launchPath: String, arguments: [String] = [], workingDirectoryPath: String? = nil, environment: [String: String]? = nil) {
		self.launchPath = launchPath
		self.arguments = arguments
		self.workingDirectoryPath = workingDirectoryPath
		self.environment = environment
	}
	
	/// A GCD group which to wait completion
	private static let group = DispatchGroup()
	
	/// wait for all task termination
	public static func waitForAllTaskTermination() {
		Task.group.wait(timeout: DispatchTime.distantFuture)
	}
}

extension Task: CustomStringConvertible {
	public var description: String {
		return "\(launchPath) \(arguments.joined(separator: " "))"
	}
}

extension Task: Hashable {
	public var hashValue: Int {
		var result = launchPath.hashValue ^ (workingDirectoryPath?.hashValue ?? 0)
		for argument in arguments {
			result ^= argument.hashValue
		}
		for (key, value) in environment ?? [:] {
			result ^= key.hashValue ^ value.hashValue
		}
		return result
	}
}

private func ==<Key: Equatable, Value: Equatable>(lhs: [Key: Value]?, rhs: [Key: Value]?) -> Bool {
	switch (lhs, rhs) {
	case let (lhs?, rhs?):
		return lhs == rhs
		
	case (.none, .none):
		return true
		
	default:
		return false
	}
}

public func ==(lhs: Task, rhs: Task) -> Bool {
	return lhs.launchPath == rhs.launchPath && lhs.arguments == rhs.arguments && lhs.workingDirectoryPath == rhs.workingDirectoryPath && lhs.environment == rhs.environment
}

/// A private class used to encapsulate a Unix pipe.
private final class Pipe {
	typealias ReadProducer = SignalProducer<Data, TaskError>

	/// The file descriptor for reading data.
	let readFD: Int32

	/// The file descriptor for writing data.
	let writeFD: Int32

	/// A GCD queue upon which to deliver I/O callbacks.
	let queue: DispatchQueue
	
	/// A GCD group which to wait completion
	let group: DispatchGroup

	/// Creates an NSFileHandle corresponding to the `readFD`. The file handle
	/// will not automatically close the descriptor.
	var readHandle: FileHandle {
		return FileHandle(fileDescriptor: readFD, closeOnDealloc: false)
	}

	/// Creates an NSFileHandle corresponding to the `writeFD`. The file handle
	/// will not automatically close the descriptor.
	var writeHandle: FileHandle {
		return FileHandle(fileDescriptor: writeFD, closeOnDealloc: false)
	}

	/// Initializes a pipe object using existing file descriptors.
	init(readFD: Int32, writeFD: Int32, queue: DispatchQueue, group: DispatchGroup) {
		precondition(readFD >= 0)
		precondition(writeFD >= 0)

		self.readFD = readFD
		self.writeFD = writeFD
		self.queue = queue
		self.group = group
	}

	/// Instantiates a new descriptor pair.
	//TODO: Swift 3 API guidelines?
	class func create(_ queue: DispatchQueue, _ group: DispatchGroup) -> Result<Pipe, TaskError> {
		var fildes: [Int32] = [ 0, 0 ]
		if pipe(&fildes) == 0 {
			return .Success(self.init(readFD: fildes[0], writeFD: fildes[1], queue: queue, group: group))
		} else {
			return .Failure(.posixError(errno))
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
	func transferReadsToProducer() -> ReadProducer {
		return SignalProducer { observer, disposable in
			self.group.enter()
			let channel = DispatchIO(type: .stream, fileDescriptor: self.readFD, queue: self.queue) { error in
				if error == 0 {
					observer.sendCompleted()
				} else if error == ECANCELED {
					observer.sendInterrupted()
				} else {
					observer.sendFailed(.posixError(error))
				}

				close(self.readFD)
				self.group.leave()
			}

			channel.setLimit(lowWater: 1)
			channel.read(offset: 0, length: Int.max, queue: self.queue) { (done, dispatchData, error) in
				if let dispatchData = dispatchData {
					let bytes = UnsafeMutablePointer<UInt8>(allocatingCapacity: dispatchData.count)
					dispatchData.copyBytes(to: bytes, count: dispatchData.count)
					let data = Data(bytes: bytes, count: dispatchData.count)
					observer.sendNext(data)
				}

				if error == ECANCELED {
					observer.sendInterrupted()
				} else if error != 0 {
					observer.sendFailed(.posixError(error))
				}

				if done {
					channel.close()
				}
			}

			disposable.addDisposable {
				channel.close(flags: .stop)
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
	//TODO: Swift 3 API guidelines?
	func writeDataFromProducer(_ producer: SignalProducer<Data, NoError>) -> SignalProducer<(), TaskError> {
		return SignalProducer { observer, disposable in
			self.group.enter()
			let channel = DispatchIO(type: .stream, fileDescriptor: self.writeFD, queue: self.queue) { error in
				if error == 0 {
					observer.sendCompleted()
				} else if error == ECANCELED {
					observer.sendInterrupted()
				} else {
					observer.sendFailed(.posixError(error))
				}

				close(self.writeFD)
				self.group.leave()
			}

			producer.startWithSignal { signal, producerDisposable in
				disposable.addDisposable(producerDisposable)

				signal.observe(Observer(next: { data in
					let bytes = UnsafeMutablePointer<UInt8>(allocatingCapacity: data.count)
					data.copyBytes(to: bytes, count: data.count)
					let buffer = UnsafeBufferPointer(start: bytes, count: data.count)
					let dispatchData = DispatchData(bytes: buffer)
					channel.write(offset: 0, data: dispatchData, queue: self.queue) { (done, data, error) in
						if error == ECANCELED {
							observer.sendInterrupted()
						} else if error != 0 {
							observer.sendFailed(.posixError(error))
						}
					}
				}, completed: {
					channel.close()
				}, interrupted: {
					observer.sendInterrupted()
				}))
			}

			disposable.addDisposable {
				channel.close(flags: .stop)
			}
		}
	}
}

public protocol TaskEventType {
	/// The type of value embedded in a `Success` event.
	associatedtype T

	/// The resulting value, if the event is `Success`.
	var value: T? { get }

	/// Maps over the value embedded in a `Success` event.
	func map<U>( _ transform: @noescape(T) -> U) -> TaskEvent<U>

	/// Convenience operator for mapping TaskEvents to SignalProducers.
	func producerMap<U, Error>( _ transform: @noescape(T) -> SignalProducer<U, Error>) -> SignalProducer<TaskEvent<U>, Error>
}

/// Represents events that can occur during the execution of a task that is
/// expected to terminate with a result of type T (upon success).
public enum TaskEvent<T>: TaskEventType {
	/// The task is about to be launched.
	case launch(Task)
	
	/// Some data arrived from the task on `stdout`.
	case standardOutput(Data)

	/// Some data arrived from the task on `stderr`.
	case standardError(Data)

	/// The task exited successfully (with status 0), and value T was produced
	/// as a result.
	case success(T)

	/// The resulting value, if the event is `Success`.
	public var value: T? {
		if case let .success(value) = self {
			return value
		}
		return nil
	}

	/// Maps over the value embedded in a `Success` event.
	public func map<U>( _ transform: @noescape(T) -> U) -> TaskEvent<U> {
		switch self {
		case let .launch(task):
			return .launch(task)

		case let .standardOutput(data):
			return .standardOutput(data)

		case let .standardError(data):
			return .standardError(data)

		case let .success(value):
			return .success(transform(value))
		}
	}

	/// Convenience operator for mapping TaskEvents to SignalProducers.
	public func producerMap<U, Error>( _ transform: @noescape(T) -> SignalProducer<U, Error>) -> SignalProducer<TaskEvent<U>, Error> {
		switch self {
		case let .launch(task):
			return .init(value: .launch(task))
			
		case let .standardOutput(data):
			return .init(value: .standardOutput(data))

		case let .standardError(data):
			return .init(value: .standardError(data))

		case let .success(value):
			return transform(value).map(TaskEvent<U>.success)
		}
	}
}

public func == <T: Equatable>(lhs: TaskEvent<T>, rhs: TaskEvent<T>) -> Bool {
	switch (lhs, rhs) {
	case let (.launch(left), .launch(right)):
		return left == right
	
	case let (.standardOutput(left), .standardOutput(right)):
		return left == right
	
	case let (.standardError(left), .standardError(right)):
		return left == right
	
	case let (.success(left), .success(right)):
		return left == right
	
	default:
		return false
	}
}

extension TaskEvent: CustomStringConvertible {
	public var description: String {
		func dataDescription(_ data: Data) -> String {
			// TODO: Check whether this can be done without NSString
			return NSString(data: data, encoding: String.Encoding.utf8.rawValue).map { $0 as String } ?? data.description
		}

		switch self {
		case let .launch(task):
			return "launch: \(task)"
			
		case let .standardOutput(data):
			return "stdout: " + dataDescription(data)

		case let .standardError(data):
			return "stderr: " + dataDescription(data)

		case let .success(value):
			return "success(\(value))"
		}
	}
}

extension SignalProducer where Value: TaskEventType {
	/// Maps the values inside a stream of TaskEvents into new SignalProducers.
	public func flatMapTaskEvents<U>(_ strategy: FlattenStrategy, transform: (Value.T) -> SignalProducer<U, Error>) -> SignalProducer<TaskEvent<U>, Error> {
		return self.flatMap(strategy) { taskEvent in
			return taskEvent.producerMap(transform)
		}
	}
	
	/// Ignores incremental standard output and standard error data from the given
	/// task, sending only a single value with the final, aggregated result.
	public func ignoreTaskData() -> SignalProducer<Value.T, Error> {
		return lift { $0.ignoreTaskData() }
	}
}

extension Signal where Value: TaskEventType {
	/// Ignores incremental standard output and standard error data from the given
	/// task, sending only a single value with the final, aggregated result.
	public func ignoreTaskData() -> Signal<Value.T, Error> {
		return self
			.map { event in
				return event.value
			}
			.ignoreNil()
	}
}

/// Launches a new shell task.
///
/// - Parameters:
///   - task:          The task to launch.
///   - standardInput: Data to stream to standard input of the launched process. If nil, stdin will
///                    be inherited from the parent process.
///
/// - Returns: A producer that will launch the task when started, then send
/// `TaskEvent`s as execution proceeds.
//TODO: Swift 3 API guidelines?
public func launchTask(_ task: Task, standardInput: SignalProducer<Data, NoError>? = nil) -> SignalProducer<TaskEvent<Data>, TaskError> {
	return SignalProducer { observer, disposable in
		let queue = DispatchQueue(label: task.description, attributes: .serial)
		let group = Task.group

		let rawTask = Foundation.Task()
		rawTask.launchPath = task.launchPath
		rawTask.arguments = task.arguments

		if let cwd = task.workingDirectoryPath {
			rawTask.currentDirectoryPath = cwd
		}

		if let env = task.environment {
			rawTask.environment = env
		}

		var stdinProducer: SignalProducer<(), TaskError> = .empty

		if let input = standardInput {
			switch Pipe.create(queue, group) {
			case let .Success(pipe):
				rawTask.standardInput = pipe.readHandle

				stdinProducer = pipe.writeDataFromProducer(input).on(started: {
					close(pipe.readFD)
				})

			case let .Failure(error):
				observer.sendFailed(error)
				return
			}
		}

		SignalProducer(result: Pipe.create(queue, group) &&& Pipe.create(queue, group))
			.flatMap(.merge) { stdoutPipe, stderrPipe -> SignalProducer<TaskEvent<Data>, TaskError> in
				let stdoutProducer = stdoutPipe.transferReadsToProducer()
				let stderrProducer = stderrPipe.transferReadsToProducer()

				enum Aggregation {
					case value(Data)
					case failed(TaskError)
					case interrupted

					var producer: Pipe.ReadProducer {
						switch self {
						case let .value(data):
							return .init(value: data)
						case let .failed(error):
							return .init(error: error)
						case .interrupted:
							return SignalProducer { observer, _ in
								observer.sendInterrupted()
							}
						}
					}
				}

				return SignalProducer { observer, disposable in
					//TODO: Swift 3 API guidelines?
					func startAggregating(_ producer: Pipe.ReadProducer) -> Pipe.ReadProducer {
						let aggregated = MutableProperty<Aggregation?>(nil)

						producer.startWithSignal { signal, signalDisposable in
							disposable += signalDisposable

							var aggregate = Data()
							signal.observe(Observer(next: { data in
								observer.sendNext(.standardOutput(data))
								aggregate.append(data)
							}, failed: { error in
								observer.sendFailed(error)
								aggregated.value = .failed(error)
							}, completed: {
								aggregated.value = .value(aggregate)
							}, interrupted: {
								aggregated.value = .interrupted
							}))
						}

						return aggregated.producer
							.ignoreNil()
							.flatMap(.concat) { $0.producer }
					}

					let stdoutAggregated = startAggregating(stdoutProducer)
					let stderrAggregated = startAggregating(stderrProducer)

					rawTask.standardOutput = stdoutPipe.writeHandle
					rawTask.standardError = stderrPipe.writeHandle

					group.enter()
					rawTask.terminationHandler = { nstask in
						let terminationStatus = nstask.terminationStatus
						if terminationStatus == EXIT_SUCCESS {
							// Wait for stderr to finish, then pass
							// through stdout.
							disposable += stderrAggregated
								.then(stdoutAggregated)
								.map(TaskEvent.success)
								.start(observer)
						} else {
							// Wait for stdout to finish, then pass
							// through stderr.
							disposable += stdoutAggregated
								.then(stderrAggregated)
								.flatMap(.concat) { data -> SignalProducer<TaskEvent<Data>, TaskError> in
									let errorString = (data.count > 0 ? NSString(data: data, encoding: String.Encoding.utf8.rawValue) as? String : nil)
									return SignalProducer(error: .shellTaskFailed(task, exitCode: terminationStatus, standardError: errorString))
								}
								.start(observer)
						}
						group.leave()
					}
					
					observer.sendNext(.launch(task))
					rawTask.launch()
					close(stdoutPipe.writeFD)
					close(stderrPipe.writeFD)

					stdinProducer.startWithSignal { signal, signalDisposable in
						disposable += signalDisposable
					}

					disposable.addDisposable {
						rawTask.terminate()
					}
				}
			}
			.startWithSignal { signal, taskDisposable in
				disposable.addDisposable(taskDisposable)
				signal.observe(observer)
			}
	}
}
