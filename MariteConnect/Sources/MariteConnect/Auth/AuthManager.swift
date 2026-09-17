import Foundation
import MSAL
import UIKit

/// Wraps MSAL sign-in and silent token acquisition against Marite's Entra ID tenant.
/// This is the app's only source of Microsoft Graph access tokens.
@MainActor
final class AuthManager: ObservableObject {
    @Published private(set) var isSignedIn = false
    @Published private(set) var displayName: String?
    @Published private(set) var email: String?
    @Published var lastError: String?

    private var application: MSALPublicClientApplication?
    private var currentAccount: MSALAccount?

    init() {
        do {
            let config = MSALPublicClientApplicationConfig(
                clientId: AppConfig.msalClientId,
                redirectUri: AppConfig.msalRedirectUri,
                authority: try MSALAADAuthority(url: URL(string: AppConfig.msalAuthority)!)
            )
            application = try MSALPublicClientApplication(configuration: config)
            restoreExistingAccount()
        } catch {
            lastError = "Failed to configure sign-in: \(error.localizedDescription)"
        }
    }

    private func restoreExistingAccount() {
        guard let application else { return }
        do {
            if let account = try application.allAccounts().first {
                currentAccount = account
                isSignedIn = true
                displayName = account.username
                email = account.username
            }
        } catch {
            // No cached account yet; the user will need to sign in interactively.
        }
    }

    func signIn(presentingViewController: UIViewController) async {
        guard let application else { return }
        let webParameters = MSALWebviewParameters(authPresentationViewController: presentingViewController)
        let parameters = MSALInteractiveTokenParameters(scopes: AppConfig.graphScopes, webviewParameters: webParameters)

        do {
            let result = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<MSALResult, Error>) in
                application.acquireToken(with: parameters) { result, error in
                    if let error { continuation.resume(throwing: error); return }
                    guard let result else {
                        continuation.resume(throwing: AuthError.noResult)
                        return
                    }
                    continuation.resume(returning: result)
                }
            }
            currentAccount = result.account
            isSignedIn = true
            displayName = result.account.username
            email = result.account.username
            lastError = nil
        } catch {
            lastError = "Sign-in failed: \(error.localizedDescription)"
        }
    }

    func signOut() {
        guard let application, let currentAccount else { return }
        do {
            let params = MSALSignoutParameters()
            application.signout(with: currentAccount, signoutParameters: params) { [weak self] _, _ in
                Task { @MainActor in
                    self?.isSignedIn = false
                    self?.currentAccount = nil
                    self?.displayName = nil
                    self?.email = nil
                }
            }
        } catch {
            lastError = "Sign-out failed: \(error.localizedDescription)"
        }
    }

    /// Acquires a Graph access token silently, falling back to nil if interaction is
    /// required (the UI layer should then prompt for a fresh interactive sign-in).
    func acquireToken() async throws -> String {
        guard let application, let currentAccount else {
            throw AuthError.notSignedIn
        }
        let silentParameters = MSALSilentTokenParameters(scopes: AppConfig.graphScopes, account: currentAccount)
        return try await withCheckedThrowingContinuation { continuation in
            application.acquireTokenSilent(with: silentParameters) { result, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                guard let token = result?.accessToken else {
                    continuation.resume(throwing: AuthError.noResult)
                    return
                }
                continuation.resume(returning: token)
            }
        }
    }

    enum AuthError: LocalizedError {
        case notSignedIn
        case noResult

        var errorDescription: String? {
            switch self {
            case .notSignedIn: return "Not signed in."
            case .noResult: return "Sign-in did not return a result."
            }
        }
    }
}
