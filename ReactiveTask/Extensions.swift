//
//  Extensions.swift
//  ReactiveTask
//
//  Created by Syo Ikeda on 10/1/15.
//  Copyright © 2015 Carthage. All rights reserved.
//

import ReactiveCocoa

extension Signal {

	/// Bring back the `observe` overload. The `observeNext` or pattern matching
	/// on `observe(Event)` is still annoying in practice and more verbose. This is
	/// also likely to change in a later RAC 4 alpha.
	internal func observe(next next: (T -> ())? = nil, error: (E -> ())? = nil, completed: (() -> ())? = nil, interrupted: (() -> ())? = nil) -> Disposable? {
		return self.observe { (event: Event<T, E>) in
			switch event {
			case let .Next(value):
				next?(value)
			case let .Error(err):
				error?(err)
			case .Completed:
				completed?()
			case .Interrupted:
				interrupted?()
			}
		}
	}
}

extension SignalProducer {

	/// Bring back the `start` overload. The `startNext` or pattern matching
	/// on `start(Event)` is annoying in practice and more verbose. This is also
	/// likely to change in a later RAC 4 alpha.
	internal func start(next next: (T -> ())? = nil, error: (E -> ())? = nil, completed: (() -> ())? = nil, interrupted: (() -> ())? = nil) -> Disposable? {
		return self.start { (event: Event<T, E>) in
			switch event {
			case let .Next(value):
				next?(value)
			case let .Error(err):
				error?(err)
			case .Completed:
				completed?()
			case .Interrupted:
				interrupted?()
			}
		}
	}
}
