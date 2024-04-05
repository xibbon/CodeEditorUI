//
//  File.swift
//  
//
//  Created by Miguel de Icaza on 4/1/24.
//

import Foundation
import Runestone

///
/// Tracks the state for the editor, you can affect the editor by invoking methods in this API
///
/// You can be notified of changes on a file in the editor by setting a callback in the `onHook`
/// method
@Observable
public class CodeEditorState {
    public var hostServices: HostServices
    var openFiles: [EditedItem]
    var currentEditor: Int? = nil
    var completionRequest: CompletionRequest? = nil
    
    /// Configures whether the editors show line numbers
    public var showLines: Bool = true
    
    /// Configures whether the editors show tabs
    public var showTabs: Bool = false
    
    /// Configures whether the editors show various space indicators
    public var showSpaces: Bool = false
    
    /// Initializes the code editor state that you can use to control what is shown
    public init (hostServices: HostServices? = nil, openFiles: [EditedItem] = []) {
        self.hostServices = hostServices ?? HostServices.makeTestHostServices()
        self.openFiles = openFiles
        currentEditor = openFiles.count > 0 ? 0 : nil
    }
    
    public func openFile (path: String, data: AnyObject?) -> HostServiceIOError? {
        switch hostServices.loadFile(path: path) {
        case .success(let content):
            openFiles.append(EditedItem(path: path, content: content, data: data))
            currentEditor = openFiles.count - 1
            return nil
        case .failure(let failure):
            return failure
        }
    }
    
    public func selectFile (path: String) {
        if let idx = openFiles.firstIndex(where: { $0.path == path }) {
            currentEditor = idx
        }
    }
    
    /// This callback receives both an instance to the state so it can direct the process, and a handle to the TextView that triggered the change
    /// and can be used to extract information about the change.
    public var onChange: ((CodeEditorState, EditedItem, TextView)->())? = nil
    
    func change (_ editedItem: EditedItem, _ textView: TextView) {
        guard let onChange else {
            return
        }
        onChange (self, editedItem, textView)
    }
}

/// This packet describes the parameters to trigger the code compeltion window
struct CompletionRequest {
    let at: CGRect
    let on: TextView
    let prefix: String
    let completions: [CompletionEntry]
}
