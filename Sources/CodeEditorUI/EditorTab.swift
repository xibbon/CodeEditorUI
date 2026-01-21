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
#if os(macOS)
            selected ? Color.accentColor.opacity(0.3) : Color (nsColor: .controlBackgroundColor)
#else
            selected ? Color.accentColor.opacity(0.3) : Color (uiColor: .secondarySystemBackground)
#endif
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
                .buttonStyle(.plain)
            }
            ZStack {
                Text (item.title)
                    .fontWeight(.semibold)
                    .foregroundStyle(.background)
                    .opacity(0.001)

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
            #if os(macOS)
            selected ? Color.accentColor.opacity(0.2) : Color (.lightGray)
            #else
            selected ? Color.accentColor.opacity(0.2) : Color (uiColor: .systemGray5)
            #endif
        }
        .clipShape(UnevenRoundedRectangle(topLeadingRadius: 10, bottomLeadingRadius: 10, bottomTrailingRadius: 10, topTrailingRadius: 10, style: .continuous))
    }
}

// MARK: - Custom Gesture Support

#if os(iOS)
import UIKit

class LongPressDragGestureRecognizer: UILongPressGestureRecognizer {
    var onLongPressBegin: (() -> Void)?
    var onDragChanged: ((CGPoint) -> Void)?
    var onDragEnded: (() -> Void)?

    private var longPressActivated = false
    private var initialLocation: CGPoint = .zero

    func handleGesture() {
        switch state {
        case .began:
            initialLocation = location(in: view)
            longPressActivated = true
            onLongPressBegin?()

        case .changed:
            if longPressActivated {
                let currentLocation = location(in: view)
                let translation = CGPoint(
                    x: currentLocation.x - initialLocation.x,
                    y: currentLocation.y - initialLocation.y
                )
                onDragChanged?(translation)
            }

        case .ended, .cancelled, .failed:
            if longPressActivated {
                onDragEnded?()
            }
            longPressActivated = false

        default:
            break
        }
    }
}

struct LongPressDragGesture: UIGestureRecognizerRepresentable {
    var onLongPressBegin: () -> Void
    var onDragChanged: (CGPoint) -> Void
    var onDragEnded: () -> Void

    func makeUIGestureRecognizer(context: Context) -> some UIGestureRecognizer {
        let gesture = LongPressDragGestureRecognizer()
        gesture.minimumPressDuration = 0.6
        gesture.allowableMovement = 8
        gesture.onLongPressBegin = onLongPressBegin
        gesture.onDragChanged = onDragChanged
        gesture.onDragEnded = onDragEnded

        gesture.delegate = context.coordinator
        return gesture
    }

    func handleUIGestureRecognizerAction(_ recognizer: UIGestureRecognizerType, context: Context) {
        guard let gesture = recognizer as? LongPressDragGestureRecognizer else { return }
        gesture.handleGesture()
    }

    func makeCoordinator(converter: CoordinateSpaceConverter) -> Coordinator {
        Coordinator(converter: converter)
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        let converter: CoordinateSpaceConverter

        init(converter: CoordinateSpaceConverter) {
            self.converter = converter
        }

        // Allow simultaneous recognition with ScrollView's pan gesture
        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
            return true
        }

        // Don't require other gestures to wait for us
        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldBeRequiredToFailBy otherGestureRecognizer: UIGestureRecognizer) -> Bool {
            return false
        }
    }
}
#endif

// MARK: - Reorder Support

private struct TabFramePreferenceKey: PreferenceKey {
    static let defaultValue: [Int: CGRect] = [:]
    static func reduce(value: inout [Int : CGRect], nextValue: () -> [Int : CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { $1 })
    }
}

private struct HStackOriginPreferenceKey: PreferenceKey {
    static let defaultValue: CGPoint = .zero
    static func reduce(value: inout CGPoint, nextValue: () -> CGPoint) {
        value = nextValue()
    }
}

private extension View {
    func captureFrame(index: Int) -> some View {
        background(
            GeometryReader { geo in
                Color.clear
                    .preference(key: TabFramePreferenceKey.self, value: [index: geo.frame(in: .named("TabScrollSpace"))])
            }
        )
    }
    func captureOrigin() -> some View {
        background(
            GeometryReader { geo in
                Color.clear
                    .preference(key: HStackOriginPreferenceKey.self, value: geo.frame(in: .named("TabScrollSpace")).origin)
            }
        )
    }
}

@available(iOS 18.0, macOS 11.0, *)
struct EditorTabs: View {
    @Binding var selected: Int?
    @Binding var items: [HostedItem]
    let closeRequest: (Int) -> ()
    @ScaledMetric var dividerSize = 12
    @ScaledMetric var tabSpacing: CGFloat = 10

    // Drag state
    @State private var draggingIndex: Int? = nil
    @State private var dragTranslationX: CGFloat = 0
    @State private var proposedIndex: Int? = nil

    // Layout capture
    @State private var tabFrames: [Int: CGRect] = [:]
    @State private var hstackOrigin: CGPoint = .zero

    // Scroll management
    @State private var contentSize: CGSize = .zero
    @State private var containerSize: CGSize = .zero
    @State private var contentOffsetX: CGFloat = 0
    @State private var autoscrollTimer: Timer?
    @State private var scrollPositionStorage = ScrollPositionStorage()

    // Auto-scroll config
    private let edgeActivationWidth: CGFloat = 60
    private let maxAutoScrollSpeed: CGFloat = 12 // points per tick (Timer ~ 60Hz)
    private let autoScrollTick: TimeInterval = 1.0 / 60.0

    // Suppress animations just during the drop commit
    @State private var committingDrop: Bool = false

    // Equatable wrapper for scroll geometry
    private struct ScrollGeometry: Equatable {
        var containerSize: CGSize
        var contentSize: CGSize
        var contentOffsetX: CGFloat
    }
    private struct ScrollPositionStorage {
        var value: Any? = nil
    }

    @available(iOS 18.0, macOS 15.0, *)
    private func scrollPositionBinding() -> Binding<ScrollPosition> {
        Binding(
            get: { (scrollPositionStorage.value as? ScrollPosition) ?? ScrollPosition(edge: .leading) },
            set: { scrollPositionStorage.value = $0 }
        )
    }

    private func targetIndex(for midX: CGFloat) -> Int? {
        guard !tabFrames.isEmpty else { return nil }
        let sorted = tabFrames.keys.sorted { (tabFrames[$0]?.minX ?? 0) < (tabFrames[$1]?.minX ?? 0) }
        let centers: [CGFloat] = sorted.map { (tabFrames[$0]?.midX ?? 0) }
        if let firstCenter = centers.first, midX < firstCenter { return 0 }
        if let lastCenter = centers.last, midX > lastCenter { return sorted.count }
        for (i, c) in centers.enumerated() where midX < c {
            return i
        }
        return sorted.count
    }

    private func reorderedItems(source: Int, destination: Int) -> [HostedItem] {
        var copy = items
        let moving = copy.remove(at: source)
        let dest = destination > source ? destination - 1 : destination
        copy.insert(moving, at: max(0, min(dest, copy.count)))
        return copy
    }

    private func adjustedOffset(for index: Int) -> CGFloat {
        guard let dragging = draggingIndex, let proposed = proposedIndex else { return 0 }
        if index == dragging { return dragTranslationX }
        guard let draggedFrame = tabFrames[dragging] else { return 0 }
        let draggedWidth = draggedFrame.width + tabSpacing

        let source = dragging
        let dest = proposed

        if dest > source {
            if index > source && index < dest {
                return -draggedWidth
            }
        } else if dest < source {
            if index >= dest && index < source {
                return draggedWidth
            }
        }
        return 0
    }

    private func startAutoscroll() {
        guard #available(iOS 18.0, macOS 15.0, *) else { return }
        if scrollPositionStorage.value == nil {
            scrollPositionStorage.value = ScrollPosition(edge: .leading)
        }
        guard autoscrollTimer == nil else { return }
        autoscrollTimer = Timer.scheduledTimer(withTimeInterval: autoScrollTick, repeats: true) { _ in
            guard let dragging = draggingIndex,
                  let frame = tabFrames[dragging]
            else { return }

            let midX = frame.midX + dragTranslationX
            let leftEdge = contentOffsetX
            let rightEdge = contentOffsetX + containerSize.width

            var delta: CGFloat = 0
            if midX < leftEdge + edgeActivationWidth {
                let dist = max(1, (midX - leftEdge))
                let t = max(0, min(1, (edgeActivationWidth - dist) / edgeActivationWidth))
                delta = -maxAutoScrollSpeed * t
            } else if midX > rightEdge - edgeActivationWidth {
                let dist = max(1, (rightEdge - midX))
                let t = max(0, min(1, (edgeActivationWidth - dist) / edgeActivationWidth))
                delta = maxAutoScrollSpeed * t
            }

            guard delta != 0 else { return }

            let newX = max(0, min(contentSize.width - containerSize.width, contentOffsetX + delta))
            if var position = scrollPositionStorage.value as? ScrollPosition {
                position.scrollTo(x: newX)
                scrollPositionStorage.value = position
            }
        }
    }

    private func stopAutoscroll() {
        autoscrollTimer?.invalidate()
        autoscrollTimer = nil
    }

    var body: some View {
        let scrollView = ScrollView(.horizontal) {
            HStack(spacing: tabSpacing) {
                if let selected {
                    ForEach(Array(items.enumerated()), id: \.offset) { idx, _ in
                        let isDragging = draggingIndex == idx
                        let tab = EditorTab(
                            item: $items[idx],
                            selected: idx == selected,
                            close: { closeRequest(idx) },
                            select: { self.selected = idx }
                        )
                        .scaleEffect(isDragging ? 1.05 : 1.0)
                        .opacity(isDragging ? 0.9 : 1.0)
                        .zIndex(isDragging ? 1 : 0)
                        .offset(x: adjustedOffset(for: idx))
#if os(iOS)
                        .gesture(
                            LongPressDragGesture(
                                onLongPressBegin: {
                                    let impactFeedback = UIImpactFeedbackGenerator(style: .medium)
                                    impactFeedback.impactOccurred()

                                    draggingIndex = idx
                                    dragTranslationX = 0
                                    proposedIndex = idx
                                    startAutoscroll()
                                },
                                onDragChanged: { translation in
                                    guard draggingIndex == idx else { return }
                                    dragTranslationX = translation.x

                                    if let frame = tabFrames[idx] {
                                        let movingMidX = frame.midX + dragTranslationX
                                        if let newProposed = targetIndex(for: movingMidX), newProposed != proposedIndex {
                                            withAnimation(.interactiveSpring(response: 0.25, dampingFraction: 0.8, blendDuration: 0.1)) {
                                                proposedIndex = newProposed
                                            }
                                        }
                                    }
                                },
                                onDragEnded: {
                                    guard draggingIndex == idx else { return }

                                    stopAutoscroll()

                                    let dragging = draggingIndex
                                    let finalProposed = proposedIndex ?? draggingIndex ?? 0

                                    // Begin no-animation commit
                                    committingDrop = true
                                    if let dragging, finalProposed != dragging {
                                        let movedItemID = items[dragging].id
                                        let newItems = reorderedItems(source: dragging, destination: finalProposed)

                                        withTransaction(Transaction(animation: nil)) {
                                            items = newItems
                                            draggingIndex = nil
                                            proposedIndex = nil
                                            dragTranslationX = 0
                                        }
                                        if let newIndex = items.firstIndex(where: { $0.id == movedItemID }) {
                                            withTransaction(Transaction(animation: nil)) {
                                                self.selected = newIndex
                                            }
                                        }
                                    } else {
                                        withTransaction(Transaction(animation: nil)) {
                                            draggingIndex = nil
                                            proposedIndex = nil
                                            dragTranslationX = 0
                                        }
                                    }
                                    // End of commit; re-enable animations on the next runloop tick
                                    DispatchQueue.main.async {
                                        committingDrop = false
                                    }
                                }
                            )
                        )
#endif
                        .captureFrame(index: idx)

                        // Attach animations only when not committing the drop
                        if committingDrop {
                            tab
                        } else {
                            tab
                                .animation(.interactiveSpring(response: 0.25, dampingFraction: 0.8, blendDuration: 0.1), value: draggingIndex)
                                .animation(.interactiveSpring(response: 0.25, dampingFraction: 0.8, blendDuration: 0.1), value: proposedIndex)
                                .animation(.interactiveSpring(response: 0.25, dampingFraction: 0.8, blendDuration: 0.1), value: dragTranslationX)
                        }
                    }
                }
            }
            .captureOrigin()
            .overlay(alignment: .topLeading) {
                if let draggingIndex, let proposedIndex, !tabFrames.isEmpty {
                    let total = items.count
                    let xPos: CGFloat = {
                        let sorted = tabFrames.keys.sorted { (tabFrames[$0]?.minX ?? 0) < (tabFrames[$1]?.minX ?? 0) }
                        if proposedIndex <= 0 {
                            return (tabFrames[sorted.first!]?.minX ?? 0) - tabSpacing/2
                        } else if proposedIndex >= total {
                            return (tabFrames[sorted.last!]?.maxX ?? 0) + tabSpacing/2
                        } else {
                            let leftIdx = sorted[proposedIndex - 1]
                            let rightIdx = sorted[proposedIndex]
                            let leftMax = tabFrames[leftIdx]?.maxX ?? 0
                            let rightMin = tabFrames[rightIdx]?.minX ?? 0
                            return (leftMax + rightMin) / 2
                        }
                    }()

                    let indicator = Rectangle()
                        .fill(Color.accentColor)
                        .frame(width: 2, height: 18)
                        .offset(x: xPos, y: 6)

                    if committingDrop {
                        indicator
                    } else {
                        indicator
                            .animation(.interactiveSpring(response: 0.25, dampingFraction: 0.8, blendDuration: 0.1), value: proposedIndex)
                    }
                }
            }
        }
        .coordinateSpace(name: "TabScrollSpace")
        .scrollDisabled(draggingIndex != nil)
        .onPreferenceChange(TabFramePreferenceKey.self) { tabFrames = $0 }
        .onPreferenceChange(HStackOriginPreferenceKey.self) { hstackOrigin = $0 }
        .scrollIndicators(.hidden)
        .onDisappear {
            stopAutoscroll()
        }
        if #available(iOS 18.0, macOS 15.0, *) {
            scrollView
                .scrollPosition(scrollPositionBinding())
                .onScrollGeometryChange(for: ScrollGeometry.self) { geo in
                    ScrollGeometry(containerSize: geo.containerSize, contentSize: geo.contentSize, contentOffsetX: geo.contentOffset.x)
                } action: { _, new in
                    containerSize = new.containerSize
                    contentSize = new.contentSize
                    contentOffsetX = new.contentOffsetX
                }
        } else {
            scrollView
        }
    }
}

struct DemoEditorTabs: View {
    @State var selected: Int? = 2
    @State var items: [HostedItem] = [
        EditedItem (path: "some/file/foo.txt", content: "Demo", editedItemDelegate: nil),
        EditedItem (path: "res://another.txt", content: "Demo", editedItemDelegate: nil),
        EditedItem (path: "res://third.txt", content: "Demo", editedItemDelegate: nil),
        EditedItem (path: "some/file/foo2.txt", content: "Demo", editedItemDelegate: nil),
        EditedItem (path: "res://another2.txt", content: "Demo", editedItemDelegate: nil),
        EditedItem (path: "res://third2.txt", content: "Demo", editedItemDelegate: nil),
        EditedItem (path: "some/file/foo3.txt", content: "Demo", editedItemDelegate: nil),
        EditedItem (path: "res://another3.txt", content: "Demo", editedItemDelegate: nil),
        EditedItem (path: "res://third3.txt", content: "Demo", editedItemDelegate: nil),
        EditedItem (path: "some/file/foo4.txt", content: "Demo", editedItemDelegate: nil),
        EditedItem (path: "res://another4.txt", content: "Demo", editedItemDelegate: nil),
        EditedItem (path: "res://third4txt", content: "Demo", editedItemDelegate: nil),
        EditedItem (path: "some/file/foo5.txt", content: "Demo", editedItemDelegate: nil),
        EditedItem (path: "res://another5.txt", content: "Demo", editedItemDelegate: nil),
        EditedItem (path: "res://third5.txt", content: "Demo", editedItemDelegate: nil),
        EditedItem (path: "some/file/foo6.txt", content: "Demo", editedItemDelegate: nil),
        EditedItem (path: "res://another6.txt", content: "Demo", editedItemDelegate: nil),
        EditedItem (path: "res://third6.txt", content: "Demo", editedItemDelegate: nil),
    ]

    var body: some View {
        if #available(iOS 18.0, macOS 15.0, *) {
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
        } else {
            // Fallback on earlier versions
        }
    }
}

#Preview {
    ZStack {
        Color (.secondarySystemFill)

        DemoEditorTabs()
    }
}
