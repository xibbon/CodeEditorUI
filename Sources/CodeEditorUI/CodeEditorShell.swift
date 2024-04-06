import SwiftUI
import Runestone
import TreeSitter
import RunestoneUI
import TreeSitterGDScriptRunestone

/// This is the host for all of the coding needs that we have
public struct CodeEditorShell: View {
    @Environment(HostServices.self) var hostServices
    @Binding var state: CodeEditorState
    @State var TODO: String = ""
    
    public init (state: Binding<CodeEditorState>) {
        self._state = state
    }

    public var body: some View {
        VStack (spacing: 0) {
            EditorTabs(selected: $state.currentEditor, items: $state.openFiles, closeRequest: { idx in
                
                state.attemptClose (idx)
            })
            .alert("Error", isPresented: Binding<Bool>(get: { state.saveError}, set: { newV in state.saveError = newV })) {
                Button ("Retry") {
                    state.saveError = false
                    DispatchQueue.main.async {
                        state.attemptClose(state.saveIdx)
                    }
                }
                Button ("Cancel") {
                    state.saveError = false
                }
                Button ("Ignore") {
                    state.closeFile (state.saveIdx)
                    state.saveError = false
                }
            } message: {
                Text (state.saveErrorMessage)
            }
            Divider()

            if let currentIdx = state.currentEditor, currentIdx >= 0, currentIdx < state.openFiles.count  {
                let current = state.openFiles [currentIdx]
                PathBrowser (path: current.path)
                    .environment(state)
                    .padding ([.horizontal], 4)
                Divider()
                CodeEditorView(state: state, item: current, contents: Binding<String>(get: { current.content }, set: { newV in current.content = newV })) { textView in
                    state.change (current, textView)
                }
            }
        }
        .background { Color (uiColor: .systemBackground) }
    }
}

struct DemoCodeEditorShell: View {
    @State var state: CodeEditorState = CodeEditorState(hostServices: HostServices.makeTestHostServices())
    @State var hostServices = HostServices.makeTestHostServices()
    
    var body: some View {
        CodeEditorShell (state: $state)
            .environment(hostServices)
            .onAppear {
                state.openFile(path: "/Users/miguel/cvs/godot-master/modules/gdscript/tests/scripts/utils.notest.gd", data: nil)
            }
    }
}
#Preview {
    ZStack {
        Color.red
        DemoCodeEditorShell ()
    }
}
