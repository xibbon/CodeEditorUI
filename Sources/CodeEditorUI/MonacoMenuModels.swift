import CoreGraphics
import Foundation

public struct MonacoActionItem {
    public let id: String
    public let label: String
    public let enabled: Bool

    public init(id: String, label: String, enabled: Bool) {
        self.id = id
        self.label = label
        self.enabled = enabled
    }
}

public struct MonacoMenuItem {
    public enum Kind: String {
        case action
        case separator
        case submenu
    }

    public let kind: Kind
    public let id: String?
    public let label: String?
    public let enabled: Bool
    public let keybinding: String?
    public let children: [MonacoMenuItem]

    public init(kind: Kind, id: String?, label: String?, enabled: Bool, keybinding: String?, children: [MonacoMenuItem]) {
        self.kind = kind
        self.id = id
        self.label = label
        self.enabled = enabled
        self.keybinding = keybinding
        self.children = children
    }
}

public struct MonacoSelectionRange {
    public let startLine: Int
    public let startColumn: Int
    public let endLine: Int
    public let endColumn: Int

    public init(startLine: Int, startColumn: Int, endLine: Int, endColumn: Int) {
        self.startLine = startLine
        self.startColumn = startColumn
        self.endLine = endLine
        self.endColumn = endColumn
    }
}

public struct MonacoContextMenuRequest {
    public let location: TextLocation?
    public let selection: MonacoSelectionRange?
    public let selectedText: String
    public let word: String?
    public let actions: [MonacoMenuItem]
    public let viewPoint: CGPoint?

    public init(
        location: TextLocation?,
        selection: MonacoSelectionRange?,
        selectedText: String,
        word: String?,
        actions: [MonacoMenuItem],
        viewPoint: CGPoint?
    ) {
        self.location = location
        self.selection = selection
        self.selectedText = selectedText
        self.word = word
        self.actions = actions
        self.viewPoint = viewPoint
    }
}

public struct MonacoCommandPaletteRequest {
    public let actions: [MonacoActionItem]

    public init(actions: [MonacoActionItem]) {
        self.actions = actions
    }
}
