//
//  PathBrowser.swift
//
// TODO: The last item in the path should also list the peer files
// TODO: should add a hook for the scanned methods from GDScritp
// TODO: the nested directories are not showing up, not sure why, but if I add a menu at the bottom, they all show up.
//
//  Created by Miguel de Icaza on 4/2/24.
//

import SwiftUI
import Foundation

struct PathBrowser: View {
    @Environment (HostServices.self) var hostServices
    @Environment (CodeEditorState.self) var editorState
    
    struct IdentifiableInt: Identifiable {
        var id: Int
    }
    let prefix: String
    var components: [Substring]
    @State var showContents: IdentifiableInt? = nil
    
    init (path: String) {
        self.prefix = path.hasPrefix("res://") ? "res://" : "/"
        
        components = path.dropFirst (path.hasPrefix ("res://") ? 6 : 0).split (separator: "/")
    }
    
    static func makePath (prefix: String, _ components: [Substring], _ idx: Int) -> String {
        let r = components [0..<idx+1].joined(separator: "/")
        return "\(prefix)/\(r)"
    }
    
    static func iconFor (_ txt: String) -> String {
        if txt.hasSuffix(".gd") {
            return "scroll"
        }
        if txt.hasSuffix(".md") {
            return "text.justify.left"
        }
        if txt == "README" {
            return "book"
        }
        return "doc"
    }
    
    struct DirectoryView: View {
        @Environment (HostServices.self) var hostServices
        @Environment (CodeEditorState.self) var editorState
        let prefix: String
        let basePath: String
        let element: String
        
        var body: some View {
            Menu (element) {
                ForEach (Array (hostServices.fileListing(at: basePath).enumerated()), id: \.offset) { _, v in
                    if v.isDir {
                        DirectoryView (prefix: prefix, basePath: "\(basePath)/\(v)", element: v.name)
                    } else {
                        Button (action: { editorState.openFile(path: "\(basePath)/\(v.name)", data: nil) }) {
                            Label(v.name, systemImage: v.isDir ? "folder.fill" : PathBrowser.iconFor(v.name))
                        }
                    }
                }
                Menu ("This triggers the submenus to show up") {
                    Text ("no idea why")
                }
            }
        }
    }
    var body: some View {
        ScrollView (.horizontal) {
            HStack {
                ForEach (Array (components.enumerated()), id: \.offset) { idx, v in
                    DirectoryView (prefix: prefix, basePath: PathBrowser.makePath (prefix: prefix, components, idx), element: String(v))
                    Image (systemName: "chevron.compact.right")
                        .foregroundColor(.secondary)
                }
            }
        }
        .font (.subheadline)
        .padding([.vertical], 4)
    }
}

#Preview {
    PathBrowser(path: "res://addons/files/text.gd")
}
