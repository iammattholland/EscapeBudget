import SwiftUI

/// Standardized chrome + content spacing for list-based screens.
struct AppChromeListRow: View {
    let topChrome: AnyView?
    let scrollID: String?

    init(topChrome: AnyView?, scrollID: String? = nil) {
        self.topChrome = topChrome
        self.scrollID = scrollID
    }

    var body: some View {
        VStack(spacing: AppDesign.Theme.Layout.topChromeContentGap) {
            if let scrollID {
                ScrollOffsetReader(coordinateSpace: scrollID, id: scrollID)
            }
            if let topChrome {
                topChrome
            }
        }
        .padding(.top, AppDesign.Theme.Layout.topChromeTopPadding)
        .padding(.bottom, AppDesign.Theme.Layout.topChromeContentGap)
        .listRowInsets(EdgeInsets())
        .listRowSeparator(.hidden)
        .listRowBackground(Color.clear)
    }
}

/// Standardized chrome + content spacing for scroll-based screens.
struct AppChromeStack<Content: View>: View {
    let topChrome: AnyView?
    let scrollID: String?
    let content: Content

    init(topChrome: AnyView?, scrollID: String? = nil, @ViewBuilder content: () -> Content) {
        self.topChrome = topChrome
        self.scrollID = scrollID
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AppDesign.Theme.Layout.topChromeContentGap) {
            if let scrollID {
                ScrollOffsetReader(coordinateSpace: scrollID, id: scrollID)
            }
            if let topChrome {
                topChrome
            }
            content
        }
        .padding(.top, AppDesign.Theme.Layout.topChromeTopPadding)
    }
}
