import AppKit
import SwiftUI

/// Every open document's panes, one set on top of the other, with only the
/// selected document's showing. Switching tabs changes which set is hidden:
/// nothing is loaded or rendered again, so it is instant, and a document
/// comes back exactly as it was left.
///
/// AppKit does the stacking because a hidden NSView is out of everything at
/// once: drawing, the mouse, the keyboard loop and accessibility. The
/// workspace keeps the stack current; SwiftUI only gives it its place.
struct DocumentStack: NSViewRepresentable {
    let workspace: Workspace

    func makeNSView(context: Context) -> DocumentStackView {
        workspace.stack
    }

    func updateNSView(_ stack: DocumentStackView, context: Context) {}
}

final class DocumentStackView: NSView {
    private var hosts: [ObjectIdentifier: NSHostingView<DocumentPanes>] = [:]
    private weak var shown: MarkdownDocument?
    private weak var workspace: Workspace?
    private var keyboardAttempts = 0

    /// A document's set of panes, while the document is open.
    func panes(of document: MarkdownDocument) -> NSView? {
        hosts[ObjectIdentifier(document)]
    }

    func show(_ documents: [MarkdownDocument], selected: MarkdownDocument?, in workspace: Workspace) {
        self.workspace = workspace
        let open = Set(documents.map(ObjectIdentifier.init))
        for (id, host) in hosts where !open.contains(id) {
            host.removeFromSuperview()
            hosts[id] = nil
        }
        for document in documents where hosts[ObjectIdentifier(document)] == nil {
            let host = NSHostingView(rootView: DocumentPanes(document: document, workspace: workspace))
            // The stack decides the size; the panes fill it.
            host.sizingOptions = []
            host.frame = bounds
            host.autoresizingMask = [.width, .height]
            host.isHidden = true
            addSubview(host)
            hosts[ObjectIdentifier(document)] = host
        }

        guard selected !== shown else { return }
        // Whatever has the keyboard belongs to the panes going out of sight.
        window?.makeFirstResponder(nil)
        let selectedID = selected.map(ObjectIdentifier.init)
        for (id, host) in hosts {
            host.isHidden = id != selectedID
        }
        shown = selected
        keyboardAttempts = 0
        giveKeyboardToShownPanes()
    }

    /// The panes in front get the keyboard, so typing goes on in the tab
    /// that was just picked. A document that was just opened has no panes
    /// yet, so this tries again shortly; it never takes the keyboard from
    /// something that got it in the meantime.
    private func giveKeyboardToShownPanes() {
        guard let document = shown, let workspace else { return }
        if let window, window.firstResponder !== window { return }
        if document.takeKeyboard(in: workspace.viewMode) { return }
        keyboardAttempts += 1
        guard keyboardAttempts < 80 else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.025) { [weak self, weak document] in
            guard let self, let document, self.shown === document else { return }
            self.giveKeyboardToShownPanes()
        }
    }
}
