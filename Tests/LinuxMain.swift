import XCTest
import Quick

@testable import ReactiveTaskTests

Quick.QCKMain([
	StringExtensionSpec.self,
	TaskSpec.self,
])
