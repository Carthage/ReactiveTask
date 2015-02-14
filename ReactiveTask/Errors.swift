//
//  Errors.swift
//  ReactiveTask
//
//  Created by Justin Spahr-Summers on 2014-12-01.
//  Copyright (c) 2014 Carthage. All rights reserved.
//

import Foundation

/// An error originating from ReactiveTask.
public enum ReactiveTaskError {
	/// A shell task exited unsuccessfully.
	case ShellTaskFailed(exitCode: Int, standardError: String?)
}

extension ReactiveTaskError: Printable {
	public var description: String {
		switch self {
		case let .ShellTaskFailed(exitCode, standardError):
			var description = "A shell task failed with exit code \(exitCode)"
			if let standardError = standardError {
				description += ":\n\(standardError)"
			}
			
			return description
		}
	}
}
