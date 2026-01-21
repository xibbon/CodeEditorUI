//
//  File.swift
//
//
//  Created by Miguel de Icaza on 5/11/24.
//

import Foundation

@MainActor
open class HostedItem: Identifiable, Hashable, Equatable {
    /// - Parameters:
    ///  - path: the path that will be passed to the HostServices API to load and save the file
    ///  - data: this is data that can be attached to this object and extracted a later point by the user
    public init (path: String, content: String) {
        self.path = path
        self.content = content
    }

    public var id: String { path }

    /// The path of the file that we are editing
    public var path: String

    /// The content that is initially displayed
    public var content: String

    public static func == (lhs: HostedItem, rhs: HostedItem) -> Bool {
        lhs === rhs
    }

    public func hash(into hasher: inout Hasher) {
        path.hash(into: &hasher)
    }

    @MainActor
    public func requestFindAndReplace() {}
    @MainActor
    public func requestFind () {}

    /// Returns a title suitable to be shown on the titlebar
    open var title: String {
        fatalError()
    }
}
