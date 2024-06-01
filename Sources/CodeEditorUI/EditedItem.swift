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
            if path.hasSuffix(".gd") {
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
    var editedItemDelegate: EditedItemDelegate?
    
    public var language: TreeSitterLanguage? = nil
    
    /// List of detected functions, contains the name of the function and the line location
    public var functions: [(String,Int)] = []
    
    /// Detected errors
    public var errors: [Issue]? = nil
    
    /// Detected warnings
    public var warnings: [Issue]? = nil

    /// Mechanism to trigger actions on the TextViewUI
    public var commands = TextViewCommands()

    public static func == (lhs: EditedItem, rhs: EditedItem) -> Bool {
        lhs === rhs
    }
    
    var completionRequest: CompletionRequest? = nil
    var selected = 0
    
    // This is because we do not have a way of reliably knowing if the user moved away the cursor
    func monitorLocation (on textView: TextView, location: NSRange) {
        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds (300)) {
            if self.completionRequest == nil {
                return
            }
            if textView.selectedRange != location {
                self.cancelCompletion()
            }
            self.monitorLocation(on: textView, location: location)
        }
    }
                             
    public func requestCompletion (at location: CGRect, on textView: TextView, prefix: String, completions: [CompletionEntry]) {
        completionRequest = CompletionRequest(at: location, on: textView, prefix: prefix, completions: completions)
        monitorLocation(on: textView, location: textView.selectedRange)
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
}

@MainActor
public protocol EditedItemDelegate: AnyObject {
    func started (editedItem: EditedItem, textView: TextView)
    func editedTextChanged (_ editedItem: EditedItem, _ textView: TextView)
    func gutterTapped (_ editedItem: EditedItem, _ textView: TextView, _ line: Int)
    func lookup (_ editedItem: EditedItem, on: TextView, at: UITextPosition, word: String)
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
