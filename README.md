# ReactiveTask
ReactiveTask is a Swift framework for launching shell tasks (processes), built using [ReactiveSwift](https://github.com/ReactiveCocoa/ReactiveSwift).

```swift
let strings = [ "foo\n", "bar\n", "buzz\n", "fuzz\n" ]
let input = SignalProducer<Data, NoError>(values: strings.map { $0.data(using: .utf8)! })
let task = Task("/usr/bin/sort")

// Run the task, ignoring the output, and do something with the final result.
let result: Result<String, TaskError>? = task.launch(standardInput: input)
    .ignoreTaskData()
    .map { String(data: $0, encoding: .utf8) }
    .ignoreNil()
    .single()
print("Output of `\(task)`: \(result?.value ?? "")")

// Start the task and print all the events, which includes all the output
// that was received.
task.launch(standardInput: input)
    .flatMapTaskEvents(.concat) { data in
        return SignalProducer(value: String(data: data, encoding: .utf8))
    }
    .startWithNext { (event: TaskEvent) in
        switch event {
        case let .launch(task):
            print("launched task: \(task)")

        case let .standardError(data):
            print("stderr: \(data)")

        case let .standardOutput(data):
            print("stdout: \(data)")

        case let .success(string):
            print("value: \(string ?? "")")
        }
    }
```

For examples of how to use ReactiveTask, see the Xcode and Git integration code from the [CarthageKit](https://github.com/Carthage/Carthage) framework.

## License
ReactiveTask is released under the [MIT license](LICENSE.md).
