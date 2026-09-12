import Foundation
import Testing
@testable import MarkEditor

struct OutlineTests {
    @Test func collectsHeadingsWithLevelsTitlesAndLines() {
        let markdown = """
        # Title

        text

        ## Section *one*

        Sub
        ---

        ```
        # not a heading
        ```

        ### Three
        """
        let items = Outline.items(in: markdown)
        #expect(items.map(\.level) == [1, 2, 2, 3])
        #expect(items.map(\.title) == ["Title", "Section one", "Sub", "Three"])
        #expect(items.map(\.line) == [0, 4, 6, 13])
        #expect(items.map(\.id) == [0, 1, 2, 3])
    }

    @Test func supportsAllSixLevels() {
        let items = Outline.items(in: "# 1\n## 2\n### 3\n#### 4\n##### 5\n###### 6\n####### 7 is not a heading")
        #expect(items.map(\.level) == [1, 2, 3, 4, 5, 6])
    }

    @Test func emptyHeadingsAreSkipped() {
        #expect(Outline.items(in: "#\n\n## Real").map(\.title) == ["Real"])
    }

    @Test func documentWithoutHeadingsHasEmptyOutline() {
        #expect(Outline.items(in: "just text\n\n- list").isEmpty)
    }
}
