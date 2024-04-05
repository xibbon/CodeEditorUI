import SwiftUI
import Runestone
import TreeSitter
import RunestoneUI
import TreeSitterGDScriptRunestone

/// Represents an edited item in the code editor, it uses a path to reference it, and expect that it
/// can be loaded and saved via the HostServices variable.
@Observable
public class EditedItem: Identifiable, Hashable, Equatable {
    public static func == (lhs: EditedItem, rhs: EditedItem) -> Bool {
        lhs.path == rhs.path && lhs.data === rhs.data
        
    }
    
    public func hash(into hasher: inout Hasher) {
        path.hash(into: &hasher)
    }
    
    /// Returns the filename that is suitable to be displayed to the user
    public var filename: String {
        if let s = path.lastIndex(of: "/"){
            return String (path [path.index(after: s)...])
        }
        return path
    }
    public var id: String { path }
    
    /// The path of the file that we are editing
    public var path: String
    
    /// User-defined paylog for additional data
    public var data: AnyObject?
    
    public var content: String = ""
    
    public var language: TreeSitterLanguage? = nil
    
    /// - Parameters:
    ///  - path: the path that will be passed to the HostServices API to load and save the file
    ///  - data: this is data that can be attached to this object and extracted a later point by the user
    public init (path: String, content: String, data: AnyObject?) {
        if path.hasSuffix(".gd") {
            language = TreeSitterLanguage.gdscript
        } else {
            language = nil
        }
        self.path = path
        self.content = content
        self.data = data
    }
    
    var completionRequest: CompletionRequest? = nil
    
    public func requestCompletion (at: CGRect, prefix: String, completions: [CompletionEntry]) {
        completionRequest = CompletionRequest(at: at, prefix: prefix, completions: completions)
    }
}

/// This is the host for all of the coding needs that we have
public struct CodeEditorShell: View {
    @Environment(HostServices.self) var hostServices
    @Binding var state: CodeEditorState
    @State var TODO: String = ""
    @State var errorSaving: Bool = false
    @State var errorMessage: String = ""
    @State var saveIdx: Int = 0
    
    public init (state: Binding<CodeEditorState>) {
        self._state = state
    }

    func attemptSave (_ idx: Int) -> Bool {
        saveIdx = idx
        if let error = hostServices.saveContents(contents: state.openFiles[idx].content, path: state.openFiles[idx].path) {
            errorMessage = error.localizedDescription
            errorSaving = true
            return false
        }
        return true
    }
    
    func closeFile (_ idx: Int) {
        state.openFiles.remove(at: idx)
        if idx == state.currentEditor {
            if state.openFiles.count == 0 {
                state.currentEditor = nil
            } else {
                if let ce = state.currentEditor {
                    state.currentEditor = ce-1
                }
            }
        }
    }
    
    func attemptClose (_ idx: Int) {
        if attemptSave (idx) {
            closeFile (idx)
        }
    }
    
    public var body: some View {
        VStack (spacing: 0) {
            EditorTabs(selected: $state.currentEditor, items: $state.openFiles, closeRequest: { idx in
                
                attemptClose (idx)
            })
            .alert("Error", isPresented: $errorSaving) {
                Button ("Retry") {
                    errorSaving = false
                    DispatchQueue.main.async {
                        attemptClose(saveIdx)
                    }
                }
                Button ("Cancel") {
                    errorSaving = false
                }
                Button ("Ignore") {
                    closeFile (saveIdx)
                    errorSaving = false
                }
            } message: {
                Text (errorMessage)
            }
            Divider()

            if let currentIdx = state.currentEditor, currentIdx >= 0, currentIdx < state.openFiles.count  {
                let current = state.openFiles [currentIdx]
                PathBrowser (path: current.path)
                    .environment(state)
                
                CodeEditorView(item: current, contents: Binding<String>(get: { current.content }, set: { newV in current.content = newV })) { textView in
                    state.change (current, textView)
                }
            }
        }
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
    DemoCodeEditorShell ()
}
