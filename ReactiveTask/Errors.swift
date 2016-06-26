//
//  Errors.swift
//  ReactiveTask
//
//  Created by Justin Spahr-Summers on 2014-12-01.
//  Copyright (c) 2014 Carthage. All rights reserved.
//

import Foundation
import ReactiveCocoa

/// An error originating from ReactiveTask.
public enum TaskError: ErrorProtocol, Equatable {
	/// A shell task exited unsuccessfully.
	case shellTaskFailed(Task, exitCode: Int32, standardError: String?)

	/// An error was returned from a POSIX API.
	case POSIXError(Int32)
}

extension TaskError: CustomStringConvertible {
	public var description: String {
		switch self {
		case let .shellTaskFailed(task, exitCode, standardError):
			var description = "A shell task (\(task)) failed with exit code \(exitCode)"
			if let standardError = standardError {
				description += ":\n\(standardError)"
			}

			return description

		case let .POSIXError(code):
			return NSError(domain: NSPOSIXErrorDomain, code: Int(code), userInfo: nil).description
		}
	}
}

public func == (lhs: TaskError, rhs: TaskError) -> Bool {
	switch (lhs, rhs) {
	case let (.shellTaskFailed(lhsTask, lhsCode, lhsErr), .shellTaskFailed(rhsTask, rhsCode, rhsErr)):
		return lhsTask == rhsTask && lhsCode == rhsCode && lhsErr == rhsErr

	case let (.POSIXError(lhsCode), .POSIXError(rhsCode)):
		return lhsCode == rhsCode

	default:
		return false
	}
}
