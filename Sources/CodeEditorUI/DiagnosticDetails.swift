//
//  File.swift
//
//
//  Created by Miguel de Icaza on 4/9/24.
//

import Foundation
import SwiftUI

struct ShowIssue: View {
    let issue: Issue

    var body: some View {
        HStack (alignment: .firstTextBaseline){
            Image (systemName: issue.kind == .error ? "xmark.circle.fill" : "exclamationmark.triangle.fill")
                .foregroundStyle(issue.kind == .error ? Color.red : Color.orange)
            Text ("\(issue.line):\(issue.col) ")
                .foregroundStyle(.secondary)
                .fontDesign(.monospaced)
            + Text ("\(issue.message)")
        }
        .font(.footnote)
    }
}
struct DiagnosticDetailsView: View {
    let errors: [Issue]?
    let warnings: [Issue]?
    let item: EditedItem
    let maxFirstLine: CGFloat

    struct DiagnosticView: View {
        let src: [Issue]
        let item: EditedItem
        let maxFirstLine: CGFloat
        
        var body: some View {
            ForEach (Array (src.enumerated()), id: \.offset) { idx, v in
                ShowIssue (issue: v)
                    .onTapGesture {
                        item.commands.requestGoto(line: v.line-1)
                    }
                    .frame(maxWidth: idx == 0 ? maxFirstLine : .infinity, alignment: .leading)
                .listRowSeparator(.hidden)
            }
        }
    }

    var body: some View {
        List {
            if let errors {
                DiagnosticView(src: errors, item: item, maxFirstLine: maxFirstLine)
            }
            if let warnings {
                DiagnosticView(src: warnings, item: item, maxFirstLine: maxFirstLine)
            }
        }
        .listStyle(.plain)
    }
}

#Preview {
    DiagnosticDetailsView(
        errors: [Issue(kind: .error, col: 1, line: 1, message: "My Error, but this is a very long line explaining what went wrong and hy you should not always have text this long that does not have a nice icon aligned")],
        warnings: [Issue(kind: .warning, col: 1, line: 1, message: "My Warning")], item: EditedItem(path: "/tmp/", content: "demo", editedItemDelegate: nil), maxFirstLine: .infinity)
}
