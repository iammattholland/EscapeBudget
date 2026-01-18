import SwiftUI

struct ScrollOffsetPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

struct NamedScrollOffsetsPreferenceKey: PreferenceKey {
    static var defaultValue: [String: CGFloat] = [:]

    static func reduce(value: inout [String: CGFloat], nextValue: () -> [String: CGFloat]) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}

struct ScrollOffsetReader: View {
    let coordinateSpace: String
    var id: String? = nil

    var body: some View {
        GeometryReader { proxy in
            let offset = proxy.frame(in: .named(coordinateSpace)).minY
            Color.clear
                .preference(key: ScrollOffsetPreferenceKey.self, value: offset)
                .preference(key: NamedScrollOffsetsPreferenceKey.self, value: {
                    if let id { return [id: offset] }
                    return [:]
                }())
        }
        .frame(height: 0)
    }
}
