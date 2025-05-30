import SwiftUI
import Runestone
import TreeSitter
import RunestoneUI
import TreeSitterGDScriptRunestone

/// This is the host for all of the coding needs that we have
public struct CodeEditorShell<EmptyContent: View>: View {
    @State var state: CodeEditorState
    @State var showDiagnosticDetails = false
    @FocusState var isFocused: Bool
    let emptyContent: () -> EmptyContent
    let urlLoader: (URL) -> String?

    /// Creates the CodeEditorShell
    /// - Parameters:
    ///   - state: The state used to control this CodeEditorShell
    ///   - urlLoader: This should load a URL, and upon successful completion, it can return an anchor to scroll to, or nil otherwise
    ///   - emptyView: A view to show if there are no tabs open
    public init (state: CodeEditorState, urlLoader: @escaping (URL) -> String?, @ViewBuilder emptyView: @escaping ()->EmptyContent) {
        self._state = State(initialValue: state)
        self.emptyContent = emptyView
        self.urlLoader = urlLoader
    }

    @ViewBuilder
    func diagnosticBlurb (editedItem: EditedItem) -> some View {
        HStack {
            if let warnings = editedItem.warnings {
                Button (action: { showDiagnosticDetails.toggle () }) {
                    HStack (spacing: 4){
                        Image (systemName: "exclamationmark.triangle.fill")
                        Text ("\(warnings.count)")
                    }.foregroundStyle(Color.orange)
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
            if editedItem.warnings != nil || editedItem.errors != nil {
                Button (action: { withAnimation { showDiagnosticDetails.toggle() } }) {
                    HStack (spacing: 4) {
                        Image (systemName: "chevron.right")
                            .rotationEffect(showDiagnosticDetails ? Angle (degrees: 90) : Angle(degrees: 0))
                    }
                }
                .foregroundStyle(.secondary)
                .padding (.horizontal, 8)
            }
        }
    }

    func focusEditor() {
        DispatchQueue.main.asyncAfter(deadline: .now()+0.3) {
            isFocused = true
        }
    }
    
    @State var disclosureControlWidth: CGFloat = 0
    @State var errorWindowWidth: CGFloat = 0
    
    @ViewBuilder
    var editorContent: some View {
        if let currentIdx = state.currentEditor, currentIdx >= 0, currentIdx < state.openFiles.count  {
            let current = state.openFiles [currentIdx]
            ZStack {
                ForEach (state.openFiles) { file in
                    Group {
                        if let editedItem = file as? EditedItem {
                            VStack(spacing: 0) {
                                if state.showPathBrowser {
                                    PathBrowser (item: editedItem)
                                        .environment(state)
                                        .padding(.bottom, 0)
                                        .padding(.horizontal, 10)
                                    Divider()
                                }
                                ZStack(alignment: .top) {
                                    CodeEditorView(
                                        state: state,
                                        item: editedItem,
                                        contents: Binding<String>(get: {
                                            editedItem.content
                                        }, set: { newV in
                                            editedItem.content = newV
                                        })
                                    )
                                    .focusable()
                                    .id(file)
                                    .focused($isFocused, equals: true)
                                    if state.showGotoLine {
                                        GotoLineView(showing: $state.showGotoLine) { newLine in
                                            editedItem.commands.requestGoto(line: newLine-1)
                                            DispatchQueue.main.asyncAfter(deadline: .now()+0.1) {
                                                editedItem.commands.becomeFirstResponder()
                                            }
                                        }
                                    }
                                }
                                .zIndex(1)
                                    
                                if showDiagnosticDetails || editedItem.errors != nil || editedItem.warnings != nil {
                                    Divider()
                                }
                                if showDiagnosticDetails,
                                   ((editedItem.errors?.count ?? 0) > 0 || (editedItem.warnings?.count ?? 0) > 0) {
                                    ZStack(alignment: .topLeading) {
                                        DiagnosticDetailsView(errors: editedItem.errors, warnings: editedItem.warnings, item: editedItem, maxFirstLine: errorWindowWidth-disclosureControlWidth)
                                        HStack {
                                            Spacer()
                                            diagnosticBlurb (editedItem: editedItem)
                                                .padding(.top, 8)
                                                .padding(.bottom, 10)
                                                .padding(.horizontal, 10)
                                                .font(.footnote)
                                                .background(Color(.systemBackground))
                                                .onGeometryChange(for: CGFloat.self) {
                                                    $0.size.width
                                                } action: {
                                                    disclosureControlWidth = $0
                                                }
                                        }
                                    }
                                    .onGeometryChange(for: CGFloat.self) {
                                        $0.size.width
                                    } action: {
                                        errorWindowWidth = $0
                                    }
                                    .frame(maxHeight: 120)
                                } else if let hint = editedItem.hint {
                                    HStack {
                                        Button (action: { showDiagnosticDetails.toggle()}) {
                                            ShowHint(text: hint)
                                                .fontDesign(.monospaced)
                                                .lineLimit(1)
                                        }.buttonStyle(.plain)
                                        Spacer ()
                                        diagnosticBlurb (editedItem: editedItem)
                                    }
                                    .padding(.top, 8)
                                    .padding(.bottom, 10)
                                    .padding(.horizontal, 10)
                                    .font(.footnote)
                                } else if let firstError = editedItem.errors?.first ?? editedItem.warnings?.first {
                                    HStack {
                                        Button (action: { showDiagnosticDetails.toggle()}) {
                                            ShowIssue (issue: firstError)
                                                .fontDesign(.monospaced)
                                                .lineLimit(1)
                                        }.buttonStyle(.plain)
                                        Spacer ()
                                        diagnosticBlurb (editedItem: editedItem)
                                    }
                                    .padding(.top, 8)
                                    .padding(.bottom, 10)
                                    .padding(.horizontal, 10)
                                    .font(.footnote)
                                }
                            }
                        } else if let htmlItem = file as? HtmlItem {
                            WebView(text: htmlItem.content,
                                    anchor: htmlItem.anchor,
                                    obj: htmlItem,
                                    load: urlLoader)
                            Spacer()
                        } else if let swifuiItem = file as? SwiftUIHostedItem {
                            swifuiItem.view()
                        }
                    }
                    .opacity(current.id == file.id ? 1 : 0)
                }
            }
        } else {
            emptyContent()
        }
    }
    
    var fileMenu: some View {
        Menu {
            Button(action: {
                state.requestFileOpen(title: "Open Shader", path: "res://") { files in
                    guard let file = files.first else { return }
                    
                    state.requestOpen(path: file)
                }
            }) {
                Text("Open Shader")
            }
            Button(action: {
                state.saveCurrentFile()
            }) {
                Text("Save Shader")
            }
            Button(action: {
                state.saveFileAs()
            }) {
                Text("Save Shader As...")
            }
        } label: {
            Text("File")
        }
    }

    public var body: some View {
        VStack {
            HStack {
                if state.showFileMenu, state.openFiles.count > 0  {
                    fileMenu
                }
                EditorTabs(selected: $state.currentEditor, items: $state.openFiles, closeRequest: { idx in
                    state.attemptClose (idx)
                })
            }
            .alert("Error", isPresented: Binding<Bool>(get: { state.saveError }, set: { newV in state.saveError = newV })) {
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

            editorContent
                .background {
                    RoundedRectangle(cornerRadius: 11)
                        .fill(Color(uiColor: .systemBackground))
                        .stroke(Color(uiColor: .systemGray5))
                }
                .clipShape(RoundedRectangle (cornerRadius: 11))
        }
        //.background { Color (uiColor: .systemBackground) }

        .padding(8)
    }
}

/// This shows a single line from the hint string, we need to figure out a good way of showing all the lines
struct ShowHint: View {
    let str: AttributedString

    init(text: String) {
        var str = AttributedString()
        let lines = text.split(separator: "\n")

        let ranges = lines[0].ranges(of: "\u{ffff}")
        if ranges.count == 2 {
            var highlighted = AttributedString(text[ranges[0].upperBound..<ranges[1].lowerBound])
            highlighted.foregroundColor = UIColor.systemBackground
            highlighted.backgroundColor = Color.primary

            str.append(AttributedString(text[text.startIndex..<ranges[0].lowerBound]))
            str.append(highlighted)
            str.append(AttributedString(text[ranges[1].upperBound...]))
        } else {
            str.append(AttributedString(lines[0]))
        }
        self.str = str
    }

    var body: some View {
        Text(str)
    }
}


#if DEBUG
class DemoCodeEditorState: CodeEditorState {
    override func requestFileSaveAs(title: LocalizedStringKey, path: String, complete: @escaping ([String]) -> ()) {
        complete (["picked.gd"])
    }
    
    override func requestOpen(path: String) {
        print ("File \(path) shoudl be opened")
    }
}

struct DemoCodeEditorShell: View {
    @State var state: CodeEditorState = DemoCodeEditorState()

    var body: some View {
        VStack {
            Button("Show Go-To Line") {
                state.showGotoLine = true
            }
            
            Text ("\(Bundle.main.resourceURL) xx Path=\(Bundle.main.paths(forResourcesOfType: ".gd", inDirectory: "/tmp"))")
            CodeEditorShell (state: state) { request in
                print ("Loading \(request)")
                return nil
            } emptyView: {
                Text ("No Files Open")
            }
            .onAppear {
                _ = state.openHtml(title: "Help", path: "foo.html", content: "<html><body><title>Hello</title><p>hack</body>")
                switch state.openFile(path: "/etc/passwd", delegate: nil, fileHint: .detect) {
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
}

#Preview {
    ZStack {
        Color(uiColor: .systemGray6)
        DemoCodeEditorShell ()
    }
}
#endif
