import SwiftUI

#if canImport(UIKit)
import UIKit

private extension UIScrollView {
    var escapeBudgetNormalizedScrollOffset: CGFloat {
        // Match ScrollOffsetReader semantics:
        // - At top: 0
        // - Scrolling down: negative values
        -(contentOffset.y + adjustedContentInset.top)
    }
}

private extension UIView {
    func enclosingScrollView() -> UIScrollView? {
        var candidate: UIView? = self
        while let current = candidate {
            if let scrollView = current as? UIScrollView { return scrollView }
            candidate = current.superview
        }
        return nil
    }

    func scrollViewsInDescendants(limit: Int = 64) -> [UIScrollView] {
        var found: [UIScrollView] = []
        var queue: [UIView] = [self]
        while let current = queue.first {
            queue.removeFirst()
            if let scrollView = current as? UIScrollView {
                found.append(scrollView)
                if found.count >= limit { break }
            }
            queue.append(contentsOf: current.subviews)
        }
        return found
    }

    func bestCandidateScrollView(from scrollViews: [UIScrollView]) -> UIScrollView? {
        guard !scrollViews.isEmpty else { return nil }

        if let tableView = scrollViews.first(where: { $0 is UITableView }) {
            return tableView
        }

        func score(_ scrollView: UIScrollView) -> Double {
            let boundsHeight = max(1, scrollView.bounds.height)
            let contentHeight = scrollView.contentSize.height
            let isVertScrollable = scrollView.alwaysBounceVertical || contentHeight > boundsHeight + 1
            let scrollableBonus = isVertScrollable ? 10_000 : 0
            return Double(scrollableBonus) + Double(contentHeight) + Double(boundsHeight) * 0.001
        }

        return scrollViews.max(by: { score($0) < score($1) })
    }

    func nearestScrollViewBySearchingAncestorSubtrees(maxHops: Int = 12) -> UIScrollView? {
        var candidate: UIView? = self
        var hops = 0
        while let current = candidate, hops < maxHops {
            if let direct = current as? UIScrollView { return direct }
            let scrollViews = current.scrollViewsInDescendants()
            if let best = current.bestCandidateScrollView(from: scrollViews) { return best }
            candidate = current.superview
            hops += 1
        }
        return nil
    }
}

private struct ScrollViewOffsetObserverRepresentable: UIViewRepresentable {
    let onOffsetChange: (CGFloat) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onOffsetChange: onOffsetChange)
    }

    func makeUIView(context: Context) -> UIView {
        let view = UIView(frame: .zero)
        view.isUserInteractionEnabled = false
        DispatchQueue.main.async {
            context.coordinator.attachIfNeeded(from: view)
        }
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        DispatchQueue.main.async {
            context.coordinator.attachIfNeeded(from: uiView)
        }
    }

    final class Coordinator: NSObject {
        private let onOffsetChange: (CGFloat) -> Void
        private var observation: NSKeyValueObservation?
        private weak var scrollView: UIScrollView?
        private var lastEmitted: CGFloat = .nan

        init(onOffsetChange: @escaping (CGFloat) -> Void) {
            self.onOffsetChange = onOffsetChange
        }

        func attachIfNeeded(from view: UIView) {
            guard let found = view.nearestScrollViewBySearchingAncestorSubtrees() else { return }
            guard scrollView !== found else { return }

            scrollView = found
            observation?.invalidate()
            observation = found.observe(\.contentOffset, options: [.initial, .new]) { [weak self] scrollView, _ in
                guard let self else { return }
                let offset = scrollView.escapeBudgetNormalizedScrollOffset
                if self.lastEmitted.isNaN || abs(self.lastEmitted - offset) > 0.5 {
                    self.lastEmitted = offset
                    DispatchQueue.main.async {
                        self.onOffsetChange(offset)
                    }
                }
            }
        }

        deinit {
            observation?.invalidate()
        }
    }
}

struct ScrollOffsetEmitter: View {
    let id: String
    var emitLegacy: Bool = false

    @State private var offset: CGFloat = 0

    var body: some View {
        let base = ScrollViewOffsetObserverRepresentable { newOffset in
            offset = newOffset
        }
        .frame(width: 0, height: 0)
        .preference(key: NamedScrollOffsetsPreferenceKey.self, value: [id: offset])

        Group {
            if emitLegacy {
                base.preference(key: ScrollOffsetPreferenceKey.self, value: offset)
            } else {
                base
            }
        }
    }
}
#else
struct ScrollOffsetEmitter: View {
    let id: String
    var emitLegacy: Bool = false

    var body: some View {
        Color.clear
    }
}
#endif
