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
    var item: EditedItem
    let state: CodeEditorState
    
    public init (state: CodeEditorState, item: EditedItem, contents: Binding<String>) {
        self.state = state
        self.item = item
        self._status = State(initialValue: .ok)
        self._contents = contents
    }
    
    func onChange (_ textView: TextView) {
        item.editedTextChanged(on: textView)
    }
    
    func insertCompletion () {
        guard let req = item.completionRequest else { return }
        let insertFull = req.completions[item.selected].insert
        let count = req.prefix.count
        let startLoc = req.on.selectedRange.location-count
        if startLoc >= 0 {
            let r = NSRange (location: startLoc, length: count)
            req.on.replace(r, withText: insertFull)
        }
        item.cancelCompletion()
    }
    
    public var body: some View {
        ZStack (alignment: .topLeading){
//            TextViewUI(text: $contents,
//                       onChange: onChange,
//                       gotoRequest: Binding<Int?>(
//                        get: { item.gotoLineRequest },
//                        set: { newV in item.gotoLineRequest = newV }),
//                       findRequest: Binding<FindKind?>(
//                        get: { item.findRequest },
//                        set: { newV in item.findRequest = newV })
//                       )
            TextViewUI (text: $contents,
                        onChange: onChange,
                        commands: item.commands)
            .onAppear {
                    switch hostServices.loadFile (path: item.path){
                    case .success(let contents):
                        self.contents = contents
                        status = .ok
                    case .failure:
                        status = .notFound
                    }
                }
                .onKeyPress(.downArrow) {
                    if let req = item.completionRequest {
                        if item.selected < req.completions.count {
                            item.selected += 1
                        }
                        return .handled
                    }
                    return .ignored
                }
                .onKeyPress(.upArrow) {
                    if item.completionRequest != nil {
                        if item.selected > 0 {
                            item.selected -= 1
                        }
                        return .handled
                    }
                    return .ignored
                }
                .onKeyPress(.return) {
                    if item.completionRequest != nil {
                        insertCompletion ()
                        return .handled
                    }
                    return .ignored
                }
                .language (item.language)
                .lineHeightMultiplier(1.0)
                .showTabs(state.showTabs)
                .showLineNumbers(state.showLines)
                .showSpaces(state.showSpaces)
                .characterPairs(codingPairs)
            if let req = item.completionRequest {
                CompletionsDisplayView(
                    prefix: req.prefix,
                    completions: req.completions,
                    selected: Binding<Int> (get: { item.selected}, set: { newV in  item.selected = newV }),
                    onComplete: insertCompletion)
                    .background { Color (uiColor: .systemBackground) }
                    .offset(x: req.at.minX, y: req.at.maxY+8)
            }
        }
    }
}

struct DemoCodeEditorView: View {
    @State var text: String = "This is just a sample"
    
    var body: some View {
        CodeEditorView(state: CodeEditorState(),
                       item: EditedItem(
                        path: "/Users/miguel/cvs/godot-master/modules/gdscript/tests/scripts/utils.notest.gd",
                        content: text,
                        editedItemDelegate: nil),
                       contents: $text)
            .environment(HostServices.makeTestHostServices())
    }
    
    func changed(_ editedItem: EditedItem, _ textView: TextView) {
        //
    }
}
#Preview {
    DemoCodeEditorView()
}

let codingPairs = [
    BasicCharacterPair(leading: "(", trailing: ")"),
    BasicCharacterPair(leading: "{", trailing: "}"),
    BasicCharacterPair(leading: "[", trailing: "]"),
    BasicCharacterPair(leading: "\"", trailing: "\""),
    BasicCharacterPair(leading: "'", trailing: "'")
]

struct BasicCharacterPair: CharacterPair {
    let leading: String
    let trailing: String
}
