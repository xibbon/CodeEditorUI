import SwiftUI
import Runestone
import TreeSitter
import RunestoneUI
import TreeSitterGDScriptRunestone

/// This is the host for all of the coding needs that we have
@available(iOS 18.0, *)
public struct CodeEditorShell<EmptyContent: View, CodeEditorMenu: View>: View {
    @Environment(\.dismiss) var dismiss
    @State var state: CodeEditorState
    @State var showDiagnosticDetails = false
    @FocusState var isFocused: Bool
    let emptyContent: () -> EmptyContent
    let urlLoader: (URL) -> String?
    var codeEditorMenu: (() -> CodeEditorMenu)?

    /// Creates the CodeEditorShell
    /// - Parameters:
    ///   - state: The state used to control this CodeEditorShell
    ///   - urlLoader: This should load a URL, and upon successful completion, it can return an anchor to scroll to, or nil otherwise
    ///   - emptyView: A view to show if there are no tabs open
    ///   - codeEditorMenu: A view to show injected menu
    public init (state: CodeEditorState, urlLoader: @escaping (URL) -> String?, @ViewBuilder emptyView: @escaping ()->EmptyContent, @ViewBuilder codeEditorMenu: @escaping () -> CodeEditorMenu) {
        self._state = State(initialValue: state)
        self.emptyContent = emptyView
        self.urlLoader = urlLoader
        self.codeEditorMenu = codeEditorMenu
    }

    /// Creates the CodeEditorShell
    /// - Parameters:
    ///   - state: The state used to control this CodeEditorShell
    ///   - urlLoader: This should load a URL, and upon successful completion, it can return an anchor to scroll to, or nil otherwise
    ///   - emptyView: A view to show if there are no tabs open
    ///   - codeEditorMenu: A view to show injected menu
    public init (state: CodeEditorState, urlLoader: @escaping (URL) -> String?, @ViewBuilder emptyView: @escaping ()->EmptyContent) where CodeEditorMenu == EmptyView {
        self._state = State(initialValue: state)
        self.emptyContent = emptyView
        self.urlLoader = urlLoader
        self.codeEditorMenu = nil
    }

    @ViewBuilder
    func diagnosticBlurb (editedItem: EditedItem) -> some View {
        HStack {
            if let warnings = editedItem.warnings {
                Button (action: { showDiagnosticDetails.toggle () }) {
                    HStack (spacing: 4){
                        Image (systemName: "exclamationmark.triangle.fill")
                        Text (verbatim: "\(warnings.count)")
                    }.foregroundStyle(Color.orange)
                }
            }
            if let errors = editedItem.errors {
                Button (action: { showDiagnosticDetails.toggle() }) {
                    HStack (spacing: 4) {
                        Image (systemName: "xmark.circle.fill")
                        Text (verbatim: "\(errors.count)")
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
                                        Button (action: {
                                            withAnimation {
                                                showDiagnosticDetails.toggle()
                                            }
                                        }) {
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
                                        Button (action: {
                                            withAnimation {
                                                showDiagnosticDetails.toggle()
                                            }
                                        }) {
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

    // This function for now works with just edited items, as we only use it
    // in the 'navigation' mode which is the iPhone, and only for shaders, not
    // for the main editor - in that case, we would need to change this to
    // also handle HostedItems
    func getTitle() -> String {
        if let current = state.getCurrentEditedItem() {
            return current.filename
        } else {
            return String(localized: .shaderEditor)
        }
    }
    public var body: some View {
        VStack {
            HStack {
                if state.useNavigation {
                    Color.clear.frame(height: 0)
                        .navigationTitle(getTitle())
                        .navigationBarTitleDisplayMode(.inline)
                } else {
                    if let codeEditorMenu, state.openFiles.count > 0 {
                        codeEditorMenu()
                    }
                    EditorTabs(selected: $state.currentEditor, items: $state.openFiles, closeRequest: { idx in
                        state.attemptClose (idx)
                    })
                }
            }
            .alert(String(localized: .error), isPresented: Binding<Bool>(get: { state.saveError }, set: { newV in state.saveError = newV })) {
                Button (.retry) {
                    state.saveError = false
                    DispatchQueue.main.async {
                        state.attemptClose(state.saveIdx)
                    }
                }
                Button (.cancel) {
                    state.saveError = false
                }
                Button (.ignore) {
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
        .toolbar {
            if state.useNavigation {
                ToolbarTitleMenu {
                    ForEach(Array(state.openFiles.enumerated()), id: \.offset) { offset, element in
                        Button(action: {
                            state.currentEditor = offset
                        }) {
                            Text(element.title)
                        }
                    }
                }
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                    }
                }
                if #available(iOS 26.0, *) {
                    ToolbarSpacer(.fixed, placement: .topBarLeading)
                }

                if let codeEditorMenu {
                    ToolbarItem(placement: .topBarLeading) {
                        codeEditorMenu()
                    }
                }
                ToolbarItem {
                    Button(action: { state.showGotoLine = true }) {
                        Image(systemName: "number")
                    }
                }
            }
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
    override func requestFileSaveAs(title: String, path: String, complete: @escaping ([String]) -> ()) {
        complete (["picked.gd"])
    }
    
    override func requestOpen(path: String) {
        print ("File \(path) shoudl be opened")
    }
}

@available(iOS 18.0, *)
struct DemoCodeEditorShell: View {
    @State var state: CodeEditorState = DemoCodeEditorState()

    init(phone: Bool) {
        state.useNavigation = phone
    }
    
    var body: some View {
        VStack {
            Button(action: {
                state.showGotoLine = true
            }) {
                Text(verbatim: "Go To Line")
            }
            
            Text (verbatim: "\(String(describing: Bundle.main.resourceURL)) Path=\(String(describing: Bundle.main.paths(forResourcesOfType: ".gd", inDirectory: "/tmp")))")
            CodeEditorShell (state: state) { request in
                print ("Loading \(request)")
                return nil
            } emptyView: {
                Text (verbatim: "No Files Open")
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
    if UIDevice.current.userInterfaceIdiom == .pad {
        ZStack {
            Color(uiColor: .systemGray6)
            if #available(iOS 18.0, *) {
                DemoCodeEditorShell(phone: false)
            } else {
                // Fallback on earlier versions
            }
        }
    } else {
        NavigationStack {
            if #available(iOS 18.0, *) {
                DemoCodeEditorShell(phone: true)
            } else {
                // Fallback on earlier versions
            }
        }
    }
}
#endif
