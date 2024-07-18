//
//  File.swift
//
//
//  Created by Miguel de Icaza on 4/3/24.
//

import Foundation

public struct CompletionEntry {
    /// Need to find a way of making this more generic, this is what GDScript has, but will need different kinds to support
    /// other languages in the future.
    public enum CompletionKind: Int {
        case `class` = 0
        case function = 1
        case signal = 2
        case variable = 3
        case member = 4
        case `enum` = 5
        case constant = 6
        case nodePath = 7
        case filePath = 8
        case plainText = 9
    }

    /// The kind of completion, used to style it
    public var kind: CompletionKind
    /// The text to display in the completion menu
    public var display: String
    /// The text to insert when the user picks that option
    public var insert: String

    public init (kind: CompletionKind, display: String, insert: String) {
        self.kind = kind
        self.display = display
        self.insert = insert
    }
}
