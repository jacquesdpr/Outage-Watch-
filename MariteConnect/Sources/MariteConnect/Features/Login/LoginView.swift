import SwiftUI
import UIKit

struct LoginView: View {
    @EnvironmentObject private var authManager: AuthManager

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            VStack(spacing: 12) {
                Image(systemName: "diamond.fill")
                    .font(.system(size: 56))
                    .foregroundStyle(.orange)
                Text("Marite Connect")
                    .font(.largeTitle.bold())
                Text("Staff chat, tasks, SharePoint search, and the\nSectional Title Assistant — all in one place.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            Spacer()

            Button {
                signIn()
            } label: {
                Label("Sign in with Microsoft", systemImage: "person.crop.circle.badge.checkmark")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
            }
            .buttonStyle(.borderedProminent)
            .tint(.orange)
            .padding(.horizontal, 32)

            if let error = authManager.lastError {
                Text(error)
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }

            Text("Use your Marite Microsoft 365 account.")
                .font(.caption)
                .foregroundStyle(.secondary)

            Spacer()
        }
        .padding()
    }

    private func signIn() {
        guard let rootVC = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first?.windows.first(where: \.isKeyWindow)?.rootViewController else { return }
        Task { await authManager.signIn(presentingViewController: rootVC) }
    }
}
