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
public enum ReactiveTaskError {
	/// A shell task exited unsuccessfully.
	case ShellTaskFailed(exitCode: Int32, standardError: String?)

	/// An error was returned from a POSIX API.
	case POSIXError(Int32)
}

extension ReactiveTaskError: ErrorType {
	public var _domain: String {
		switch self {
		case .ShellTaskFailed:
			return "org.carthage.ReactiveTask"
		case POSIXError:
			return NSPOSIXErrorDomain
		}
	}
	
	public var _code: Int {
		switch self {
		case .ShellTaskFailed:
			return 0
		case let POSIXError(code):
			return Int(code)
		}
	}
}

extension ReactiveTaskError: CustomStringConvertible {
	public var description: String {
		switch self {
		case let .ShellTaskFailed(exitCode, standardError):
			var description = "A shell task failed with exit code \(exitCode)"
			if let standardError = standardError {
				description += ":\n\(standardError)"
			}

			return description

		case let .POSIXError(code):
			return NSError(domain: NSPOSIXErrorDomain, code: Int(code), userInfo: nil).description
		}
	}
}
