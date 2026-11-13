import SwiftUI

struct StaffSetupView: View {
    @EnvironmentObject private var cloudKit: CloudKitManager
    @State private var name = ""
    @State private var isSaving = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            VStack(spacing: 12) {
                Image(systemName: "diamond.fill")
                    .font(.system(size: 56))
                    .foregroundStyle(.orange)
                Text("Marite Connect")
                    .font(.largeTitle.bold())

                if let iCloudError = cloudKit.errorMessage, cloudKit.accountStatus != .available {
                    Text(iCloudError)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                } else {
                    Text("What should we call you? This is shown to colleagues\nwhen you post or get tagged.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
            }

            Spacer()

            if cloudKit.accountStatus == .available {
                VStack(spacing: 12) {
                    TextField("Your name", text: $name)
                        .textFieldStyle(.roundedBorder)
                        .textInputAutocapitalization(.words)
                        .padding(.horizontal, 32)

                    Button(action: save) {
                        if isSaving {
                            ProgressView()
                        } else {
                            Text("Continue").frame(maxWidth: .infinity).padding(.vertical, 4)
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.orange)
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || isSaving)
                    .padding(.horizontal, 32)
                }
            } else {
                Button("Try Again") {
                    Task { await cloudKit.start() }
                }
                .buttonStyle(.bordered)
            }

            if let errorMessage {
                Text(errorMessage).font(.footnote).foregroundStyle(.red).padding(.horizontal, 32)
            }

            Spacer()
        }
        .padding()
        .task { await cloudKit.start() }
    }

    private func save() {
        isSaving = true
        errorMessage = nil
        Task {
            do {
                try await cloudKit.registerStaff(displayName: name.trimmingCharacters(in: .whitespaces))
            } catch {
                errorMessage = error.localizedDescription
            }
            isSaving = false
        }
    }
}
