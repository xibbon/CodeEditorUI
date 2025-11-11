//
//  CodeEditorView.swift
//
//
//  Created by Miguel de Icaza on 3/29/24.
//

import SwiftUI
import UniformTypeIdentifiers

#if canImport(UIKit)
import RunestoneUI
import TreeSitterGDScriptRunestone
import Runestone
public typealias RTextView = Runestone.TextView
#else
public typealias RTextView = TextView
#endif

enum CodeEditorStatus {
    case ok
    case notFound
}

public struct CodeEditorView: View, DropDelegate, TextViewUIDelegate {
    @State var codeEditorSize: CGSize = .zero
    @Binding var contents: String
    @State var status: CodeEditorStatus
    @State var keyboardOffset: CGFloat = 0
    @State var lookupWord: String = ""
    @State var completionInProgress: Bool = false
    @State var textOffset: CGFloat = 0

    var item: EditedItem
    let state: CodeEditorState

    public init (state: CodeEditorState, item: EditedItem, contents: Binding<String>) {
        self.state = state
        self.item = item
        self._status = State(initialValue: .ok)
        self._contents = contents
    }

    public func uitextViewChanged(_ textView: RTextView) {
        item.editedTextChanged(on: textView)
    }

    public func uitextViewDidChangeSelection(_ textView: TextView) {
        item.editedTextSelectionChanged(on: textView)
    }

    public func uitextViewLoaded(_ textView: RTextView) {
        item.started(on: textView)
    }

    public func uitextViewGutterTapped(_ textView: RTextView, line: Int) {
        item.gutterTapped(on: textView, line: line)
    }

    public func uitextViewRequestWordLookup(_ textView: RTextView, at position: UITextPosition, word: String) {
        item.editedItemDelegate?.lookup(item, on: textView, at: position, word: word)
    }
    
    public func uitextViewTryCompletion() -> Bool {
        if item.completionRequest != nil {
            insertCompletion ()
            return true
        } else {
            return false
        }
    }

    public func uitextViewDidInvalidateBreakpoints(_ textView: TextView, changeLineIndex: Int, diff: Int) {
        var sortedBP = item.breakpoints.sorted()
        for i in 0..<sortedBP.count  {
            if sortedBP[i] >= changeLineIndex {
                sortedBP[i] = sortedBP[i] + diff
            }
        }
        self.item.breakpoints = Set(sortedBP)
    }

    func insertCompletion () {
        guard let req = item.completionRequest else { return }
        completionInProgress = true
        if item.selectedCompletion > req.completions.count {
            print("item.selectedCompletion=\(item.selectedCompletion) > req.completions.count=\(req.completions.count)")
            return
        }
        let insertFull = req.completions[item.selectedCompletion].insert
        let count = req.prefix.count
        let startLoc = req.on.selectedRange.location-count
        if startLoc >= 0 {
            var r = NSRange (location: startLoc, length: count)
            if let currentText = req.on.text(in: r) {
                // Inserting a quote inserts an additional one #1450
                if insertFull.first == "\"" && insertFull.last == "\"" && currentText.first == "\"" {
                    if let suffix = req.on.text(in: NSRange(location: r.location + r.length, length: 1)), suffix == "\"" {
                        r.length += 1
                    }

                }
            }
            req.on.replace(r, withText: insertFull)
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            item.cancelCompletion()
            self.completionInProgress = false
        }

    }

    // Implementation of the DropDelegate method
    public func performDrop(info: DropInfo) -> Bool {
        let cmd = item.commands
        let offset = cmd.textView?.contentOffset.y
        // we need to include offset as well, otherwise it doesn't work
        guard let pos = cmd.closestPosition(to: CGPoint(x: info.location.x, y: info.location.y + (offset ?? 0))) else { return false }
        guard let range = cmd.textRange (from: pos, to: pos) else { return false }

        let result = Accumulator (range: range, cmd: cmd)
        var pending = 0

        for provider in info.itemProviders(for: [.text, .data]) {
            if provider.hasItemConformingToTypeIdentifier(UTType.data.identifier) {
                pending += 1
                provider.loadItem(forTypeIdentifier: UTType.data.identifier) { data, _ in
                    Task {
                        if let data = data as? Data, let file = try? JSONDecoder().decode(FileNode.self, from: data) {
                            for url in file.urls {
                                await result.push(state.encodeDroppedFile(path: url))
                            }
                        } else if let data = data as? Data, let scene = try? JSONDecoder().decode(SceneNode.self, from: data) {
                            await result.push(state.encodeScenePath(path: scene.path))
                        } else {
                            await result.error()
                            return
                        }
                        
                    }
                }
            }

            if provider.hasItemConformingToTypeIdentifier(UTType.text.identifier) {
                pending += 1
                provider.loadItem(forTypeIdentifier: UTType.text.identifier) { data, error in
                    Task {
                        if let data = data as? Data, let text = String(data: data, encoding: .utf8) {
                            await result.push (text)
                        } else {
                            await result.error ()
                        }
                    }
                }
            }
        }
        Task {
            await result.waitFor (pending)
        }
        return true
    }

    // Needed so we can show the cursor moving
    public func dropEntered(info: DropInfo) {
        item.commands.textView?.becomeFirstResponder()
    }

    // Update the cursor position near the drop site.
    public func dropUpdated(info: DropInfo) -> DropProposal? {
        let cmd = item.commands
        let offset = cmd.textView?.contentOffset.y
        // we need to include offset as well, otherwise it doesn't work
        guard let pos = cmd.closestPosition(to: CGPoint(x: info.location.x, y: info.location.y + (offset ?? 0))) else { return nil }
        cmd.selectedTextRange = cmd.textRange(from: pos, to: pos)

        return nil
    }

    public var body: some View {
        ZStack (alignment: .topLeading){
#if os(macOS)
            Text("This is where the editor goes")
#else
            let b = Bindable(item)
            TextViewUI (text: $contents,
                        commands: item.commands,
                        keyboardOffset: $keyboardOffset,
                        breakpoints: b.breakpoints,
                        delegate: self
            )
            .highlightLine(item.currentLine)
            .onDisappear {
                // When we go away, clear the completion request
                item.completionRequest = nil
            }
            .focusable()
            .spellChecking(.no)
            .autoCorrection(.no)
            .includeLookupSymbol(item.supportsLookup)
            .onKeyPress(.downArrow) {
                if let req = item.completionRequest {
                    if item.selectedCompletion < req.completions.count {
                        item.selectedCompletion += 1
                    }
                    return .handled
                }
                return .ignored
            }
            .onKeyPress(.upArrow) {
                if item.completionRequest != nil {
                    if item.selectedCompletion > 0 {
                        item.selectedCompletion -= 1
                    }
                    return .handled
                }
                return .ignored
            }
            .onKeyPress(.leftArrow) {
                item.completionRequest = nil
                return .ignored
            }
            .onKeyPress(.rightArrow) {
                item.completionRequest = nil
                return .ignored
            }
            .onKeyPress(.return) {
                if item.completionRequest != nil {
                    insertCompletion ()
                    return .handled
                }
                return .ignored
            }
            .onKeyPress(.escape) {
                if item.completionRequest != nil {
                    item.completionRequest = nil
                    return .handled
                }
                return .ignored
            }
            .onDrop(of: [.text, .data], delegate: self)
            .language (item.language)
            .lineHeightMultiplier(state.lineHeightMultiplier)
            .showTabs(state.showTabs)
            .showLineNumbers(state.showLines)
            .lineWrappingEnabled(state.lineWrapping)
            .showSpaces(state.showSpaces)
            .characterPairs(codingPairs)
            .highlightLine(item.currentLine)
            .characterPairTrailingComponentDeletionMode(
                state.autoDeleteEmptyPairs ? .immediatelyFollowingLeadingComponent : .disabled)
            .theme(state.codeEditorDefaultTheme)
            .indentStrategy(state.indentStrategy)
            if let req = item.completionRequest, !completionInProgress {
                let (xOffset, yOffset, maxHeight) = calculateOffsetAndHeight(req: req)
                CompletionsDisplayView(
                    prefix: req.prefix,
                    completions: req.completions,
                    selected: Binding<Int> (get: { item.selectedCompletion}, set: { newV in
                        if newV >= req.completions.count {
                            print("Attempting to put a value outside of the range")
                            return
                        }
                        item.selectedCompletion = newV
                    }),
                    onComplete: insertCompletion)
                    .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification), perform: {  _ in
                        if item.completionRequest != nil {
                            self.item.completionRequest = nil
                        }
                    })
                    .background { Color (uiColor: .systemBackground) }
                    .offset(x: xOffset, y: yOffset)
                    .frame(minWidth: 200, maxWidth: 350, maxHeight: maxHeight)
            }
#endif
        }
        .onGeometryChange(for: CGSize.self) { proxy in
            proxy.size
        } action: { newValue in
            codeEditorSize = newValue
        }
    }
    
    func calculateOffsetAndHeight(req: CompletionRequest) -> (offsetX: CGFloat, offsetY: CGFloat, height: CGFloat) {
        let yBelow = req.at.maxY+8
        let yAbove = req.at.minY-10
        // Calculate maximum available height either above or below
        let maxHeight = min(34 * 6.0, max(yAbove, (keyboardOffset - (req.at.maxY + 8))))
        // Calculate xOffset based on current position
        let xOffset = min(codeEditorSize.width - 350, req.at.minX)
        // Calculate yOffset and determine wheater to put completion above or below based on space
        let yOffset = codeEditorSize.height - maxHeight < yBelow ? (yAbove - maxHeight) : yBelow
        
        return (xOffset, yOffset, maxHeight)
    }
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

/// We use this accumultator because we can receive multiple drop files, and each one of those is resolved
/// in the background - when all of those are collected, we can insert the results.
actor Accumulator {
    let range: UITextRange
    let cmd: TextViewCommands

    init (range: UITextRange, cmd: TextViewCommands) {
        result = ""
        count = 0
        self.range = range
        self.cmd = cmd
    }

    func push (_ item: String) {
        if result != "" {
            result += ", "
        }
        result += item
        bump()
    }

    func error () {
        bump()
    }

    func bump () {
        count += 1
        if count == waitingFor {
            flush ()
        }
    }

    func waitFor(_ count: Int) {
        waitingFor = count
        if self.count == waitingFor {
            flush()
        }
    }

    // When we are done, invoke the command
    func flush () {
        let value = result
        DispatchQueue.main.async {
            self.cmd.replace(self.range, withText: value)
        }
    }

    var result: String
    var count: Int
    var waitingFor = Int.max
}

public struct FileNode: Codable, Sendable {
    public let urls: [String]
    public let localIds: [String]

    public init(urls: [String], localIds: [String]) {
        self.urls = urls
        self.localIds = localIds
    }
}

public struct SceneNode: Codable, Sendable {
    public let path: String
    public let localId: String

    public init(path: String, localId: String) {
        self.path = path
        self.localId = localId
    }
}


#if DEBUG
struct DemoCodeEditorView: View {
    @State var text: String = "This is just a sample"

    var body: some View {
        CodeEditorView(state: DemoCodeEditorState(),
                       item: EditedItem(
                        path: "/Users/miguel/cvs/godot-master/modules/gdscript/tests/scripts/utils.notest.gd",
                        content: text,
                        editedItemDelegate: nil),
                       contents: $text)
    }

    func changed(_ editedItem: EditedItem, _ textView: TextView) {
        //
    }
}
#Preview {
    DemoCodeEditorView()
}
#endif
