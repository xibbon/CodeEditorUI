//
//  GotoLineView.swift
//  CodeEditorUI
//
//  Created by Miguel de Icaza on 5/17/25.
//

import SwiftUI

struct GotoLineView: View {
    @Binding var showing: Bool
    @Environment(\.colorScheme) var colorScheme
    @FocusState var inputFocused: Bool
    @State var line: String = ""
    @State var canGo: Int? = 1
    //let maxLines: Int
    let callback: (Int) -> ()
    
    var textInputBox: some View {
        VStack(alignment: .leading) {
            HStack(alignment: .firstTextBaseline) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField(String(localized: .lineNumber), text: $line)
                    .onSubmit {
                        showing = false
                        if let canGo {
                            callback(canGo)
                        }
                    }
                    .onAppear {
                        inputFocused = true
                    }
                    .focused($inputFocused, equals: true)
                Button(action: {
                    line = ""
                }) {
                    Image (systemName: "xmark.circle.fill")
                }
                .font(.body)
                .foregroundStyle(.secondary)
                .opacity(line == "" ? 0 : 1)
            }
            .padding(.vertical, 3)
            .font(.title3)
            if let canGo {
                Text(.lineNumber(canGo))
                    .font(.subheadline)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(4)
                    .background(RoundedRectangle(cornerRadius: 4).fill(Color.accentColor))
                    .foregroundStyle(.white)
            }
        }
        .padding()
#if os(macOS)
        .background(RoundedRectangle(cornerRadius: 10).fill(
            //Color(uiColor: .systemGray6)
            .ultraThickMaterial
        )
            .stroke(Color(.gray)))
#else
            .background(RoundedRectangle(cornerRadius: 10).fill(
                //Color(uiColor: .systemGray6)
                .ultraThickMaterial
            )
        .stroke(Color(uiColor: .systemGray4)))
#endif
        .shadow(color: colorScheme == .dark ? .clear : Color.gray, radius: 40, x: 10, y: 30)
        .onChange(of: line) { old, new in
            if let line = Int(new), line > 0 { // }, line < maxLines {
                canGo = line
            } else {
                canGo = nil
            }
        }
        .frame(minWidth: 300, maxWidth: 400)
    }
    
    var body: some View {
        ZStack(alignment: .top) {
            Color.black.opacity(0.001)
                .onTapGesture {
                    showing = false
                }
            textInputBox
                .offset(y: 40)
        }
        .onKeyPress(.escape) {
            showing = false
            return .handled
        }
    }
}

#if DEBUG
struct ContentView: View {
    @Binding var show: Bool
    
    var body: some View {
        ZStack {
            VStack {
                Image(systemName: "globe")
                    .imageScale(.large)
                    .foregroundStyle(.tint)
                Text(verbatim: "Hello, world!")
            }
            .padding()
            if show {
                GotoLineView(showing: $show) { line in
                    print("Use picked line \(line)")
                }
            }
        }
    }
}

#Preview {
    @Previewable @State var show = true
    ContentView(show: $show)
}
#endif
