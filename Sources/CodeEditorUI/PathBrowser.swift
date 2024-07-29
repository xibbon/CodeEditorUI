//
//  PathBrowser.swift
//
//  Created by Miguel de Icaza on 4/2/24.
//

import SwiftUI
import Foundation

struct PathBrowser: View {
    @Environment(HostServices.self) var hostServices
    @Environment(CodeEditorState.self) var editorState

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
        if r == "" {
            return prefix
        }
        return "\(prefix)/\(r)"
    }

    static func iconFor(_ txt: String) -> String {
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
        @Environment(HostServices.self) var hostServices
        @Environment(CodeEditorState.self) var editorState
        let prefix: String
        let basePath: String
        let element: String

        var body: some View {
            Menu (element) {
                ForEach (Array (hostServices.fileListing(at: basePath).enumerated()), id: \.offset) { _, v in
                    if v.isDir {
                        DirectoryView (prefix: prefix, basePath: "\(basePath)/\(v.name)", element: v.name)
                    } else {
                        Button (action: {
                            _ = hostServices.requestOpen(path: "\(basePath)/\(v.name)")
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
        HStack(spacing: 2) {
            ScrollView (.horizontal) {
                HStack (spacing: 4) {
                    ForEach (Array (components.enumerated()), id: \.offset) { idx, v in
                        if idx == 0 {
                            Text (prefix)
                                .foregroundStyle(.secondary)
                        }
                        
                        if idx == components.count-1 {
                            // For the last element, we display the contents of all the peers, like Xcode
                            DirectoryView (prefix: prefix, basePath: PathBrowser.makePath (prefix: prefix, components, idx-1), element: String(v))
                        } else {
                            // List the elements of this directory.
                            DirectoryView (prefix: prefix, basePath: PathBrowser.makePath (prefix: prefix, components, idx), element: String(v))
                                .foregroundStyle(.primary)
                            Image (systemName: "chevron.compact.right")
                                .foregroundColor(.secondary)
                        }
                    }
                }
                .font(.caption)
            }
            .scrollIndicators(.hidden)

            Spacer ()
            Menu {
                FunctionView (functions: item.functions) { line in
                    item.commands.requestGoto(line: line)
                }
            } label: {
                Image (systemName: "arrow.down.to.line")
                    .font(.caption)
                    .foregroundStyle(Color.primary)
            }
            .foregroundStyle(.secondary)
        }
        .padding([.vertical], 10)
    }

}

#Preview {
    VStack (alignment: .leading){
        Text ("Path:")

        PathBrowser(item: EditedItem(path: "res://addons/files/text.gd", content: "demo", editedItemDelegate: nil))
        PathBrowser(item: EditedItem(path: "res://users/More/Longer/Very/Long/Path/NotSure/Where/ThisWouldEverEnd/With/ContainersAndOthers/addons/files/text.gd", content: "demo", editedItemDelegate: nil))

    }
    .environment(HostServices.makeTestHostServices())
    .environment(CodeEditorState())
    .padding()
}
