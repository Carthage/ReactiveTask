//
//  Errors.swift
//  ReactiveTask
//
//  Created by Justin Spahr-Summers on 2014-12-01.
//  Copyright (c) 2014 Carthage. All rights reserved.
//

import Foundation

/// Possible error codes within `ReactiveTaskErrorDomain`.
public enum ReactiveTaskError: Int {
	/// The domain for all errors originating within ReactiveTask.
	public static let domain: NSString = "org.carthage.ReactiveTask"

	/// In a user info dictionary, associated with the exit code from a child
	/// process.
	public static let exitCodeKey: NSString = "ReactiveTaskErrorExitCode"

	/// In a user info dictionary, associated with any accumulated stderr
	/// string.
	public static let standardErrorKey: NSString = "ReactiveTaskErrorStandardError"

	/// A shell task exited unsuccessfully.
	case ShellTaskFailed
}
