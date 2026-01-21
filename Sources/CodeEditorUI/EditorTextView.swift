import CoreGraphics
import Foundation

#if canImport(UIKit)
import UIKit
#endif

#if canImport(Runestone)
import Runestone
#endif

#if canImport(Runestone)
public typealias TextLocation = Runestone.TextLocation
#else
/// Text location in a document.
public struct TextLocation {
    public var lineNumber: Int
    public var column: Int
}
#endif

#if canImport(UIKit)
public typealias EditorTextPosition = UITextPosition
public typealias EditorTextRange = UITextRange
#else
public class EditorTextPosition: NSObject {
    public let offset: Int

    public init(offset: Int) {
        self.offset = offset
        super.init()
    }
}

public class EditorTextRange: NSObject {
    public let start: EditorTextPosition
    public let end: EditorTextPosition

    public var isEmpty: Bool {
        start.offset == end.offset
    }

    public init(start: EditorTextPosition, end: EditorTextPosition) {
        self.start = start
        self.end = end
        super.init()
    }
}
#endif

/// Minimal editor surface used by CodeEditorUI to report selection and position.
public protocol EditorTextView: AnyObject {
    var text: String { get set }
    var selectedRange: NSRange { get set }
    var selectedTextRange: EditorTextRange? { get set }
    var contentOffset: CGPoint { get }
    func textLocation(at location: Int) -> TextLocation?
}

#if canImport(Runestone)
extension Runestone.TextView: EditorTextView {}
#endif
