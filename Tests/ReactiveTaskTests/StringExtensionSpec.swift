import Quick
import Nimble
@testable import ReactiveTask

class StringExtensionSpec: QuickSpec {
	override func spec() {
		describe("escapingWhitespaces") {
			it("should escape whitespace characters") {
				expect("a b c".escapingWhitespaces).to(equal("a\\ b\\ c"))
				expect("d\te\tf".escapingWhitespaces).to(equal("d\\\te\\\tf"))
			}

			it("should not change the original string if it does not contain whitespaces") {
				expect("ReactiveTask").to(equal("ReactiveTask"))
			}
		}
	}
}
