//
//  File.swift
//
//
//  Created by Miguel de Icaza on 4/5/24.
//

import Foundation
import Runestone
import RunestoneUI
import TreeSitter
import TreeSitterGDScriptRunestone
import TreeSitterJSONRunestone
import TreeSitterMarkdownRunestone
import SwiftUI
/// Represents an edited item in the code editor, it uses a path to reference it, and expect that it
/// can be loaded and saved via the HostServices variable.
@Observable
public class EditedItem: HostedItem {
    public enum FileHint {
        case detect
        case gdscript
        case json
        case markdown
    }
    /// Lines where breakpoint indicators are shown
    public var breakpoints: Set<Int>

    /// If set, a line to highlight, it means "This is current the debugger is stopped"
    public var currentLine: Int?

    /// Controls whether this language supports looking symbosl up
    public var supportsLookup: Bool

    /// - Parameters:
    ///  - path: the path that will be passed to the HostServices API to load and save the file
    ///  - data: this is data that can be attached to this object and extracted a later point by the user
    public init (path: String, content: String, editedItemDelegate: EditedItemDelegate?, fileHint: FileHint = .detect, breakpoints: Set<Int> = Set<Int>(), currentLine: Int? = nil) {
        switch fileHint {
        case .detect:
            if path.hasSuffix(".gd") || path.contains ("::"){
                language = TreeSitterLanguage.gdscript
                supportsLookup = true
            } else if path.hasSuffix (".md") {
                language = TreeSitterLanguage.markdown
                supportsLookup = false
            } else {
                language = nil
                supportsLookup = false
            }
        case .gdscript:
            language = TreeSitterLanguage.gdscript
            supportsLookup = true
        case .json:
            language = TreeSitterLanguage.json
            supportsLookup = false
        case .markdown:
            language = TreeSitterLanguage.markdown
            supportsLookup = false
        }
        self.editedItemDelegate = editedItemDelegate
        self.breakpoints = breakpoints
        self.currentLine = currentLine
        super.init (path: path, content: content)
    }

    /// Returns the filename that is suitable to be displayed to the user
    public var filename: String {
        if let s = path.lastIndex(of: "/"){
            return String (path [path.index(after: s)...])
        }
        return path
    }

    /// Returns a title suitable to be shown on the titlebar
    public override var title: String {
        filename
    }

    /// Delegate
    public var editedItemDelegate: EditedItemDelegate?

    public var language: TreeSitterLanguage? = nil

    /// List of detected functions, contains the name of the function and the line location
    public var functions: [(String,Int)] = []

    /// Detected errors
    public var errors: [Issue]? = nil

    /// Detected warnings
    public var warnings: [Issue]? = nil

    /// Whether the buffer has local changes
    public var dirty: Bool = false

    /// Mechanism to trigger actions on the TextViewUI
    public var commands = TextViewCommands()

    public static func == (lhs: EditedItem, rhs: EditedItem) -> Bool {
        lhs === rhs
    }

    var completionRequest: CompletionRequest? = nil
    var selected = 0

    public func requestCompletion (at location: CGRect, on textView: TextView, prefix: String, completions: [CompletionEntry]) {
        completionRequest = CompletionRequest(at: location, on: textView, prefix: prefix, completions: completions, textViewCursor: textView.selectedRange.location)
        selected = 0
    }

    public func cancelCompletion () {
        completionRequest = nil
    }

    /// This is used to set the validation result
    public func validationResult (functions: [(String,Int)], errors: [Issue]?, warnings: [Issue]?) {
        self.functions = functions
        self.errors = errors
        self.warnings = warnings
    }

    public override func requestFindAndReplace() {
        commands.requestFindAndReplace()
    }

    public override func requestFind () {
        commands.requestFind()
    }

    @MainActor
    public func editedTextChanged (on textView: TextView) {
        dirty = true
        editedItemDelegate?.editedTextChanged(self, textView)
    }

    @MainActor
    public func started (on textView: TextView) {
        editedItemDelegate?.editedTextChanged(self, textView)
    }

    @MainActor
    public func gutterTapped (on textView: TextView, line: Int) {
        editedItemDelegate?.gutterTapped (self, textView, line)
    }

    public var textLocation = TextLocation(lineNumber: 0, column: 0)

    @MainActor
    public func editedTextSelectionChanged (on textView: TextView) {
        if let newPos = textView.textLocation(at: textView.selectedRange.location) {
            textLocation = newPos
        }
        guard let completionRequest else { return }
        if textView.selectedRange.location != completionRequest.textViewCursor {
            self.cancelCompletion()
        }
    }
}

/// Protocol describing the callbacks for the EditedItem
@MainActor
public protocol EditedItemDelegate: AnyObject {
    /// Editing has started for the given item, this is raised when the TextView has loaded
    func started (editedItem: EditedItem, textView: TextView)
    /// Invoked when the text in the textView has changed, a chance to extract the data
    func editedTextChanged (_ editedItem: EditedItem, _ textView: TextView)
    /// Invoked when the gutter is tapped, and it contains the line number that was tapped
    func gutterTapped (_ editedItem: EditedItem, _ textView: TextView, _ line: Int)
    /// Invoked when the user has requested the "Lookup Definition" from the context menu in the editor, it contains the position where this took place and the word that should be looked up
    func lookup (_ editedItem: EditedItem, on: TextView, at: UITextPosition, word: String)
    /// Invoked when a closing is imminent on the UI
    func closing (_ editedItem: EditedItem)
    /// Requests that the given item be saved, returns nil on success or details on error, if newPath is not-nil, save to a new filename
    func save(editedItem: EditedItem, contents: String, newPath: String?) -> HostServiceIOError?
}

public struct Issue {
    public enum Kind {
        case warning
        case error
    }
    var kind: Kind
    var col, line: Int
    var message: String

    public init (kind: Kind, col: Int, line: Int, message: String) {
        self.kind = kind
        self.col = col
        self.line = line
        self.message = message
    }
}
