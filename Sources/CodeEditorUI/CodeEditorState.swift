//
//  File.swift
//  
//
//  Created by Miguel de Icaza on 4/1/24.
//

import Foundation

@Observable
public class CodeEditorState {
    var openFiles: [EditedItem]
    var currentEditor: Int
    
    /// Initializes the code editor state that you can use to control what is shown
    public init (openFiles: [EditedItem] = []) {
        self.openFiles = openFiles
        currentEditor = 0
    }
    
    public func openFile (path: String, data: AnyObject?) {
        openFiles.append(EditedItem(path: path, data: data))
        currentEditor = openFiles.count - 1 
    }
    
    public func selectFile (path: String) {
        if let idx = openFiles.firstIndex(where: { $0.path == path }) {
            currentEditor = idx
        }
    }
}
