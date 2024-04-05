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
    let state: CodeEditorState
    
    public init (state: CodeEditorState, item: EditedItem, contents: Binding<String>, onChange: @escaping (_ textView: TextView) ->()) {
        self.state = state
        self.item = item
        self._status = State(initialValue: .ok)
        self._contents = contents
        self.onChange = onChange
    }
    
    public var body: some View {
        ZStack (alignment: .topLeading){
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
                .lineHeightMultiplier(1.0)
                .showTabs(state.showTabs)
                .showLineNumbers(state.showLines)
                .showSpaces(state.showSpaces)
            if let req = item.completionRequest {
                CompletionsDisplayView(prefix: req.prefix, completions: req.completions)
                    .background { Color (uiColor: .systemBackground) }
                    .offset(x: req.at.minX, y: req.at.maxY+8)
            }
        }
    }
}

struct DemoCodeEditorView: View {
    @State var text: String = "This is just a sample"
    
    var body: some View {
        CodeEditorView(state: CodeEditorState(), item: EditedItem(path: "/Users/miguel/cvs/godot-master/modules/gdscript/tests/scripts/utils.notest.gd", content: text, data: nil), contents: $text, onChange: { textView in })
            .environment(HostServices.makeTestHostServices())
    }
}
#Preview {
    DemoCodeEditorView()
}
