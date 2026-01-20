//
//  File.swift
//
//
//  Created by Miguel de Icaza on 4/1/24.
//

import Foundation
import SwiftUI

#if canImport(UIKit)
import Runestone
import RunestoneUI
#endif

///
/// Tracks the state for the editor, you can affect the editor by invoking methods in this API
///
/// You can load files using the `openFile` method, or render local HTML content using the `openHtml` method.
///
/// You must subclass this and implement the following methods:
/// - `readFileContents`
/// - `requestFileSaveAs`
/// - `requestOpen`
/// - `requestFile Open`
/// - `fileList`
@Observable
@MainActor
open class CodeEditorState {
    public var openFiles: [HostedItem] = []
    
    /// If this is set to true, then we will place various items assuming we are hosted in a NavigationStack
    /// used for iPhone form factors
    public var useNavigation: Bool = false
    
    /// Index of the currentEditor
    public var currentEditor: Int? = nil {
        didSet {
            updateCurrentTextEditor()
        }
    }
    
    /// If true, it means that the currently selected editor in `currentEditor` is a text editor
    public var currentTabIsTextEditor: Bool = false
    
    var completionRequest: CompletionRequest? = nil
    var saveError: Bool = false
    var saveErrorMessage = ""
    var saveIdx = 0
#if !os(macOS)
    var codeEditorDefaultTheme: CodeEditorTheme
#endif

    /// Whether to show the path browser
    public var showPathBrowser: Bool = true

    /// Uses the Monaco editor (WebView) instead of the native editor.
    public var useMonacoEditor: Bool = false

    public var lineHeightMultiplier: CGFloat = 1.6

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
    
    /// Controls displaying the "Go To Line" dialog
    public var showGotoLine: Bool = false
    
    /// The font family to use, the empty string or "System font" become the system font
    public var fontFamily: String = "" {
        didSet {
#if !os(macOS)
            self.codeEditorDefaultTheme = CodeEditorTheme(fontFamily: fontFamily, fontSize: fontSize)
#endif
        }
    }
    
    /// Controls font size
    public var fontSize: CGFloat = 16 {
        didSet {
#if !os(macOS)
            self.codeEditorDefaultTheme = CodeEditorTheme(fontFamily: fontFamily, fontSize: fontSize)
#endif
            UserDefaults.standard.set(fontSize, forKey: "xogot/appearance/font_size")
        }
    }

    public func setFont(family: String, size: CGFloat) {
        self.fontFamily = family
        self.fontSize = size
    }

    /// Controls indentation strategy
    public var indentStrategy: IndentStrategy = .tab(length: 4)

    /// Initializes the code editor state that you can use to control what is shown
    public init() {
        currentEditor = nil
#if !os(macOS)
        self.codeEditorDefaultTheme = CodeEditorTheme()
#endif
        updateCurrentTextEditor()
    }

    func updateCurrentTextEditor() {
        if let currentEditor, currentEditor < openFiles.count, openFiles[currentEditor] is EditedItem {
            currentTabIsTextEditor = true
        } else {            currentTabIsTextEditor = false
        }
    }
    
    public func getCurrentEditedItem() -> EditedItem? {
        guard let currentEditor, currentEditor < openFiles.count else { return nil }

        guard let edited = openFiles[currentEditor] as? EditedItem else {
            return nil
        }
        return edited
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

    public func getEditedItem(path: String) -> HostedItem? {
        if let existingIdx = openFiles.firstIndex(where: {
            $0.path == path
        }) {
            return openFiles[existingIdx]
        }
        return nil

    }

    /// Must be implemented in subclasses, the default implementation uses the host API
    open func readFileContents(path: String) -> Result<String, HostServiceIOError> {
        do {
            return .success (try String(contentsOf: URL (filePath: path)))
        } catch (let err) {
            if !FileManager.default.fileExists(atPath: path) {
                return .failure(.fileNotFound(path))
            }
            return .failure(.generic(err.localizedDescription))
        }
    }
    
    /// Requests that a file with the given path be opened by the code editor
    /// - Parameters:
    ///  - path: The filename to load, this is loaded via the  `readFileContents` API
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
        switch readFileContents(path: path) {
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
    ///  - path: The filename to load, this is loaded via the `attemptOpenFile` method
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
        let item = EditedItem(path: path, content: contents, editedItemDelegate: delegate, fileHint: fileHint, breakpoints: breakpoints)
        openFiles.append(item)
        currentEditor = openFiles.count - 1
        return item
    }

    public func addSwiftUIItem(item: SwiftUIHostedItem) {
        openFiles.append(item)
        currentEditor = openFiles.count - 1
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
    public func save(editedItem: EditedItem) -> HostServiceIOError? {
        guard editedItem.dirty else {
            return nil
        }
        if let error = editedItem.editedItemDelegate?.save(editedItem: editedItem, contents: editedItem.content, newPath: nil) {
            return error
        }
        editedItem.dirty = false
        return nil
    }
    @MainActor
    public func attemptClose (_ idx: Int) {
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
                    if ce == 0 {
                        if openFiles.count > 0 {
                            currentEditor = 0
                        } else {
                            currentEditor = nil
                        }
                    } else {
                        currentEditor = ce - 1
                    }
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

    /// Invokes to save a file, it gets a title, and an initial path to display, this should display
    /// the UI to request a file to be opened, and when the user picks the target, the complete
    /// callback should be invoked with an array that contains a single string with the destination path where
    /// the file will be saved.
    ///
    /// - Parameters:
    ///  - title: Desired title to show in the UI for the dialog to save
    ///  - path: the initial path to display in the dialog
    ///  - complete: the method to invoke on the user picking the file, it should contains a string with the destination path, only the first
    ///  element is used is currently used.
    open func requestFileSaveAs(title: String, path: String, complete: @escaping ([String]) -> ()) {
        complete([])
    }
    
    /// Invoked to request that the file open dialog is displayed
    /// 
    open func requestFileOpen(title: String, path: String, complete: @escaping ([String]) -> ()) {
        print("Request file open for \(title) at \(path)")
    }
    
    /// Used to request that the shell environment opens the specified path.
    open func requestOpen(path: String) {
    }

    /// Encodes a path that was part of a FileNode drag operation, which in Xogot we know is going to be a URL in our project.
    open func encodeDroppedFile(path: String, isTargetEmptyLine: Bool) -> String {
        "\"\(path)\""
    }

    /// Encodes a scene path, which in Xogot is coming from the ScenePad
    open func encodeScenePath(path _path: String) -> String {
        var path = _path
        if path.contains(".") {
            let prefix = String(path.removeFirst())
            path = "\"" + path + "\""
            return prefix + path
        } else {
            return path
        }
    }

    /// Used to return the file contents at path, you can override this
    open func fileList(at path: String) -> [DirectoryElement] {
        var result: [DirectoryElement] = []
        do {
            for element in try FileManager.default.contentsOfDirectory(atPath: path) {
                var isDir: ObjCBool = false
                if FileManager.default.fileExists(atPath: "\(path)/\(element)", isDirectory: &isDir) {
                    result.append (DirectoryElement(name: element, isDir: isDir.boolValue))
                }
            }
        } catch {
            return result
        }
        result.sort(by: {
            if $0.isDir {
                if $1.isDir {
                    return $0.name < $1.name
                } else {
                    return false
                }
            } else {
                if $1.isDir {
                    return true
                } else {
                    return $0.name < $1.name
                }
            }
        })
        return result
    }
    
    //
    // Triggers the workflow to save the current file with a new path
    @MainActor
    public func saveFileAs() {
        guard let currentEditor else { return }
        guard let edited = openFiles[currentEditor] as? EditedItem else { return }
        let path = edited.path

        requestFileSaveAs(title: "Save Script As", path: path) { ret in
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
        for x in openFiles {
            if x is EditedItem {
                return true
            }
        }
        return false
    }

    public func hasFirstResponder() -> Bool {
        guard let currentEditor else { return false }
        if let edited = openFiles[currentEditor] as? EditedItem {
#if !os(macOS)
            if edited.commands.textView?.isFirstResponder ?? false {
                return true
            }
#endif
        }
        return false
    }
    
    @MainActor
    public func toggleInlineComment() {
        guard let currentEditor else { return }
        guard let edited = openFiles[currentEditor] as? EditedItem else {
            return
        }
        edited.toggleInlineComment()
    }

    @MainActor
    public func indent() {
        guard let currentEditor else { return }
        guard let edited = openFiles[currentEditor] as? EditedItem else {
            return
        }
        edited.indent()
    }

    @MainActor
    public func unIndent() {
        guard let currentEditor else { return }
        guard let edited = openFiles[currentEditor] as? EditedItem else {
            return
        }
        edited.unIndent()
    }

    @MainActor
    public func increaseFontSize() {
        var newFontSize = self.fontSize + 2
        self.fontSize = min(newFontSize, 18)
    }

    @MainActor
    public func decreaseFontSize() {
        var newFontSize = self.fontSize - 2
        self.fontSize = max(newFontSize, 12)
    }

    public func clearHighlight() {
        guard let currentEditor else { return }
        if let item = openFiles[currentEditor] as? EditedItem {
            item.currentLine = nil
        }
    }

    public func undo() {
        guard let currentEditor else { return }
        if let item = openFiles[currentEditor] as? EditedItem {
            item.commands.textView?.undoManager?.undo()
        }
    }

    public func redo() {
        guard let currentEditor else { return }
        if let item = openFiles[currentEditor] as? EditedItem {
            item.commands.textView?.undoManager?.redo()
        }
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

#if os(macOS)
/// Strategy to use when indenting text.
public enum IndentStrategy: Equatable {
    /// Indent using tabs. The specified length is used to determine the width of the tab measured in space characers.
    case tab(length: Int)
    /// Indent using a number of spaces.
    case space(length: Int)
}
#endif
