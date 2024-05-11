import SwiftUI
import Runestone
import TreeSitter
import RunestoneUI
import TreeSitterGDScriptRunestone

/// This is the host for all of the coding needs that we have
public struct CodeEditorShell<EmptyContent:View>: View {
    @Environment(HostServices.self) var hostServices
    @Binding var state: CodeEditorState
    @State var showDiagnosticDetails = false
    let emptyContent: () -> EmptyContent
    let urlLoader: (URL) -> String?
    
    public init (state: Binding<CodeEditorState>, urlLoader: @escaping (URL) -> String?, @ViewBuilder emptyView: @escaping ()->EmptyContent) {
        self._state = state
        self.emptyContent = emptyView
        self.urlLoader = urlLoader
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
                if let editedItem = current as? EditedItem {
                    PathBrowser (item: editedItem)
                        .environment(state)
                        .padding ([.horizontal], 4)
                    Divider()
                    CodeEditorView(state: state, item: editedItem, contents: Binding<String>(get: { editedItem.content }, set: { newV in editedItem.content = newV }))
                        .id(current)
                    Divider()
                    HStack {
                        if !showDiagnosticDetails, let firstError = editedItem.errors?.first {
                            Button (action: { showDiagnosticDetails.toggle()}) {
                                ShowIssue (issue: firstError)
                                    .fontDesign(.monospaced)
                                    .lineLimit(1)
                            }.buttonStyle(.plain)
                        }
                        Spacer ()
                        if let warnings = editedItem.warnings {
                            Button (action: { showDiagnosticDetails.toggle () }) {
                                HStack (spacing: 4){
                                    Image (systemName: "exclamationmark.triangle.fill")
                                    Text ("\(warnings.count)")
                                }.foregroundStyle(Color.yellow)
                            }
                        }
                        if let errors = editedItem.errors {
                            Button (action: { showDiagnosticDetails.toggle() }) {
                                HStack (spacing: 4) {
                                    Image (systemName: "xmark.circle.fill")
                                    Text ("\(errors.count)")
                                }.foregroundStyle(Color.red)
                            }
                        }
                        if showDiagnosticDetails {
                            Button (action: { showDiagnosticDetails = false }) {
                                Image (systemName: "xmark.circle")
                            }
                        }
                    }
                    .padding ([.trailing])
                    .font(.footnote)
                    if showDiagnosticDetails, editedItem.errors != nil || editedItem.warnings != nil {
                        DiagnosticDetailsView(errors: editedItem.errors, warnings: editedItem.warnings)
                            .frame(maxHeight: 120)
                    }
                } else if let htmlItem = current as? HtmlItem {
                    WebView(text: Binding<String>(get: { htmlItem.content }, set: { newV in htmlItem.content = newV }),
                            load: urlLoader)
                    Spacer()
                }
            } else {
                emptyContent()
            }
        }
        
        .background { Color (uiColor: .systemBackground) }
    }
}

struct DemoCodeEditorShell: View {
    @State var state: CodeEditorState = CodeEditorState(hostServices: HostServices.makeTestHostServices())
    @State var hostServices = HostServices.makeTestHostServices()
    
    var body: some View {
        CodeEditorShell (state: $state) { request in
            print ("Loading \(request)")
            return nil
        } emptyView: {
            Text ("No Files Open")
        }
            .environment(hostServices)
            .onAppear {
                switch state.openFile(path: "/Users/miguel/cvs/godot-master/modules/gdscript/tests/scripts/utils.notest.gd", delegate: nil, fileHint: .detect) {
                case .success(let item):
                    item.validationResult (
                        functions: [],
                        errors: [Issue(kind: .error, col: 1, line: 1, message: "Demo Error, with a very long descrption that makes it up for the very difficult task of actually having to wrap around")],
                        warnings: [Issue(kind: .warning, col: 1, line: 1, message: "Demo Warning")])
                case .failure(let err):
                    print ("Error: \(err)")
                    break
                }
            }
    }
}
#Preview {
    ZStack {
        Color.red
        DemoCodeEditorShell ()
    }
}
