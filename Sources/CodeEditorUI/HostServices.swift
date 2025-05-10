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

    /// Internal assertion, we should not really hit this
    case assertion(String)

    public var description: String {
        switch self {
        case .fileNotFound(let f):
            return "File not found \(f)"
        case .assertion(let msg):
            return "Internal error, this should not happen: \(msg)"
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
