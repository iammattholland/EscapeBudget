import AuthenticationServices
import Combine
import Foundation

@MainActor
final class UserAccountService: NSObject, ObservableObject {
    static let shared = UserAccountService()

    @Published private(set) var isSignedIn: Bool = false
    @Published private(set) var userID: String?
    @Published private(set) var email: String?
    @Published private(set) var credentialState: ASAuthorizationAppleIDProvider.CredentialState = .revoked

    private let keychain = KeychainService.shared

    private override init() {
        super.init()
        reloadFromStorage()
    }

    func reloadFromStorage() {
        userID = keychain.getString(forKey: .appleUserID)
        email = keychain.getString(forKey: .appleEmail)
        isSignedIn = userID != nil
        Task { await refreshCredentialState() }
    }

    func signOut() {
        keychain.remove(forKey: .appleUserID)
        keychain.remove(forKey: .appleEmail)
        reloadFromStorage()
    }

    func handleSignInCompletion(result: Result<ASAuthorization, Error>) {
        switch result {
        case .failure:
            break
        case .success(let authorization):
            guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential else { return }
            let user = credential.user
            _ = keychain.setString(user, forKey: .appleUserID)

            if let email = credential.email, !email.isEmpty {
                _ = keychain.setString(email, forKey: .appleEmail)
            }

            reloadFromStorage()
        }
    }

    func refreshCredentialState() async {
        guard let userID else {
            credentialState = .revoked
            return
        }

        let provider = ASAuthorizationAppleIDProvider()
        do {
            let state = try await provider.credentialState(forUserID: userID)
            credentialState = state
            if state != .authorized {
                signOut()
            }
        } catch {
            credentialState = .revoked
        }
    }
}
