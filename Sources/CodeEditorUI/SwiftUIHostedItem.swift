//
//  SwiftUIHostedItem.swift
//  CodeEditorUI
//
//  Created by Miguel de Icaza on 12/18/24.
//
import SwiftUI

/// An item that hosts a SwiftUI View
open class SwiftUIHostedItem: HostedItem {
    /// The view to display, it can be changed
    public var view: () -> AnyView

    open override var title: String { "None Set" }

    /// Creates an HTML Item that can be shown in the CodeEditorUI
    /// - Parameters:
    ///   - path: Path of the item to browse, not visible, used to check if the document is opened
    ///   - content: Data that might be useful to you
    ///   - view: the SwiftUI View that you want to render, you can change it later
    public init (path: String, content: String, view: @escaping () -> AnyView) {
        self.view = view
        super.init (path: path, content: content)
    }
}
