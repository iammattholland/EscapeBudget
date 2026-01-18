import Foundation
import Combine

@MainActor
final class ManageNavigator: ObservableObject {
    @Published var selectedSection: ManageSection = .transactions
}
