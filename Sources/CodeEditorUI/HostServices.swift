//
//  File.swift
//  
//
//  Created by Miguel de Icaza on 3/29/24.
//

import Foundation
import SwiftUI

/// List of possible errors raised by the IO operations
public enum HostServiceIOError: Error, CustomStringConvertible {
    case fileNotFound(String)
    
    /// Until swift gets typed errors for IO operations, this contains the localizedDescription error that is raised
    /// by the native operations.
    case generic(String)
    
    public var description: String {
        switch self {
        case .fileNotFound(let f):
            return "File not found \(f)"
        case .generic(let msg):
            return msg
        }
    }
}

///
/// The HostServices is intended to provide an API that the CodeEditor can use to interact with its host environment,
/// in the case of Godot on iPad, the paths that we use are resolved by Godot and can either by physical files, or
/// they can reference assets that are part of a compressed file, hence the need for this.
@Observable
open class HostServices {
    /// Initializes a HostServices class with a function to load, and one function to save.
    /// - Parameters:
    ///  - load: this callback takes a path and returns the contents of the file on success, or an error code
    ///  - save: this callback takes the contents to save, and the destination path, it will return nil on success, or a status code indicating the error on failure.
    public init (load: @escaping (_ path: String)->Result<String,HostServiceIOError>, save: @escaping (_ contents: String, _ path: String) -> HostServiceIOError?) {
        cbLoadFile = load
        cbSaveContents = save
    }
    
    public var cbLoadFile: (String)->Result<String,HostServiceIOError>
    public var cbSaveContents: (String, String) -> HostServiceIOError?
    
    /// Loads a file
    /// - Returns: the string with the contents of the file or the error detailing the problem
    open func loadFile (path: String) -> Result<String,HostServiceIOError> {
        return cbLoadFile (path)
    }
    
    /// Saves the string contained in contents to the specified path
    /// - Returns: nil on success, or an error code otherwise
    open func saveContents (contents: String, path: String) -> HostServiceIOError? {
        return cbSaveContents (contents, path)
    }
}
