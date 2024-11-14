//
//  File.swift
//
//
//  Created by Miguel de Icaza on 3/29/24.
//

import Foundation
import SwiftUI

/// List of possible errors raised by the IO operations
public enum HostServiceIOError: Error, CustomStringConvertible, LocalizedError {
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

    public var failureReason: String? {
        return description
    }
    public var errorDescription: String? {
        return description
    }

}

public struct DirectoryElement {
    public init(name: String, isDir: Bool) {
        self.name = name
        self.isDir = isDir
    }

    public var name: String
    public var isDir: Bool
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
    ///  - fileList: provides a direcotry listing of files at the specified path
    ///  - requestFileSave: requests that the file be saved, the parameters are the title for the dialog, the path to save it to, and a callback to invoke with the resulting filename to save to.
    ///  - requestOpen: invokes the system "open" functionality on the specified path, which will determine how to best open a specific file.
    public init (
        load: @escaping (_ path: String)->Result<String,HostServiceIOError>,
        save: @escaping (_ contents: String, _ path: String) -> HostServiceIOError?,
        fileList: @escaping (_ path: String) -> [DirectoryElement],
        requestFileSaveAs: @escaping (_ title: String, _ path: String, _ complete: @escaping ([String])->()) -> (),
        requestOpen: @escaping (_ path: String) -> ()
    ) {
        cbLoadFile = load
        cbSaveContents = save
        cbFileList = fileList
        cbRequestFileSaveAs = requestFileSaveAs
        cbRequestOpen = requestOpen
    }

    var cbLoadFile: (String)->Result<String,HostServiceIOError>
    var cbSaveContents: (String, String) -> HostServiceIOError?
    var cbRequestOpen: (String) -> ()
    public var cbFileList: (String) -> [DirectoryElement]
    public var cbRequestFileSaveAs: (_ title: String, _ path: String, _ complete: @escaping ([String])->()) -> ()

    /// Requests that the host process opens the specified path in an appropriate way
    ///
    /// When hosted in Godot, this calls the Godot code that determines if this is a scene, a resource, a text file or script that needs to be opened
    open func requestOpen (path: String) {
        cbRequestOpen(path)
    }

    /// Loads a file
    /// - Returns: the string with the contents of the file or the error detailing the problem
    open func loadFile (path: String) -> Result<String,HostServiceIOError> {
        return cbLoadFile (path)
    }

    /// Triggers a request in the UI for picking a file to be saved as, currently this
    /// will default to filters for all files and "gd" extension
    ///
    /// - Parameters:
    ///  - title: The title for the dialog box
    ///  - path: the current path for the file
    ///  - complete: callback to invoke when the operation is completed with the list of arguments
    ///  selected (for now, just one value)
    open func requestFileSaveAs (title: String, path: String, complete: @escaping ([String]) -> ()) {
        cbRequestFileSaveAs(title, path, complete)
    }

    /// Saves the string contained in contents to the specified path
    /// - Returns: nil on success, or an error code otherwise
    open func saveContents (contents: String, path: String) -> HostServiceIOError? {
        return cbSaveContents (contents, path)
    }

    open func fileListing (at: String) -> [DirectoryElement] {
        return cbFileList (at)
    }

    public static func makeTestHostServices () -> HostServices {
        HostServices { path in

            do {
                return .success (try String(contentsOf: URL (filePath: path)))
            } catch (let err) {
                if !FileManager.default.fileExists(atPath: path) {
                    return .failure(.fileNotFound(path))
                }
                return .failure(.generic(err.localizedDescription))
            }
        } save: { contents, path in
            do {
                try contents.write(toFile: "/too", atomically: false, encoding: .utf8)
            } catch (let err) {
                return .generic(err.localizedDescription)
            }
            return nil
        } fileList: { at in
            var result: [DirectoryElement] = []
            do {
                for element in try FileManager.default.contentsOfDirectory(atPath: at) {
                    var isDir: ObjCBool = false
                    if FileManager.default.fileExists(atPath: "\(at)/\(element)", isDirectory: &isDir) {
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
        } requestFileSaveAs: { title, path, complete in
            complete (["picked.gd"])
        } requestOpen: { file in
            print ("File \(file) shoudl be opened")
        }
    }

}

