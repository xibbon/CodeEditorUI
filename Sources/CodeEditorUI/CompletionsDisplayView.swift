//
//  SwiftUIView.swift
//  
//
//  Created by Miguel de Icaza on 4/3/24.
//

import SwiftUI

public struct CompletionsDisplayView: View {
    let prefix: String
    @Binding var completions: [CompletionEntry]
    @Binding var selected: Int
    
    func getDefaultAcceptButton () -> some View {
        Image (systemName: "return")
            .padding(5)
            .background { Color.accentColor }
            .foregroundStyle(.background)
            .clipShape(RoundedRectangle(cornerRadius: 4))
    }
    
    func kindToIcon (kind: CompletionEntry.CompletionKind) -> String {
        switch kind {
        case .class:
            return "cube"
        case .function:
            return "function"
        case .constant:
            return "c.square"
        case .enum:
            return "e.square"
        case .filePath:
            return "folder"
        case .member:
            return "m.square"
        case .nodePath:
            return "point.3.connected.trianglepath.dotted"
        case .plainText:
            return "text.justify.left"
        case .signal:
            return "app.connected.to.app.below.fill"
        case .variable:
            return "shippingbox"
        }
    }
    
    /// Makes bold text for the text that we were matching against
    func boldify (_ source: String, _ hayStack: String) -> LocalizedStringKey {
        var result = ""
        let sourceLower = source.lowercased()
        var scan = sourceLower [sourceLower.startIndex...]
        for hs in hayStack {
            let match = hs.lowercased().first ?? hs
            if let p = scan.firstIndex(of: match) {
                result += "[\(hs)]"
                scan = scan [p...]
            } else {
                result += "\(hs)"
            }
        }
        return LocalizedStringKey(stringLiteral: result)
    }

    /// Makes bold text for the text that we were matching against
    func boldify2 (_ source: String, _ hayStack: String) -> Text {
        var result = ""
        var ra = AttributedString()
        let sourceLower = source.lowercased()
        var scan = sourceLower [sourceLower.startIndex...]
        for hs in hayStack {
            let match = hs.lowercased().first ?? hs
            
            var ch = AttributedString ("\(hs)")
            if scan.count > 0, let p = scan.firstIndex(of: match) {
                ch.foregroundColor = .primary
                scan = scan [scan.index(after: p)...]
            } else {
                ch.foregroundColor = .secondary
            }
            ra.append (ch)
        }
        return Text (ra)
    }
    
    func item (prefix: String, _ v: CompletionEntry) -> some View {
        HStack (spacing: 0){
            Image (systemName: kindToIcon (kind: v.kind))
                .padding (4)
                .background { Color.cyan.brightness(0.2) }
                .padding ([.trailing], 5)
            #if false
            Text (boldify (prefix, v.display)).foregroundStyle(.secondary)
            #else
            boldify2 (prefix, v.display)
            #endif
        }
        .padding (3)
        .padding ([.horizontal], 3)
    }

    public var body: some View {
        VStack (alignment: .leading){
            Grid (alignment: .leading) {
                ForEach (Array(completions.enumerated()), id: \.offset) { idx, entry in
                    GridRow {
                        item (prefix: prefix, entry)
                            .background {
                                if idx == selected {
                                    Color.blue.opacity(0.3)
                                }
                            }
                            .clipShape(RoundedRectangle(cornerRadius: 4))

                        if idx == selected {
                            getDefaultAcceptButton()
                        } else {
                            EmptyView()
                        }
                    }

                }
            }
        }
        .padding(8) // Add padding inside the capsule
        .fontDesign(.monospaced)
        .font(.footnote)
        .clipShape (RoundedRectangle(cornerRadius: 6, style: .circular))
        .overlay {
            RoundedRectangle(cornerRadius: 6, style: .circular)
                .stroke(Color.gray, lineWidth: 1) // Add a border

                //.shadow(color: Color.gray, radius: 3, x: 3, y: 3)
        }
    }
}

#if DEBUG
struct DemoCompletionsDisplayView: View {
    @State var completions: [CompletionEntry] = DemoCompletionsDisplayView.makeTestData ()
    @State var selected = 0
    
    static func makeTestData () -> [CompletionEntry] {
        return [
            CompletionEntry(kind: .function, display: "print", insert: "print("),
            CompletionEntry(kind: .function, display: "print_error", insert: "print_error("),
            CompletionEntry(kind: .function, display: "print_another", insert: "print_another("),
            CompletionEntry(kind: .class, display: "Poraint", insert: "Poraint"),
            CompletionEntry(kind: .variable, display: "apriornster", insert: "apriornster"),
            CompletionEntry(kind: .signal, display: "paraceleuinephedert", insert: "$paraceleuinephedert")
        ]
    }
    var body: some View {
        CompletionsDisplayView(prefix: "print", completions: $completions, selected: $selected)
    }
}

#Preview {
    DemoCompletionsDisplayView()
}
#endif
