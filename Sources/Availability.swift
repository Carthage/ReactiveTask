//
//  Availability.swift
//  ReactiveTask
//
//  Created by Syo Ikeda on 2016/11/07.
//  Copyright © 2016年 Carthage. All rights reserved.
//

import Foundation
import ReactiveSwift
import enum Result.NoError

@available(*, unavailable, renamed: "Task.launch(self:)")
public func launchTask(_ task: Task) -> SignalProducer<TaskEvent<Data>, TaskError> {
	fatalError()
}

@available(*, unavailable, renamed: "Task.launch(self:standardInput:)")
public func launchTask(_ task: Task, standardInput: SignalProducer<Data, NoError>?) -> SignalProducer<TaskEvent<Data>, TaskError> {
	fatalError()
}

extension TaskError {
	@available(*, unavailable, renamed: "shellTaskFailed(_:exitCode:standardError:)")
	public static func ShellTaskFailed(_ task: Task, exitCode: Int32, standardError: String?) -> TaskError {
		return .shellTaskFailed(task, exitCode: exitCode, standardError: standardError)
	}

	@available(*, unavailable, renamed: "posixError(_:)")
	public static func POSIXError(_ code: Int32) -> TaskError {
		return .posixError(code)
	}
}

extension TaskEvent {
	@available(*, unavailable, renamed: "launch(_:)")
	public static func Launch(_ task: Task) -> TaskEvent {
		return .launch(task)
	}

	@available(*, unavailable, renamed: "standardOutput(_:)")
	public static func StandardOutput(_ data: Data) -> TaskEvent {
		return .standardOutput(data)
	}

	@available(*, unavailable, renamed: "standardError(_:)")
	public static func StandardError(_ data: Data) -> TaskEvent {
		return .standardError(data)
	}

	@available(*, unavailable, renamed: "success(_:)")
	public static func Success(_ value: T) -> TaskEvent {
		return .success(value)
	}

}
