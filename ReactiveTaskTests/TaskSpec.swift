//
//  TaskSpec.swift
//  ReactiveTask
//
//  Created by Justin Spahr-Summers on 2014-10-11.
//  Copyright (c) 2014 Carthage. All rights reserved.
//

import Foundation
import Nimble
import Quick
import ReactiveCocoa
import ReactiveTask
import Result

class TaskSpec: QuickSpec {
	override func spec() {
		it("should notify that a task is about to be launched") {
			var isLaunched: Bool = false

			let task = Task("/usr/bin/true")
			let result = launchTask(task)
				.on(next: { event in
					if case let .Launch(launched) = event {
						isLaunched = true
						expect(launched) == task
					}
				})
				.wait()

			expect(result.error).to(beNil())
			expect(isLaunched) == true
		}

		it("should launch a task that writes to stdout") {
			let result = launchTask(Task("/bin/echo", arguments: [ "foobar" ]))
				.reduce(NSMutableData()) { aggregated, event in
					if case let .StandardOutput(data) = event {
						aggregated.appendData(data)
					}

					return aggregated
				}
				.single()

			expect(result).notTo(beNil())
			if let data = result?.value {
				expect(NSString(data: data, encoding: NSUTF8StringEncoding)).to(equal("foobar\n"))
			}
		}

		it("should launch a task that writes to stderr") {
			let aggregated = NSMutableData()
			let result = launchTask(Task("/usr/bin/stat", arguments: [ "not-a-real-file" ]))
				.reduce(aggregated) { aggregated, event in
					if case let .StandardError(data) = event {
						aggregated.appendData(data)
					}

					return aggregated
				}
				.single()

			expect(result).notTo(beNil())
			expect(result?.error).notTo(beNil())
			expect(NSString(data: aggregated, encoding: NSUTF8StringEncoding)).to(equal("stat: not-a-real-file: stat: No such file or directory\n"))
		}

		it("should launch a task with standard input") {
			let strings = [ "foo\n", "bar\n", "buzz\n", "fuzz\n" ]
			let data = strings.map { $0.dataUsingEncoding(NSUTF8StringEncoding)! }

			let result = launchTask(Task("/usr/bin/sort"), standardInput: SignalProducer(values: data))
				.map { event in event.value }
				.ignoreNil()
				.single()

			expect(result).notTo(beNil())
			if let data = result?.value {
				expect(NSString(data: data, encoding: NSUTF8StringEncoding)).to(equal("bar\nbuzz\nfoo\nfuzz\n"))
			}
		}

		it("should error correctly") {
			let task = Task("/usr/bin/stat", arguments: [ "not-a-real-file" ])
			let result = launchTask(task)
				.wait()

			expect(result).notTo(beNil())
			expect(result.error).notTo(beNil())
			expect(result.error) == TaskError.ShellTaskFailed(task, exitCode: 1, standardError: "stat: not-a-real-file: stat: No such file or directory\n")
			if let error = result.error {
				expect(error.description) == "A shell task (/usr/bin/stat not-a-real-file) failed with exit code 1:\nstat: not-a-real-file: stat: No such file or directory\n"
			}
		}
	}
}
