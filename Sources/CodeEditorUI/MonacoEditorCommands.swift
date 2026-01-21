import Foundation
import WebKit

public final class MonacoEditorCommands: EditorCommands {
    public weak var textView: EditorTextView? {
        didSet {
            flushCallbacksIfReady()
        }
    }

    private weak var webView: WKWebView?
    private var pendingCallbacks: [(EditorTextView) -> Void] = []

    public init(webView: WKWebView?, textView: EditorTextView?) {
        self.webView = webView
        self.textView = textView
    }

    public func attach(webView: WKWebView?, textView: EditorTextView?) {
        self.webView = webView
        self.textView = textView
        flushCallbacksIfReady()
    }

    public var isFirstResponder: Bool {
#if os(macOS)
        guard let webView else { return false }
        return webView.window?.firstResponder === webView
#else
        return webView?.isFirstResponder ?? false
#endif
    }

    public func onTextViewReady(callback: @escaping (EditorTextView) -> Void) {
        if let textView {
            callback(textView)
        } else {
            pendingCallbacks.append(callback)
        }
    }

    public func requestGoto(line: Int, completion: (() -> Void)? = nil) {
        let lineNumber = line + 1
        runJS("window.gotoLine(\(lineNumber));") {
            completion?()
        }
    }

    public func becomeFirstResponder() {
#if os(macOS)
        if let webView {
            if let window = webView.window {
                window.makeFirstResponder(webView)
            } else {
                DispatchQueue.main.async { [weak webView] in
                    webView?.window?.makeFirstResponder(webView)
                }
            }
        }
#else
        _ = webView?.becomeFirstResponder()
#endif
        runJS("window.focusEditor();")
    }

    public func requestFind() {
        runJS("window.runEditorAction('actions.find');")
    }

    public func requestFindAndReplace() {
        runJS("window.runEditorAction('editor.action.startFindReplaceAction');")
    }

    public func undo() {
        runJS("window.undoEditor();")
    }

    public func redo() {
        runJS("window.redoEditor();")
    }

    public func toggleInlineComment(_ delimiter: String) {
        _ = delimiter
        runJS("window.runEditorAction('editor.action.commentLine');")
    }

    public func indent() {
        runJS("window.runEditorAction('editor.action.indentLines');")
    }

    public func unIndent() {
        runJS("window.runEditorAction('editor.action.outdentLines');")
    }

    private func flushCallbacksIfReady() {
        guard let textView else { return }
        if pendingCallbacks.isEmpty {
            return
        }
        let callbacks = pendingCallbacks
        pendingCallbacks.removeAll()
        for callback in callbacks {
            callback(textView)
        }
    }

    private func runJS(_ script: String, completion: (() -> Void)? = nil) {
        guard let webView else {
            completion?()
            return
        }
        webView.evaluateJavaScript(script) { _, _ in
            completion?()
        }
    }
}
