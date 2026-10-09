import WebKit

extension WKWebView {
    /// Off screen, WebKit takes the page for hidden and holds its rendering
    /// updates: CSS transitions, animation frames, scroll events. This is
    /// WebKit's own switch for that, called through its selector (tests
    /// only; the app's pages are on screen). A page in view draws through
    /// Metal, so the switch stays off where that can't be done.
    func keepRunningOffscreen() {
        guard TestMachine.drawsWithMetal else { return }
        let occlusion = NSSelectorFromString("_setWindowOcclusionDetectionEnabled:")
        guard responds(to: occlusion), let setter = method(for: occlusion) else { return }
        typealias Setter = @convention(c) (AnyObject, Selector, Bool) -> Void
        unsafeBitCast(setter, to: Setter.self)(self, occlusion, false)
    }
}
