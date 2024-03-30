import SwiftUI
import Runestone
import TreeSitter
import RunestoneUI

/// Represents an edited item
public class EditedItem: Identifiable, Hashable, Equatable {
    public static func == (lhs: EditedItem, rhs: EditedItem) -> Bool {
        lhs.path == rhs.path && lhs.data === rhs.data
        
    }
    
    public func hash(into hasher: inout Hasher) {
        path.hash(into: &hasher)
    }
    
    public var id: String { path }
    
    /// The path of the file that we are editing
    public var path: String
    public var data: AnyObject?
    
    public init (path: String, data: AnyObject?) {
        self.path = path
        self.data = data
    }
}

/// This is the host for all of the coding needs that we have
public struct CodeEditorShell: View {
    @Binding var openFiles: [EditedItem]
    @State var selected = 0
    
    public init (openFiles: Binding<[EditedItem]>) {
        self._openFiles = openFiles
    }
    
    public var body: some View {
        Picker(selection: $selected) {
            ForEach (Array (openFiles.enumerated()), id: \.offset) { idx, item in
                Text (item.path)
                    .tag(idx)
            }
        } label: {
            Text ("foo")
        }
        .pickerStyle(.segmented)
        CodeEditorView(item: openFiles [selected])
    }
}

#Preview {
    CodeEditorShell (openFiles: .constant([EditedItem(path: "/Users/miguel/cvs/godot-master/modules/gdscript/tests/scripts/utils.notest.gd", data: nil)]))
}
