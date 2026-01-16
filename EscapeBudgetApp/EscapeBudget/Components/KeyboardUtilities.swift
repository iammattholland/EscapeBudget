import Foundation

#if canImport(UIKit)
import UIKit

@MainActor
enum KeyboardUtilities {
    static func dismiss() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }
}
#endif

