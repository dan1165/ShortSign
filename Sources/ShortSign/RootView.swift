import Observation
import SwiftUI
import UIKit
import UniformTypeIdentifiers

struct RootView: View {
    @State private var model = SignModel()
    @State private var isPicking = false
    @State private var isSharingCertificate = false

    var body: some View {
        NavigationStack {
            List {
                header
                if let error = model.error {
                    Section {
                        Label(error, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                    }
                }
                certificateSection
                fileSection
                if model.summary != nil || model.isSigning {
                    signSection
                }
                if let signedURL = model.signedURL {
                    shareSection(signedURL)
                }
                finePrint
            }
            .navigationTitle("ShortSign")
            .fileImporter(
                isPresented: $isPicking,
                allowedContentTypes: [.data]
            ) { result in
                switch result {
                case .success(let url):
                    model.load(url)
                case .failure(let error):
                    model.error = error.localizedDescription
                }
            }
            .sheet(isPresented: $isSharingCertificate) {
                if let certificate = ShortcutFile.certificate {
                    ShareSheet(items: [certificate])
                }
            }
        }
    }

    private var header: some View {
        Section {
            VStack(alignment: .leading, spacing: 8) {
                Image(systemName: "scissors")
                    .font(.system(size: 40, weight: .semibold))
                    .foregroundStyle(.tint)
                Text("Sign shortcuts on your iPhone")
                    .font(.title2.bold())
                Text("Turns an unsigned shortcut plist into a signed .shortcut. Everything happens on this device — no Mac, no server, no Apple ID.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 8)
        }
    }

    private var certificateSection: some View {
        Section {
            LabeledContent("Signing certificate", value: "Self-signed")
            Button {
                isSharingCertificate = true
            } label: {
                Label("Share Certificate", systemImage: "checkmark.seal")
            }
            .disabled(ShortcutFile.certificate == nil)
            Text("Save the certificate to Files, tap it, then install the profile. Enable full trust in Settings › General › About › Certificate Trust Settings. Signed shortcuts only import on devices that trust this certificate.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        } header: {
            Text("Step 1 — Trust the certificate")
        }
    }

    private var fileSection: some View {
        Section {
            Button {
                isPicking = true
            } label: {
                Label("Choose Shortcut File", systemImage: "doc.badge.plus")
            }
            if let summary = model.summary {
                LabeledContent("Name", value: summary.name)
                LabeledContent("Actions", value: "\(summary.actionCount)")
                LabeledContent("Source", value: model.fileName)
            }
        } header: {
            Text("Step 2 — Pick a shortcut")
        } footer: {
            Text("Accepts an unsigned .shortcut, .wflow or plist file. Signed shortcuts cannot be re-signed.")
        }
    }

    private var signSection: some View {
        Section {
            Button {
                model.sign()
            } label: {
                HStack {
                    Label("Sign Shortcut", systemImage: "signature")
                    Spacer()
                    if model.isSigning {
                        ProgressView()
                    }
                }
            }
            .disabled(model.summary == nil || model.isSigning)
        } header: {
            Text("Step 3 — Sign")
        }
    }

    private func shareSection(_ url: URL) -> some View {
        Section {
            ShareLink(item: url) {
                Label("Share Signed Shortcut", systemImage: "square.and.arrow.up")
            }
            Label("Tap Share and choose Shortcuts, or save it to Files and tap the file.", systemImage: "info.circle")
                .font(.footnote)
                .foregroundStyle(.secondary)
        } header: {
            Text("Signed")
        }
    }

    private var finePrint: some View {
        Section {
            Text("ShortSign does not use Apple's signing service. A self-signed shortcut is importable only after the ShortSign certificate is trusted on the receiving device, so do not use it for public iCloud links. The signing key is stored inside the app.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }
}

@MainActor
@Observable
final class SignModel {
    var fileName = ""
    var summary: ShortcutSigner.Summary?
    var signedURL: URL?
    var isSigning = false
    var error: String?

    func load(_ url: URL) {
        error = nil
        signedURL = nil
        summary = nil
        fileName = url.lastPathComponent

        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }

        do {
            let data = try Data(contentsOf: url)
            summary = try ShortcutSigner.summarize(data)
        } catch {
            self.error = error.localizedDescription
        }
    }

    func sign() {
        guard let summary else { return }
        isSigning = true
        error = nil
        signedURL = nil

        Task {
            defer { isSigning = false }
            do {
                let data = try await Task.detached {
                    try ShortcutSigner.sign(summary.plist)
                }.value
                signedURL = try write(data, name: summary.name)
            } catch {
                self.error = error.localizedDescription
            }
        }
    }

    private func write(_ data: Data, name: String) throws -> URL {
        let safeName = name
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(safeName).shortcut")
        try data.write(to: url, options: .atomic)
        return url
    }
}

/// UIActivityViewController so the certificate can be handed to Settings.
struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
