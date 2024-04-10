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
    var item: EditedItem
    var components: [Substring]
    @State var showContents: IdentifiableInt? = nil
    
    init (item: EditedItem) {
        let path = item.path
        self.item = item
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
                        Button (action: {
                            _ = editorState.openFile(path: "\(basePath)/\(v.name)", delegate: nil)
                        }) {
                            Label(v.name, systemImage: v.isDir ? "folder.fill" : PathBrowser.iconFor(v.name))
                        }
                    }
                }
            }
        }
    }
    
    struct FunctionView: View {
        let functions: [(String,Int)]
        let gotoMethod: (Int) -> ()

        var body: some View {
            Menu ("Jump To") {
                ForEach (functions, id: \.0) { fp in
                    Button (action: {
                        gotoMethod (fp.1)
                    }) {
                        Label (fp.0, systemImage: "function")
                    }
                }
            }
        }
    }
    
    var body: some View {
        ScrollView (.horizontal) {
            HStack (spacing: 2){
                ForEach (Array (components.enumerated()), id: \.offset) { idx, v in
                    if idx == 0 {
                        Text (prefix)
                            .foregroundStyle(.secondary)
                    }
                    DirectoryView (prefix: prefix, basePath: PathBrowser.makePath (prefix: prefix, components, idx), element: String(v))
                    Image (systemName: "chevron.compact.right")
                        .foregroundColor(.secondary)
                }
                if item.functions.count > 0 {
                    FunctionView (functions: item.functions) { line in 
                        item.commands.requestGoto(line: line)
                    }
                } else {
                    Text ("No function")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .font (.subheadline)
        .padding([.vertical], 4)
    }
}

#Preview {
    ZStack {
        PathBrowser(item: EditedItem(path: "res://addons/files/text.gd", content: "demo", editedItemDelegate: nil))
            .environment(HostServices.makeTestHostServices())
            .environment(CodeEditorState())
    }
}
