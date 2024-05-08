//
//  EditorTab.swift: Displays some editor tabs on top of the buffers
//  
//
//  Created by Miguel de Icaza on 4/1/24.
//

import Foundation
import SwiftUI


struct EditorTab: View {
    @Binding var item: EditedItem
    @ScaledMetric var internalPadding = 4
    let selected: Bool
    let close: () -> ()
    let select: () -> ()
    var body: some View {
        HStack (spacing: 4) {
            Button (action: { close () }) {
                Image (systemName: "xmark")
                    .fontWeight(.light)
                    .foregroundStyle(selected ? Color.accentColor : Color.secondary)
                    .font(.footnote)
            }
            Text (item.filename)
                .foregroundStyle(selected ? Color.accentColor : Color.primary)
                .onTapGesture {
                        self.select ()
                }
                .font(.subheadline)

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

struct EditorTabs: View {
    @Binding var selected: Int?
    @Binding var items: [EditedItem]
    let closeRequest: (Int) -> ()
    @ScaledMetric var dividerSize = 12
    
    var body: some View {
        ScrollView (.horizontal){
            HStack (spacing: 0){
                if let selected {
                    ForEach (Array (items.enumerated()), id: \.offset) { idx, item in
                        EditorTab(item: $items [idx], selected: idx == selected, close: { closeRequest (idx) }, select: { self.selected = idx } )
                        if idx+1 < selected || idx > selected {
                            if idx+1 < items.count {
                                Divider()
                                    .frame(maxHeight: dividerSize)
                            }
                        }
                    }
                }
            }
        }
    }
}


struct DemoEditorTabs: View {
    @State var selected: Int? = 2
    @State var items: [EditedItem] = [
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
        }
    }
}

#Preview {
    ZStack {
        Color (uiColor: .systemBackground)
        
        DemoEditorTabs()
    }
}
