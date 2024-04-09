//
//  File.swift
//  
//
//  Created by Miguel de Icaza on 4/5/24.
//

import Foundation
import Runestone
import TreeSitter
import TreeSitterGDScript

/// Represents an edited item in the code editor, it uses a path to reference it, and expect that it
/// can be loaded and saved via the HostServices variable.
@Observable
public class EditedItem: Identifiable, Hashable, Equatable {
    public static func == (lhs: EditedItem, rhs: EditedItem) -> Bool {
        lhs === rhs
        
    }
    
    public func hash(into hasher: inout Hasher) {
        path.hash(into: &hasher)
    }
    
    /// Returns the filename that is suitable to be displayed to the user
    public var filename: String {
        if let s = path.lastIndex(of: "/"){
            return String (path [path.index(after: s)...])
        }
        return path
    }
    public var id: String { path }
    
    /// The path of the file that we are editing
    public var path: String
    
    /// Delegate
    public weak var editedItemDelegate: EditedItemDelegate?
    
    public var content: String = ""
    
    public var language: TreeSitterLanguage? = nil
    
    /// List of detected functions, contains the name of the function and the line location
    public var functions: [(String,Int)] = []
    
    /// Detected errors
    public var errors: [Issue]? = nil
    
    /// Detected warnings
    public var warnings: [Issue]? = nil

    public var gotoLineRequest: Int? = nil
    /// - Parameters:
    ///  - path: the path that will be passed to the HostServices API to load and save the file
    ///  - data: this is data that can be attached to this object and extracted a later point by the user
    public init (path: String, content: String, editedItemDelegate: EditedItemDelegate?) {
        if path.hasSuffix(".gd") {
            language = TreeSitterLanguage.gdscript
        } else {
            language = nil
        }
        self.path = path
        self.content = content
        self.editedItemDelegate = editedItemDelegate
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
}

public protocol EditedItemDelegate: AnyObject {
    func editedTextChanged (_ editedItem: EditedItem, _ textView: TextView)
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
