import Testing

/// Parent of the suites that open documents in the process's one document
/// controller. Closing every tab closes every document in it, whoever
/// opened them, so these suites run one after another: a suite is only
/// serialized against the others under the same parent.
@Suite(.serialized) enum OpenDocumentsSuites {}
