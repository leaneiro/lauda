import Testing

/// Parent of the suites that hold a document open where another suite
/// would feel it, so they run one after another (a suite is only
/// serialized against the others under the same parent):
///
/// - in the process's one document controller, where closing every tab
///   closes every document, whoever opened it;
/// - with its panes drawing in a window, which takes frames from a suite
///   that times a WebKit page.
@Suite(.serialized) enum OpenDocumentsSuites {}
