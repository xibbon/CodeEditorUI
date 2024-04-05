//
//  SwiftUIView.swift
//  
//
//  Created by Miguel de Icaza on 4/3/24.
//

import SwiftUI

public struct CompletionsDisplayView: View {
    let prefix: String
    var completions: [CompletionEntry]
    @State var selected = 0
    
    func getDefaultAcceptButton () -> some View {
        Image (systemName: "return")
            .padding(5)
            .background { Color.accentColor }
            .foregroundStyle(.background)
            .clipShape(RoundedRectangle(cornerRadius: 4))
    }
    
    let palette: [Color] = [
        Color (#colorLiteral(red: 1, green: 0.7014271617, blue: 0.5018826723, alpha: 1)),
        Color (#colorLiteral(red: 1, green: 0.8414883018, blue: 0.5013846755, alpha: 1)),
        Color (#colorLiteral(red: 0.8560311794, green: 0.7036848664, blue: 0.9709442258, alpha: 1)),
        Color (#colorLiteral(red: 0.5355303288, green: 0.6661332846, blue: 0.8973312974, alpha: 1)),
        Color (#colorLiteral(red: 0.6944738626, green: 0.6490275264, blue: 0.8922163844, alpha: 1)),
        Color (#colorLiteral(red: 0.7470750213, green: 0.9311752915, blue: 0.5108862519, alpha: 1)),
        Color (#colorLiteral(red: 0.5022051334, green: 0.8237985969, blue: 0.759318471, alpha: 1)),
        Color (#colorLiteral(red: 0.5644295812, green: 0.866447866, blue: 0.973231256, alpha: 1)),
        Color (#colorLiteral(red: 0.9982370734, green: 0.721807301, blue: 0.8741931319, alpha: 1)),
        Color (#colorLiteral(red: 0.8962232471, green: 0.5777660608, blue: 0.7532460093, alpha: 1)),
        ]

    func kindToImage (kind: CompletionEntry.CompletionKind) -> some View {
        let image: String
        let color: Color
        
        switch kind {
        case .class:
            image = "cube"
            color = palette[0]
        case .function:
            image = "function"
            color = palette[1]
        case .constant:
            image = "c.square"
            color = palette[2]
        case .enum:
            image = "e.square"
            color = palette[3]
        case .filePath:
            image = "folder"
            color = palette[4]
        case .member:
            image = "m.square"
            color = palette[5]
        case .nodePath:
            image = "point.3.connected.trianglepath.dotted"
            color = palette[6]
        case .plainText:
            image = "text.justify.left"
            color = palette[7]
        case .signal:
            image = "app.connected.to.app.below.fill"
            color = palette[8]
        case .variable:
            image = "shippingbox"
            color = palette[9]
        }
        return Image (systemName: image)
            .resizable()
            .scaledToFit()
            .padding (4)
            .background { color }
            .padding ([.trailing], 5)
            .fontWeight(.light)
    }
    
    /// Makes bold text for the text that we were matching against
    func boldify (_ source: String, _ hayStack: String) -> Text {
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
            boldify (prefix, v.display)
        }
        .padding (3)
        .padding ([.horizontal], 3)
    }

    public var body: some View {
        ScrollView(.vertical){
            Grid (alignment: .leading, verticalSpacing: 4) {
                ForEach (Array(completions.enumerated()), id: \.offset) { idx, entry in
                    GridRow (alignment: .firstTextBaseline) {
                        kindToImage(kind: entry.kind)
                        
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
                    .frame(height: UIFont.preferredFont(forTextStyle: .body).capHeight*2)
                }
            }
        }
        .frame(minWidth: 200, maxWidth: 300, maxHeight: 34*6)
        .padding([.leading], 4)
        .fontDesign(.monospaced)
        .font(.footnote)
        .clipShape (RoundedRectangle(cornerRadius: 6, style: .circular))
        .overlay {
            RoundedRectangle(cornerRadius: 6, style: .circular)
                .stroke(Color (uiColor: .systemGroupedBackground), lineWidth: 1) // Add a border

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
        CompletionsDisplayView(prefix: "print", completions: completions)
    }
}

#Preview {
    DemoCompletionsDisplayView()
}
#endif
