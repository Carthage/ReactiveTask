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
		let standardOutput = MutableProperty(NSData())
		let standardError = MutableProperty(NSData())

		beforeEach {
			standardOutput.value = NSData()
			standardError.value = NSData()
		}

		func accumulatingSinkForProperty(property: MutableProperty<NSData>) -> SinkOf<NSData> {
			let (signal, sink) = Signal<NSData, NoError>.pipe()

			property <~ signal
						|> scan(NSData()) { (accum, data) in
							let buffer = accum.mutableCopy() as! NSMutableData
							buffer.appendData(data)

							return buffer
						}

			return SinkOf { data in
				sendNext(sink, data)
			}
		}

		it("should launch a task that writes to stdout") {
			let desc = TaskDescription(launchPath: "/bin/echo", arguments: [ "foobar" ])
			let task = launchTask(desc, standardOutput: accumulatingSinkForProperty(standardOutput))
			expect(standardOutput.value).to(equal(NSData()))

			let result = task |> wait
			expect(result.value).notTo(beNil())
			expect(NSString(data: standardOutput.value, encoding: NSUTF8StringEncoding)).to(equal("foobar\n"))
		}

		it("should launch a task that writes to stderr") {
			let desc = TaskDescription(launchPath: "/usr/bin/stat", arguments: [ "not-a-real-file" ])
			let task = launchTask(desc, standardError: accumulatingSinkForProperty(standardError))
			expect(standardError.value).to(equal(NSData()))

			let result = task |> wait
			expect(result.value).to(beNil())
			expect(NSString(data: standardError.value, encoding: NSUTF8StringEncoding)).to(equal("stat: not-a-real-file: stat: No such file or directory\n"))
		}

		it("should launch a task with standard input") {
			let strings = [ "foo\n", "bar\n", "buzz\n", "fuzz\n" ]
			let data = strings.map { $0.dataUsingEncoding(NSUTF8StringEncoding)! }

			let desc = TaskDescription(launchPath: "/usr/bin/sort", standardInput: SignalProducer(values: data))
			let task = launchTask(desc, standardOutput: accumulatingSinkForProperty(standardOutput))

			let result = task |> wait
			expect(result.value).notTo(beNil())
			expect(NSString(data: standardOutput.value, encoding: NSUTF8StringEncoding)).to(equal("bar\nbuzz\nfoo\nfuzz\n"))
		}
	}
}
