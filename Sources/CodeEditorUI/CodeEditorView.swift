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
import Runestone

enum CodeEditorStatus {
    case ok
    case notFound
}

public struct CodeEditorView: View {
    @Environment(HostServices.self) var hostServices: HostServices
    @Binding var contents: String
    @State var status: CodeEditorStatus
    let onChange: (_ textView: TextView)->()
    var item: EditedItem
    
    public init (item: EditedItem, contents: Binding<String>, onChange: @escaping (_ textView: TextView) ->()) {
        self.item = item
        self._status = State(initialValue: .ok)
        self._contents = contents
        self.onChange = onChange
    }
    
    public var body: some View {
        ZStack {
            TextViewUI(text: $contents, onChange: onChange)
                .onAppear {
                    switch hostServices.loadFile (path: item.path){
                    case .success(let contents):
                        self.contents = contents
                        status = .ok
                    case .failure:
                        status = .notFound
                    }
                    
                }
                .language (item.language)
            if let req = item.completionRequest {
                CompletionsDisplayView(prefix: req.prefix, completions: req.completions)
                    .background { Color (uiColor: .systemBackground) }
            }
        }
    }
}

struct DemoCodeEditorView: View {
    @State var text: String = "This is just a sample"
    
    var body: some View {
        CodeEditorView(item: EditedItem(path: "/Users/miguel/cvs/godot-master/modules/gdscript/tests/scripts/utils.notest.gd", content: text, data: nil), contents: $text, onChange: { textView in })
    }
}
#Preview {
    DemoCodeEditorView()
}
