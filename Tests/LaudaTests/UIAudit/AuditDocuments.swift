/// The documents the audit opens: made up, and the same in every run, so
/// two runs can be compared picture by picture.
enum AuditDocuments {
    static let notes = """
        # Field notes

        A short document with a bit of **everything** the preview draws: *emphasis*,
        ~~struck text~~, `inline code` and a [link](https://example.com).

        ## A list and a quote

        - the first item
        - the second, with a longer line that has to wrap around when the pane gets narrow enough for it
        - [ ] a task still open
        - [x] a task done

        > The quote keeps the reader in the text.

        ## Code

        ```swift
        struct Page {
            let title: String
            var words = 0
        }
        ```

        ## A table

        | Pane | Shows |
        |---|---|
        | Editor | the Markdown |
        | Preview | the page |

        ## The long part

        \(paragraphs)
        """

    static let ideas = """
        # Ideas

        1. One thing at a time.
        2. The text first.

        The rest of the page is here to be searched: the word *the* comes up more than once.
        """

    static let short = "# Short\n\nA page with almost nothing on it.\n"

    static let longName = "a-document-with-a-very-long-name-that-the-tab-has-to-cut-somewhere.md"

    private static let paragraphs = (1...12).map { number in
        "Paragraph \(number). The page goes on for long enough to scroll, so the panes have "
            + "something below the fold and the status bar has words to count."
    }.joined(separator: "\n\n")
}
