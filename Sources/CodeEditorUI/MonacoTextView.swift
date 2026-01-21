import CoreGraphics
import Foundation
import WebKit

#if canImport(UIKit)
import UIKit
#endif

#if canImport(UIKit)
public final class MonacoTextPosition: UITextPosition {
    public let offset: Int

    public init(offset: Int) {
        self.offset = offset
        super.init()
    }
}

public final class MonacoTextRange: UITextRange {
    public let startPosition: MonacoTextPosition
    public let endPosition: MonacoTextPosition

    public override var start: UITextPosition {
        startPosition
    }

    public override var end: UITextPosition {
        endPosition
    }

    public override var isEmpty: Bool {
        startPosition.offset == endPosition.offset
    }

    public init(start: MonacoTextPosition, end: MonacoTextPosition) {
        self.startPosition = start
        self.endPosition = end
        super.init()
    }

    public convenience init(range: NSRange) {
        let start = MonacoTextPosition(offset: range.location)
        let end = MonacoTextPosition(offset: range.location + range.length)
        self.init(start: start, end: end)
    }
}
#else
public final class MonacoTextPosition: EditorTextPosition {
    public override init(offset: Int) {
        super.init(offset: offset)
    }
}

public final class MonacoTextRange: EditorTextRange {
    public convenience init(range: NSRange) {
        let start = MonacoTextPosition(offset: range.location)
        let end = MonacoTextPosition(offset: range.location + range.length)
        self.init(start: start, end: end)
    }
}
#endif

public final class MonacoTextView: NSObject, EditorTextView {
    public weak var webView: WKWebView?

    public var text: String {
        didSet {
            if text != oldValue {
                clampSelection()
            }
        }
    }

    public var selectedRange: NSRange {
        didSet {
            selectedTextRange = MonacoTextRange(range: selectedRange)
        }
    }

    public var selectedTextRange: EditorTextRange?

    public var contentOffset: CGPoint {
        .zero
    }

    public var isFirstResponder: Bool {
#if os(macOS)
        guard let webView else { return false }
        return webView.window?.firstResponder === webView
#else
        return webView?.isFirstResponder ?? false
#endif
    }

    public init(webView: WKWebView?, text: String) {
        self.webView = webView
        self.text = text
        self.selectedRange = NSRange(location: 0, length: 0)
        self.selectedTextRange = MonacoTextRange(range: self.selectedRange)
        super.init()
    }

    public func becomeFirstResponder() {
        _ = webView?.becomeFirstResponder()
    }

    public func textLocation(at location: Int) -> TextLocation? {
        let nsText = text as NSString
        let clamped = max(0, min(location, nsText.length))
        var line = 0
        var lineStart = 0
        var searchRange = NSRange(location: 0, length: clamped)

        while true {
            let found = nsText.range(of: "\n", options: [], range: searchRange)
            if found.location == NSNotFound {
                break
            }
            line += 1
            let nextStart = found.location + 1
            lineStart = nextStart
            searchRange = NSRange(location: nextStart, length: max(0, clamped - nextStart))
        }
        return TextLocation(lineNumber: line, column: clamped - lineStart)
    }

    public func updateSelection(start: Int, end: Int) {
        let lower = min(start, end)
        let upper = max(start, end)
        selectedRange = NSRange(location: lower, length: max(0, upper - lower))
    }

    private func clampSelection() {
        let length = (text as NSString).length
        let clampedLocation = min(max(0, selectedRange.location), length)
        let clampedLength = min(max(0, selectedRange.length), max(0, length - clampedLocation))
        if clampedLocation != selectedRange.location || clampedLength != selectedRange.length {
            selectedRange = NSRange(location: clampedLocation, length: clampedLength)
        }
    }
}
