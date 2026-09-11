import XCTest
@testable import MarkEditor

final class OutlineTests: XCTestCase {
    func testCollectsHeadingsWithLevelsTitlesAndLines() {
        let markdown = """
        # Título

        texto

        ## Seção *um*

        Sub
        ---

        ```
        # não é título
        ```

        ### Três
        """
        let items = Outline.items(in: markdown)
        XCTAssertEqual(items.map(\.level), [1, 2, 2, 3])
        XCTAssertEqual(items.map(\.title), ["Título", "Seção um", "Sub", "Três"])
        XCTAssertEqual(items.map(\.line), [0, 4, 6, 13])
        XCTAssertEqual(items.map(\.id), [0, 1, 2, 3])
    }

    func testSupportsAllSixLevels() {
        let items = Outline.items(in: "# 1\n## 2\n### 3\n#### 4\n##### 5\n###### 6\n####### 7 não é título")
        XCTAssertEqual(items.map(\.level), [1, 2, 3, 4, 5, 6])
    }

    func testEmptyHeadingsAreSkipped() {
        XCTAssertEqual(Outline.items(in: "#\n\n## Real").map(\.title), ["Real"])
    }

    func testDocumentWithoutHeadingsHasEmptyOutline() {
        XCTAssertTrue(Outline.items(in: "só texto\n\n- lista").isEmpty)
    }
}
