//
//  CodeEditorView.swift
//
//
//  Created by Miguel de Icaza on 3/29/24.
//
// TODO: onAppear is not triggered for new files opened, so the buffers are empty
// TODO: RuneStone crashs when the initial content is empty and we type text.


import SwiftUI
import RunestoneUI
import TreeSitterGDScriptRunestone


enum CodeEditorStatus {
    case ok
    case notFound
}

public struct CodeEditorView: View {
    @Environment(HostServices.self) var hostServices: HostServices
    @Binding var contents: String
    @State var status: CodeEditorStatus
    
    var item: EditedItem
    
    public init (item: EditedItem, contents: Binding<String>) {
        self.item = item
        self._status = State(initialValue: .ok)
        self._contents = contents
    }
    
    public var body: some View {
        TextViewUI(text: $contents)
            .onAppear {
                switch hostServices.loadFile (path: item.path){
                case .success(let contents):
                    self.contents = contents
                    status = .ok
                case .failure:
                    status = .notFound
                }

            }
            .language(.gdscript)
    }
}

struct DemoCodeEditorView: View {
    @State var text: String = ""
    
    var body: some View {
        CodeEditorView(item: EditedItem(path: "/Users/miguel/cvs/godot-master/modules/gdscript/tests/scripts/utils.notest.gd", data: nil), contents: $text)
    }
}
#Preview {
    DemoCodeEditorView()
}
