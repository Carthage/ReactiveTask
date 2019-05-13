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

			it("should escape the NULL terminator with the 'symbol for null' glyph (U+2400)") {
				expect("abc\0".escapingWhitespaces).to(equal("abc␀"))
			}

			it("should not change the original string if it does not contain whitespaces") {
				expect("ReactiveTask").to(equal("ReactiveTask"))
			}
		}
	}
}
