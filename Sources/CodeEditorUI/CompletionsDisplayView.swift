//
//  SwiftUIView.swift
//  
//
//  Created by Miguel de Icaza on 4/3/24.
//

import SwiftUI

public struct CompletionsDisplayView: View {
    @Binding var completions: [CompletionEntry]
    @Binding var selected = 0
    
    func getDefaultAcceptButton () -> some View {
        Image (systemName: "return")
            .padding(5)
            .background { Color.accentColor }
            .foregroundStyle(.background)
            .clipShape(RoundedRectangle(cornerRadius: 4))
    }
    
    func kindToIcon (kind: CompletionEntry.CompletionKind) {
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
    
    func item (_ v: CompletionEntry) -> some View {
        HStack (spacing: 0){
            Image (systemName: "function")
                .padding (4)
                .background { Color.cyan.brightness(0.2) }
                .padding ([.trailing], 5)
            Text ("get") + Text (v.display).foregroundStyle(.secondary)
        }
        .padding (3)
        .padding ([.horizontal], 3)
    }

    var body: some View {
        VStack (alignment: .leading){
            Grid (alignment: .leading) {
                ForEach (Array(completions.enumerated()), id: \.offset) { idx, entry in
                    GridRow {
                        item (entry)
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

#Preview {
    SwiftUIView()
}
