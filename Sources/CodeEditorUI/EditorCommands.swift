import Foundation

#if canImport(UIKit)
import RunestoneUI
#endif

@MainActor
public protocol EditorCommands: AnyObject {
    var isFirstResponder: Bool { get }
    func onTextViewReady(callback: @escaping (EditorTextView) -> Void)
    func requestGoto(line: Int, completion: (() -> Void)?)
    func becomeFirstResponder()
    func requestFind()
    func requestFindAndReplace()
    func undo()
    func redo()
    func toggleInlineComment(_ delimiter: String)
    func indent()
    func unIndent()
}

public extension EditorCommands {
    func requestGoto(line: Int) {
        requestGoto(line: line, completion: nil)
    }
}

public final class NoopEditorCommands: EditorCommands {
    public init() {}

    public var isFirstResponder: Bool { false }

    public func onTextViewReady(callback: @escaping (EditorTextView) -> Void) {
    }

    public func requestGoto(line: Int, completion: (() -> Void)? = nil) {
        completion?()
    }

    public func becomeFirstResponder() {}
    public func requestFind() {}
    public func requestFindAndReplace() {}
    public func undo() {}
    public func redo() {}
    public func toggleInlineComment(_ delimiter: String) {
        _ = delimiter
    }
    public func indent() {}
    public func unIndent() {}
}

#if canImport(UIKit)
public final class RunestoneEditorCommands: EditorCommands {
    private let commands: TextViewCommands

    public init(commands: TextViewCommands) {
        self.commands = commands
    }

    public var textView: EditorTextView? {
        commands.textView
    }

    public var isFirstResponder: Bool {
        commands.textView?.isFirstResponder ?? false
    }

    public func onTextViewReady(callback: @escaping (EditorTextView) -> Void) {
        commands.onTextViewReady { textView in
            callback(textView)
        }
    }

    public func requestGoto(line: Int, completion: (() -> Void)? = nil) {
        commands.requestGoto(line: line, completion: completion)
    }

    public func becomeFirstResponder() {
        commands.becomeFirstResponder()
    }

    public func requestFind() {
        commands.requestFind()
    }

    public func requestFindAndReplace() {
        commands.requestFindAndReplace()
    }

    public func undo() {
        commands.textView?.undoManager?.undo()
    }

    public func redo() {
        commands.textView?.undoManager?.redo()
    }

    public func toggleInlineComment(_ delimiter: String) {
        commands.toggleInlineComment(delimiter)
    }

    public func indent() {
        commands.indent()
    }

    public func unIndent() {
        commands.unIdent()
    }
}

#endif

#if canImport(UIKit)
extension TextViewCommands: EditorCommands {
    public var isFirstResponder: Bool {
#if os(macOS)
        guard let textView else { return false }
        return textView.window?.firstResponder === textView
#else
        return textView?.isFirstResponder ?? false
#endif
    }

    public func onTextViewReady(callback: @escaping (EditorTextView) -> Void) {
        onTextViewReady { (textView: TextView) in
            callback(textView)
        }
    }

    public func undo() {
        textView?.undoManager?.undo()
    }

    public func redo() {
        textView?.undoManager?.redo()
    }

    public func unIndent() {
        unIdent()
    }
}
#endif
