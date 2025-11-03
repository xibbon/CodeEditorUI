//
//  Dummy-MacOS-TextView.swift
//  CodeEditorUI
//
//  Created by Miguel de Icaza on 11/3/25.
//
#if os(macOS)
import AppKit

public protocol TextViewUIDelegate {

}

public struct UITextPosition {

}

public struct UITextRange {

}

public struct TextLocation {
    var lineNumber: Int
    var column: Int
}


/// Character pair to be registered with a text view.
public protocol CharacterPair {
    /// Leading component of the character pair. For example an opening bracket.
    var leading: String { get }
    /// Trailing component of the character pair. For example a closing bracket.
    var trailing: String { get }
}

public class TextView: NSView {
    public var selectedRange: NSRange
    public var contentOffset: NSPoint = .zero

    public func textLocation(at: Int) -> TextLocation? {
        nil
    }
    
    public required init?(coder: NSCoder) {
        fatalError()
    }

    public override init(frame frameRect: NSRect) {
        selectedRange = NSRange(location: 0, length: 0)
        super.init(frame: frameRect)
    }

    public func text(in: NSRange) -> String? {
        nil
    }

    public func replace(_ range: NSRange, withText text: String) {
    }
}

public class TextViewCommands {
    public init () {
    }

    /// The textview that provides the backing services
    public weak var textView: TextView? {
        return nil
    }

    var pendingTextView: [(TextView) -> ()] = []

    /// The TextView might not be instantiated when your code runs, use this to call a method when the textView is realized
    public func onTextViewReady(callback: @escaping (TextView)->()) {
        if let textView {
            callback(textView)
        } else {
            pendingTextView.append(callback)
        }
    }

    /// Requests that the TextView navigates to the specified line
    public func requestGoto(line: Int, completion: (() -> ())? = nil) {
        print("TextViewCommand: requestGoto")
    }

    public func becomeFirstResponder() {
        textView?.becomeFirstResponder()
    }

    /// Requests that the find UI is shown
    public func requestFind() {
        print("TextViewCommand: requestFind")
    }

    /// Requests that the find and replace UI is shown
    public func requestFindAndReplace() {
        print("TextViewCommand: requestFindAndReplace")
    }

    /// Returns the position in a document that is closest to a specified point.
    public func closestPosition (to point: CGPoint) -> UITextPosition? {
        print("TextViewCommand: closestPosition")
        return nil
    }

    /// Returns the range between two text positions.
    public func textRange(from: UITextPosition, to: UITextPosition) -> UITextRange? {
        print("TextViewCommand: textRange")
        return nil
    }

    /// Replaces the text that is in the specified range.
    public func replace(_ range: UITextRange, withText text: String) {
        print("TextViewCommand: replace")
    }

    /// Replaces the `text` in the specified `line` with the provided `withText`, the line is matched based on the .regularExpression/.caseInsensitive bits in NSString.CompareOptions, other options are ignored
    public func replaceTextAt (line: Int, text: String, withText: String, options: NSString.CompareOptions) {
        print("TextViewCommand: replaceAt")
    }

    /// The current selection range of the text view as a UITextRange.
    public var selectedTextRange: UITextRange? {
        get {
            print("TextViewCommand: selectedTextRange.get")
            return nil
        }
        set {
            print("TextViewCommand: selectedTextRange.set")
        }
    }

    public func toggleInlineComment(_ delimiter: String) {
        print("TextViewCommand: toggleInlineComment")
    }

    public func indent() {
        print("TextViewCommand: indent")
    }

    public func unIdent() {
        print("TextViewCommand: unindent")
    }
}

#endif
