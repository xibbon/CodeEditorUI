import SwiftUI
import Runestone
import TreeSitter
import RunestoneUI

/// Represents an edited item in the code editor, it uses a path to reference it, and expect that it
/// can be loaded and saved via the HostServices variable.
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
    
    /// User-defined paylog for additional data
    public var data: AnyObject?
    
    /// - Parameters:
    ///  - path: the path that will be passed to the HostServices API to load and save the file
    ///  - data: this is data that can be attached to this object and extracted a later point by the user
    public init (path: String, data: AnyObject?) {
        self.path = path
        self.data = data
    }
}

/// This is the host for all of the coding needs that we have
public struct CodeEditorShell: View {
    @Binding var openFiles: [EditedItem]
    @State var selected = 0
    @State var TODO: String = ""
    
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
        CodeEditorView(item: openFiles [selected], contents: $TODO)
    }
}

#Preview {
    CodeEditorShell (openFiles: .constant([EditedItem(path: "/Users/miguel/cvs/godot-master/modules/gdscript/tests/scripts/utils.notest.gd", data: nil)]))
}
