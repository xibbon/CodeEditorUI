//
//  SwiftUIView.swift
//  
//
//  Created by Miguel de Icaza on 3/29/24.
//

import SwiftUI
import RunestoneUI
import TreeSitterGDScriptRunestone


enum CodeEditorStatus {
    case ok
    case notFound
}

public struct CodeEditorView: View {
    @Environment(HostServices.self) var hostServices: HostServices
    @State var contents: String
    @State var status: CodeEditorStatus
    
    var item: EditedItem
    
    public init (item: EditedItem) {
        self.item = item
        self._status = State(initialValue: .ok)
        self._contents = State(initialValue: "")
    }
    
    public var body: some View {
        Text ("Hello")
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

#Preview {
    CodeEditorView(item: EditedItem(path: "/Users/miguel/cvs/godot-master/modules/gdscript/tests/scripts/utils.notest.gd", data: nil))
}
