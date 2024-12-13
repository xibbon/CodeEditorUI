//
//  File.swift
//
//
//  Created by Miguel de Icaza on 4/1/24.
//

import Foundation
import Runestone
import RunestoneUI
import SwiftUI

///
/// Tracks the state for the editor, you can affect the editor by invoking methods in this API
///
/// You can load files using the `openFile` method, or render local HTML content using the `openHtml` method.
///
@Observable
public class CodeEditorState {
    public var hostServices: HostServices
    var openFiles: [HostedItem]
    public var currentEditor: Int? = nil
    var completionRequest: CompletionRequest? = nil
    var saveError: Bool = false
    var saveErrorMessage = ""
    var saveIdx = 0
    public var lineHeightMultiplier: CGFloat = 1.2

    /// Configures whether the editors show line numbers
    public var showLines: Bool = true

    /// Configures whether the editors show tabs
    public var showTabs: Bool = false

    /// Configures whether the editors show various space indicators
    public var showSpaces: Bool = false

    /// Configures whether we auto-delete empty pairs (like quotes, parenthesis)
    public var autoDeleteEmptyPairs: Bool = true

    /// Controls word wrapping in the text editor
    public var lineWrapping: Bool = true

    /// Initializes the code editor state that you can use to control what is shown
    public init (hostServices: HostServices? = nil, openFiles: [EditedItem] = []) {
        self.hostServices = hostServices ?? HostServices.makeTestHostServices()
        self.openFiles = openFiles
        currentEditor = openFiles.count > 0 ? 0 : nil
    }

    /// If the path is currently being edited, it returns the EditedItem for it,
    /// otherwise it returns nil
    public func getEditedFile(path: String) -> EditedItem? {
        if let existingIdx = openFiles.firstIndex(where: {
            $0 is EditedItem && $0.path == path
        }) {
            if let result = openFiles [existingIdx] as? EditedItem {
                return result
            }
        }
        return nil
    }

    /// Requests that a file with the given path be opened by the code editor
    /// - Parameters:
    ///  - path: The filename to load, this is loaded via the `hostServices` API
    ///  - delegate: the delegate to fulfill services for this edited item
    ///  - fileHint: hint, if available about the kind of file we are editing
    ///  - breakpoints: List of breakpoints to show at startup as shown.
    /// - Returns: an EditedItem if it was alread opened, or if it was freshly opened on success, or an error indicating the problem otherwise
    public func openFile (path: String, delegate: EditedItemDelegate?, fileHint: EditedItem.FileHint, breakpoints: Set<Int> = Set<Int>()) -> Result<EditedItem,HostServiceIOError> {
        if let existingIdx = openFiles.firstIndex(where: { $0 is EditedItem && $0.path == path }) {
            if let result = openFiles [existingIdx] as? EditedItem {
                currentEditor = existingIdx
                return .success(result)
            }
        }
        switch hostServices.loadFile(path: path) {
        case .success(let content):
            let item = EditedItem(path: path, content: content, editedItemDelegate: delegate, fileHint: .detect, breakpoints: breakpoints)
            openFiles.append(item)
            currentEditor = openFiles.count - 1
            return .success(item)
        case .failure(let code):
            return .failure(code)
        }
    }

    /// Requests that a file with the given path be opened by the code editor
    /// - Parameters:
    ///  - path: The filename to load, this is loaded via the `hostServices` API
    ///  - delegate: the delegate to fulfill services for this edited item
    ///  - fileHint: hint, if available about the kind of file we are editing
    ///  - breakpoints: List of breakpoints to show at startup as shown.
    /// - Returns: an EditedItem if it was alread opened, or if it was freshly opened on success, or an error indicating the problem otherwise
    public func editFile (path: String, contents: String, delegate: EditedItemDelegate?, fileHint: EditedItem.FileHint, breakpoints: Set<Int> = Set<Int>()) -> EditedItem {
        if let existingIdx = openFiles.firstIndex(where: { $0 is EditedItem && $0.path == path }) {
            if let result = openFiles [existingIdx] as? EditedItem {
                currentEditor = existingIdx
                return result
            }
        }
        let item = EditedItem(path: path, content: contents, editedItemDelegate: delegate, fileHint: .detect, breakpoints: breakpoints)
        openFiles.append(item)
        currentEditor = openFiles.count - 1
        return item
    }

    /// Opens an HTML tab with the specified HTML content
    /// - Parameters:
    ///  - title: Title to display on the tab bar
    ///  - path: used for matching open tabs, it should represent the content that rendered this
    ///  - content: the HTML content to display.
    /// - Returns: the HtmlItem for this path.
    public func openHtml (title: String, path: String, content: String, anchor: String? = nil) -> HtmlItem {
        if let existingIdx = openFiles.firstIndex(where: { $0 is HtmlItem && $0.path == path }) {
            if let result = openFiles [existingIdx] as? HtmlItem {
                currentEditor = existingIdx
                if result.anchor != anchor {
                    result.anchor = anchor
                }
                return result
            }
        }
        let html = HtmlItem(title: title, path: path, content: content, anchor: anchor)
        openFiles.append (html)
        currentEditor = openFiles.count - 1
        return html
    }

    /// If the given path is already open, it returns it, and switches to it
    public func findExistingHtmlItem (path: String) -> HtmlItem? {
        if let existingIdx = openFiles.firstIndex(where: { $0 is HtmlItem && $0.path == path }) {
            if let result = openFiles [existingIdx] as? HtmlItem {
                currentEditor = existingIdx
                return result
            }
        }
        return nil
    }

    @MainActor
    public func attemptSave (_ idx: Int) -> Bool {
        guard let edited = openFiles[idx] as? EditedItem, edited.dirty else {
            return true
        }
        saveIdx = idx
        if let error = edited.editedItemDelegate?.save(editedItem: edited, contents: edited.content, newPath: nil) {
            saveErrorMessage = error.localizedDescription
            saveError = true
            return false
        }
        edited.dirty = false
        return true
    }

    @MainActor
    func attemptClose (_ idx: Int) {
        guard idx < openFiles.count else { return }
        if let edited = openFiles[idx] as? EditedItem, edited.dirty {
            if attemptSave (idx) {
                closeFile (idx)
            }
        } else {
            closeFile (idx)
        }
    }

    @MainActor
    func closeFile (_ idx: Int) {
        guard idx < openFiles.count else { return }
        if let edited = openFiles[idx] as? EditedItem {
            edited.editedItemDelegate?.closing(edited)
        }
        openFiles.remove(at: idx)
        if idx == currentEditor {
            if openFiles.count == 0 {
                currentEditor = nil
            } else {
                if let ce = currentEditor {
                    currentEditor = ce-1
                }
            }
        }
    }

    /// Saves the current file if it is dirty
    @MainActor
    public func saveCurrentFile(newPath: String? = nil) {
        guard let idx = currentEditor else { return }
        guard let edited = openFiles[idx] as? EditedItem, edited.dirty else { return }
        if let error = edited.editedItemDelegate?.save(editedItem: edited, contents: edited.content, newPath: newPath) {
            saveErrorMessage = error.localizedDescription
            saveError = true
        }
        edited.dirty = false
    }

    //
    // Triggers the workflow to save the current file with a new path
    @MainActor
    public func saveFileAs() {
        guard let currentEditor else { return }
        guard let edited = openFiles[currentEditor] as? EditedItem, edited.dirty else { return }
        let path = edited.path

        hostServices.requestFileSaveAs(title: "Save Script As", path: path) { ret in
            guard let newPath = ret.first else { return }
            edited.path = newPath
            if let error = edited.editedItemDelegate?.save(editedItem: edited, contents: edited.content, newPath: newPath) {
                self.saveErrorMessage = error.localizedDescription
                self.saveError = true
            }
            edited.dirty = false
        }
    }

    @MainActor
    public func saveAllFiles() {
        for idx in 0..<openFiles.count {
            saveIdx = idx
            guard let editedItem = openFiles[idx] as? EditedItem, editedItem.dirty else {
                continue
            }
            if let error = editedItem.editedItemDelegate?.save(editedItem: editedItem, contents: editedItem.content, newPath: editedItem.path) {
                saveErrorMessage = error.localizedDescription
                saveError = true
            } else {
                editedItem.dirty = false
            }
        }
    }

    public func getHostedItems() -> [HostedItem] {
        return openFiles
    }

    public func selectFile(path: String) {
        if let idx = openFiles.firstIndex(where: { $0.path == path }) {
            currentEditor = idx
        }
    }

    public func search (showReplace: Bool) {
        guard let currentEditor else { return }
        let item = openFiles[currentEditor]
        if showReplace {
            item.requestFindAndReplace()
        } else {
            item.requestFind()
        }
        //item.findRequest = showReplace ? .findAndReplace : .find
    }

    public func goTo (line: Int) {
        guard let currentEditor else { return }
        if let item = openFiles[currentEditor] as? EditedItem {
            item.commands.requestGoto(line: line)
        }
    }

    public func nextTab () {
        guard let currentEditor else {
            if openFiles.count > 0 {
                self.currentEditor = 0
            }
            return
        }
        if currentEditor+1 < openFiles.count {
            self.currentEditor = currentEditor + 1
        } else {
            self.currentEditor = 0
        }
    }

    public func previousTab () {
        guard let currentEditor else {
            if openFiles.count > 0 {
                self.currentEditor = openFiles.count - 1
            }

            return
        }
        if currentEditor > 0 {
            self.currentEditor = currentEditor - 1
        } else {
            self.currentEditor = openFiles.count - 1
        }
    }

    /// Indicates whether we have an empty set of tabs or not
    public var haveScriptOpen: Bool {
        var haveEditor = false
        for x in openFiles {
            if x is EditedItem {
                return true
            }
        }
        return false
    }

    /// This callback receives both an instance to the state so it can direct the process, and a handle to the TextView that triggered the change
    /// and can be used to extract information about the change.
//    public var onChange: ((CodeEditorState, EditedItem, TextView)->())? = nil
//
//    func change (_ editedItem: EditedItem, _ textView: TextView) {
//        guard let onChange else {
//            return
//        }
//        onChange (self, editedItem, textView)
//    }
}

/// This packet describes the parameters to trigger the code compeltion window
struct CompletionRequest {
    let at: CGRect
    let on: TextView
    let prefix: String
    let completions: [CompletionEntry]
    let textViewCursor: Int
}
