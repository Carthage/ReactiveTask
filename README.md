# ReactiveTask
ReactiveTask is a Swift framework for launching shell tasks (processes), built using [ReactiveCocoa](https://github.com/ReactiveCocoa/ReactiveCocoa).

```swift
let strings = [ "foo\n", "bar\n", "buzz\n", "fuzz\n" ]
let input = SignalProducer<NSData, NoError>(values: strings.map { $0.dataUsingEncoding(NSUTF8StringEncoding)! })
let task = Task("/usr/bin/sort")

// Run the task, ignoring the output, and do something with the final result.
let result: Result<String, TaskError>? = launchTask(task, standardInput: input)
    .ignoreTaskData()
    .map { String(data: $0, encoding: NSUTF8StringEncoding) }
    .ignoreNil()
    .single()
print("Output of `\(task)`: \(result?.value ?? "")")

// Start the task and print all the events, which includes all the output
// that was received.
launchTask(task, standardInput: input)
    .flatMapTaskEvents(.Concat) { data in
        return SignalProducer(value: String(data: data, encoding: NSUTF8StringEncoding))
    }
    .startWithNext { (event: TaskEvent) in
        switch event {
        case let .Launch(task):
            print("launched task: \(task)")

        case let .StandardError(data):
            print("stderr: \(data)")

        case let .StandardOutput(data):
            print("stdout: \(data)")

        case let .Success(string):
            print("value: \(string)")
        }
    }
```

For examples of how to use ReactiveTask, see the Xcode and Git integration code from the [CarthageKit](https://github.com/Carthage/Carthage) framework.

## License
ReactiveTask is released under the [MIT license](LICENSE.md).
