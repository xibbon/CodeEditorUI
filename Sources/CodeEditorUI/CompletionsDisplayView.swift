//
//  SwiftUIView.swift
//
//
//  Created by Miguel de Icaza on 4/3/24.
//

import SwiftUI

public struct CompletionsDisplayView: View {
    @Environment(\.colorScheme) var colorScheme
    let prefix: String
    var completions: [CompletionEntry]
    @Binding var selected: Int
    var onComplete: () -> ()
    @State var tappedTime: Date? = nil

    func getDefaultAcceptButton (_ color: Color) -> some View {
        Image (systemName: "return")
            .padding(5)
            .background { color }
            .foregroundStyle(Color.secondary)
            .clipShape(RoundedRectangle(cornerRadius: 4))
    }

    let palette: [Color] = [
        Color (#colorLiteral(red: 1, green: 0.5204778927, blue: 0.2, alpha: 1)),
        Color (#colorLiteral(red: 1, green: 0.7472373315, blue: 0.2049082724, alpha: 1)),
        Color (#colorLiteral(red: 0.6337333333, green: 0.194, blue: 0.97, alpha: 1)),
        Color (#colorLiteral(red: 0.18, green: 0.4399056839, blue: 0.9, alpha: 1)),
        Color (#colorLiteral(red: 0.3110562249, green: 0.178, blue: 0.89, alpha: 1)),
        Color (#colorLiteral(red: 0.6041037997, green: 0.93, blue: 0.186, alpha: 1)),
        Color (#colorLiteral(red: 0.164, green: 0.82, blue: 0.6884707017, alpha: 1)),
        Color (#colorLiteral(red: 0.194, green: 0.7673004619, blue: 0.97, alpha: 1)),
        Color (#colorLiteral(red: 1, green: 0.2, blue: 0.6410113414, alpha: 1)),
        Color (#colorLiteral(red: 0.3411764801, green: 0.6235294342, blue: 0.1686274558, alpha: 1)),
        ]

    func kindToImage (kind: CompletionEntry.CompletionKind) -> some View {
        let image: String
        let color: Color

        switch kind {
        case .class:
            image = "c.square.fill"
            color = palette[0]
        case .function:
            image = "f.square.fill"
            color = palette[1]
        case .constant:
            image = "c.square.fill"
            color = palette[2]
        case .enum:
            image = "e.square.fill"
            color = palette[3]
        case .filePath:
            image = "folder.circle.fill"
            color = palette[4]
        case .member:
            image = "m.square.fill"
            color = palette[5]
        case .nodePath:
            image = "n.square.fill"
            color = palette[6]
        case .plainText:
            image = "t.square.fill"
            color = palette[7]
        case .signal:
            image = "s.square.fill"
            color = palette[8]
        case .variable:
            image = "v.square.fill"
            color = palette[9]
        }
        return Image (systemName: image)
            .resizable()
            .scaledToFit()
            .padding(1)
            .foregroundStyle(Color.white, color)
            .fontWeight(.regular)
            .frame(height: 20)
            //.frame(width: 20, height: 40)
    }

    /// Makes bold text for the text that we were matching against
    func boldify (_ source: String, _ hayStack: String) -> Text {
        var ra = AttributedString()
        let sourceLower = source.lowercased()
        var scan = sourceLower [sourceLower.startIndex...]
#if os(macOS)
        let plain = NSColor.labelColor
        let bolded = NSColor.labelColor.withAlphaComponent(0.6)
#else
        let plain = UIColor.label
        let bolded = UIColor.label.withAlphaComponent(0.6)
#endif
        for hs in hayStack {
            let match = hs.lowercased().first ?? hs

            var ch = AttributedString ("\(hs)")
            if scan.count > 0, let p = scan.firstIndex(of: match) {
                ch.foregroundColor = plain
                scan = scan [scan.index(after: p)...]
            } else {
                ch.foregroundColor = bolded
            }
            ra.append (ch)
        }
        return Text (ra)
    }

    func item (prefix: String, _ v: CompletionEntry) -> some View {
        HStack (spacing: 0){
            boldify (prefix, v.display)
            Spacer()
        }
        .padding (3)
        .padding ([.horizontal], 3)
    }

    public var body: some View {
        // 54 59 70
        let highlight = colorScheme == .dark ? Color(red: 0.21, green: 0.23, blue: 0.275) : Color(red: 0.8, green: 0.87, blue: 0.96)

        ScrollView(.vertical){
            ScrollViewReader { proxy in
                LazyVGrid(columns: [
                    GridItem(.flexible(), alignment: .leading),
                    GridItem(.fixed(30), spacing: 3)]){
                        ForEach (Array(completions.enumerated()), id: \.offset) { idx, entry in
                            HStack {
                                kindToImage(kind: entry.kind)
                                item (prefix: prefix, entry)
                            }
                            .frame(minHeight: 29)
                            .tag(idx)
                            .padding([.leading], 7)
                            .background {
                                if idx == selected {
                                    highlight
                                }
                            }
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                            .onChange(of: selected) { oldV, newV in
                                proxy.scrollTo(newV)
                            }
                            .onTapGesture {
                                if idx == selected, tappedTime?.timeIntervalSinceNow ?? 0 > -0.25 {
                                    onComplete()
                                    return
                                }
                                selected = idx
                                tappedTime = Date()
                            }
                            if idx == selected {
                                getDefaultAcceptButton(highlight)
                                    .onTapGesture { onComplete () }
                            } else {
                                Text(verbatim: "")
                            }
                        }
                    }
            }
        }
        .padding(4)
        .fontDesign(.monospaced)
        .font(.footnote)
#if os(macOS)
        .background { Color (.lightGray) }
        .clipShape (RoundedRectangle(cornerRadius: 6, style: .circular))
        .shadow(color: Color (.gray), radius: 3, x: 3, y: 3)
        .overlay {
            RoundedRectangle(cornerRadius: 6, style: .circular)
                .stroke(Color (.darkGray), lineWidth: 1) // Add a border
        }
#else
        .background { Color (uiColor: .systemGray6) }
        .clipShape (RoundedRectangle(cornerRadius: 6, style: .circular))
        .shadow(color: Color (uiColor: .systemGray5), radius: 3, x: 3, y: 3)
        .overlay {
            RoundedRectangle(cornerRadius: 6, style: .circular)
                .stroke(Color (uiColor: .systemGray3), lineWidth: 1) // Add a border

        }
#endif
    }
}

#if DEBUG
struct DemoCompletionsDisplayView: View {
    @State var completions: [CompletionEntry] = DemoCompletionsDisplayView.makeTestData ()
    @State var selected = 0

    static func makeTestData () -> [CompletionEntry] {
        return [
            CompletionEntry(kind: .class, display: "print", insert: "print("),
            CompletionEntry(kind: .function, display: "print_error", insert: "print_error("),
            CompletionEntry(kind: .function, display: "print_another", insert: "print_another("),
            CompletionEntry(kind: .class, display: "Poraint", insert: "Poraint"),
            CompletionEntry(kind: .variable, display: "apriornster", insert: "apriornster"),
            CompletionEntry(kind: .signal, display: "Kind: signal", insert: "print"),
            CompletionEntry(kind: .variable, display: "Kind: variable", insert: "print"),
            CompletionEntry(kind: .member, display: "Kind: member", insert: "print"),
            CompletionEntry(kind: .`enum`, display: ".`enuKind: `", insert: "print"),
            CompletionEntry(kind: .constant, display: "Kind: constant", insert: "print"),
            CompletionEntry(kind: .nodePath, display: "Kind: nodePath", insert: "print"),
            CompletionEntry(kind: .filePath, display: "Kind: filePath", insert: "print"),
            CompletionEntry(kind: .plainText, display: "Kind: plainText", insert: "print")

        ]
    }
    var body: some View {
        HStack {
            VStack {
                CompletionsDisplayView(prefix: "print", completions: completions, selected: $selected, onComplete: { print ("Completing!") })
                Spacer ()
            }
            Spacer ()
        }
        .padding()
    }
}

#Preview {
    DemoCompletionsDisplayView()
}
#endif
