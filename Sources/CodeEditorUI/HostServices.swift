//
//  File.swift
//  
//
//  Created by Miguel de Icaza on 3/29/24.
//

import Foundation
import SwiftUI

public enum HostServiceIOError: Error, CustomStringConvertible {
    case fileNotFound(String)
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

@Observable
open class HostServices {
    public init (load: @escaping (String)->Result<String,HostServiceIOError>, save: @escaping (String, String) -> HostServiceIOError?) {
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
