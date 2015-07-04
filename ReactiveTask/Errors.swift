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

extension ReactiveTaskError: ReactiveCocoa.ErrorType {
	public var nsError: NSError {
		switch self {
		case let .POSIXError(code):
			return NSError(domain: NSPOSIXErrorDomain, code: Int(code), userInfo: nil)

		default:
			return NSError(domain: "org.carthage.ReactiveTask", code: 0, userInfo: [
				NSLocalizedDescriptionKey: self.description
			])
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

		case .POSIXError:
			return nsError.description
		}
	}
}
