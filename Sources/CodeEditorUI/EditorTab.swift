//
//  EditorTab.swift: Displays some editor tabs on top of the buffers
//
//
//  Created by Miguel de Icaza on 4/1/24.
//

import Foundation
import SwiftUI

struct EditorTab2: View {
    @Binding var item: HostedItem
    @ScaledMetric var internalPadding = 4
    let selected: Bool
    let close: () -> ()
    let select: () -> ()
    var body: some View {
        HStack (spacing: 4) {
            Button (action: { close () }) {
                Image (systemName: (item as? EditedItem)?.dirty ?? false ? "circle.fill" : "xmark")
                    .fontWeight(.light)
                    .foregroundStyle(selected ? Color.accentColor : Color.secondary)
                    .font(.caption)
            }
            Text (item.title)
                .foregroundStyle(selected ? Color.accentColor : Color.primary)
                .onTapGesture {
                        self.select ()
                }

        }
        .padding(internalPadding)
        .padding ([.trailing], internalPadding)
        .background {
            selected ? Color.accentColor.opacity(0.3) : Color (uiColor: .secondarySystemBackground)
        }
        .clipShape(UnevenRoundedRectangle(topLeadingRadius: 5, bottomLeadingRadius: 0, bottomTrailingRadius: 0, topTrailingRadius: 5, style: .continuous))
        .padding([.horizontal], 3)
    }
}

struct EditorTab: View {
    @Binding var item: HostedItem
    @ScaledMetric var internalPadding = 10
    @ScaledMetric var modifiedImageSize = 10
    let selected: Bool
    let close: () -> ()
    let select: () -> ()
    var body: some View {
        HStack (spacing: 2) {
            if selected {
                Button (action: { close () }) {
                    Image (systemName: "xmark.app.fill")
                        .foregroundStyle(selected ? Color.accentColor : Color.secondary.opacity(0.8))
                        .font(.caption)
                }
            }
            ZStack {
                // The first versio is the wider, and is hidden using the same color
                // as the background
                Text (item.title)
                    .fontWeight(.semibold)
                    .foregroundStyle(.background)

                // The one that we dispaly
                Text (item.title)
                    .fontWeight(selected ? .semibold : .regular)
                    .foregroundStyle(selected ? Color.accentColor : Color.secondary)
            }
            .font(.caption)
            .padding(.horizontal, 4)
            .onTapGesture {
                self.select ()
            }
            if (item as? EditedItem)?.dirty ?? false {
                Image (systemName: "circle.fill")
                    .fontWeight(.light)
                    .foregroundStyle(selected ? Color.accentColor : Color.secondary.opacity(0.8))
                    .font(.system(size: modifiedImageSize))
            }
        }
        .padding(internalPadding)
        .padding(.horizontal, 1)
        .background {
            selected ? Color.accentColor.opacity(0.2) : Color (uiColor: .systemGray5)
        }
        .clipShape(UnevenRoundedRectangle(topLeadingRadius: 10, bottomLeadingRadius: 10, bottomTrailingRadius: 10, topTrailingRadius: 10, style: .continuous))
    }
}
struct EditorTabs: View {
    @Binding var selected: Int?
    @Binding var items: [HostedItem]
    let closeRequest: (Int) -> ()
    @ScaledMetric var dividerSize = 12
    @ScaledMetric var tabSpacing: CGFloat = 10

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: tabSpacing) {
                if let selected {
                    ForEach(Array(items.enumerated()), id: \.offset) { idx, item in
                        EditorTab(item: $items [idx], selected: idx == selected, close: { closeRequest (idx) }, select: { self.selected = idx } )

                    }
                }
            }
        }
        .scrollIndicators(.hidden)
    }
}

struct DemoEditorTabs: View {
    @State var selected: Int? = 2
    @State var items: [HostedItem] = [
        EditedItem (path: "some/file/foo.txt", content: "Demo", editedItemDelegate: nil),
        EditedItem (path: "res://another.txt", content: "Demo", editedItemDelegate: nil),
        EditedItem (path: "res://third.txt", content: "Demo", editedItemDelegate: nil),
        EditedItem (path: "some/file/foo.txt", content: "Demo", editedItemDelegate: nil),
        EditedItem (path: "res://another.txt", content: "Demo", editedItemDelegate: nil),
        EditedItem (path: "res://third.txt", content: "Demo", editedItemDelegate: nil),
        EditedItem (path: "some/file/foo.txt", content: "Demo", editedItemDelegate: nil),
        EditedItem (path: "res://another.txt", content: "Demo", editedItemDelegate: nil),
        EditedItem (path: "res://third.txt", content: "Demo", editedItemDelegate: nil),
        EditedItem (path: "some/file/foo.txt", content: "Demo", editedItemDelegate: nil),
        EditedItem (path: "res://another.txt", content: "Demo", editedItemDelegate: nil),
        EditedItem (path: "res://third.txt", content: "Demo", editedItemDelegate: nil),
        EditedItem (path: "some/file/foo.txt", content: "Demo", editedItemDelegate: nil),
        EditedItem (path: "res://another.txt", content: "Demo", editedItemDelegate: nil),
        EditedItem (path: "res://third.txt", content: "Demo", editedItemDelegate: nil),
        EditedItem (path: "some/file/foo.txt", content: "Demo", editedItemDelegate: nil),
        EditedItem (path: "res://another.txt", content: "Demo", editedItemDelegate: nil),
        EditedItem (path: "res://third.txt", content: "Demo", editedItemDelegate: nil),
    ]

    var body: some View {
        EditorTabs(selected: $selected, items: $items) { closeIdx in
            items.remove(at: closeIdx)
            if closeIdx == selected {
                selected = max (0, (selected ?? 0)-1)
            }
        }.onAppear {
            if let it = items [1] as? EditedItem  {
                it.dirty = true
            }
        }
    }
}

#Preview {
    ZStack {
        Color (uiColor: .secondarySystemBackground)

        DemoEditorTabs()
    }
}
