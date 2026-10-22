import SwiftUI

struct SettingsView: View {
    @State private var trusted: Bool?
    @State private var shareItem: ShareItem?
    @Environment(\.scenePhase) private var scenePhase

    private let details = ShortcutSigner.certificateDetails()

    var body: some View {
        List {
            Section {
                LabeledContent("Status", value: status)
                if let details {
                    LabeledContent("Subject", value: details.subject)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("SHA-256")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(details.fingerprint)
                            .font(.caption.monospaced())
                            .textSelection(.enabled)
                    }
                }
                Button {
                    shareCertificate()
                } label: {
                    Label("Install Certificate", systemImage: "checkmark.seal")
                }
            } header: {
                Text("Certificate")
            } footer: {
                Text("Enable full trust in Settings › General › About › Certificate Trust Settings.")
            }

            Section("App") {
                LabeledContent("Version", value: appVersion)
            }
        }
        .navigationTitle("Settings")
        .onAppear {
            refresh()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                refresh()
            }
        }
        .sheet(item: $shareItem) { item in
            ShareSheet(items: item.urls)
        }
    }

    private var status: String {
        switch trusted {
        case true:
            "Installed"
        case false:
            "Not installed"
        case nil:
            "Checking…"
        }
    }

    private var appVersion: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return "\(version) (\(build))"
    }

    private func refresh() {
        Task {
            trusted = await Task.detached {
                ShortcutSigner.isCertificateTrusted()
            }.value
        }
    }

    private func shareCertificate() {
        guard let certificate = ShortcutFile.certificate else { return }
        shareItem = ShareItem(urls: [certificate])
    }
}
