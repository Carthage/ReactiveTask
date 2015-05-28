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
		it("should launch a task that writes to stdout") {
			let result = launchTask(TaskDescription(launchPath: "/bin/echo", arguments: [ "foobar" ]))
				|> reduce(NSMutableData()) { aggregated, event in
					switch event {
					case let .StandardOutput(data):
						aggregated.appendData(data)

					default:
						break
					}

					return aggregated
				}
				|> single

			expect(result).notTo(beNil())
			if let data = result?.value {
				expect(NSString(data: data, encoding: NSUTF8StringEncoding)).to(equal("foobar\n"))
			}
		}

		it("should launch a task that writes to stderr") {
			let result = launchTask(TaskDescription(launchPath: "/usr/bin/stat", arguments: [ "not-a-real-file" ]))
				|> reduce(NSMutableData()) { aggregated, event in
					switch event {
					case let .StandardError(data):
						aggregated.appendData(data)

					default:
						break
					}

					return aggregated
				}
				|> single

			expect(result).notTo(beNil())
			if let data = result?.value {
				expect(NSString(data: data, encoding: NSUTF8StringEncoding)).to(equal("stat: not-a-real-file: stat: No such file or directory\n"))
			}
		}

		it("should launch a task with standard input") {
			let strings = [ "foo\n", "bar\n", "buzz\n", "fuzz\n" ]
			let data = strings.map { $0.dataUsingEncoding(NSUTF8StringEncoding)! }

			let result = launchTask(TaskDescription(launchPath: "/usr/bin/sort", standardInput: SignalProducer(values: data)))
				|> map { event in event.value }
				|> ignoreNil
				|> single

			expect(result).notTo(beNil())
			if let data = result?.value {
				expect(NSString(data: data, encoding: NSUTF8StringEncoding)).to(equal("bar\nbuzz\nfoo\nfuzz\n"))
			}
		}
	}
}
