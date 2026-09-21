import Foundation
import Testing
@testable import Lauda

struct TypingSubstitutionsTests {
    private func substitute(text: String, typing: String, at location: Int) -> (NSRange, String)? {
        TypingSubstitutions.substitution(
            in: text as NSString,
            affectedRange: NSRange(location: location, length: 0),
            replacement: typing
        )
    }

    @Test func rightArrow() {
        let result = substitute(text: "a -", typing: ">", at: 3)
        #expect(result?.0 == NSRange(location: 2, length: 1))
        #expect(result?.1 == "→")
    }

    @Test func leftArrow() {
        let result = substitute(text: "a <", typing: "-", at: 3)
        #expect(result?.0 == NSRange(location: 2, length: 1))
        #expect(result?.1 == "←")
    }

    @Test func noSubstitutionWithoutPriorCharacter() {
        #expect(substitute(text: "abc", typing: ">", at: 3) == nil)
        #expect(substitute(text: "", typing: ">", at: 0) == nil)
    }

    @Test func plainDashIsUntouched() {
        #expect(substitute(text: "a b", typing: "-", at: 3) == nil)
    }
}
