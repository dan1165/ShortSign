import Foundation
import Observation
import SwiftUI
import UIKit
import UniformTypeIdentifiers

struct RootView: View {
    @State private var model = SignModel()
    @State private var isPicking = false
    @Environment(\.scenePhase) private var scenePhase

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
                if model.certificateTrusted == false {
                    certificateSection
                }
                shortcutSection
                if model.summary != nil {
                    actionSection
                }
                finePrint
            }
            .navigationTitle("ShortSign")
            .fileImporter(
                isPresented: $isPicking,
                allowedContentTypes: [.item]
            ) { result in
                switch result {
                case .success(let url):
                    model.load(url)
                case .failure(let error):
                    model.error = error.localizedDescription
                }
            }
            .sheet(item: $model.shareItem) { item in
                ShareSheet(items: [item.url])
            }
            .task {
                model.refreshCertificateTrust()
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active {
                    model.refreshCertificateTrust()
                }
            }
        }
    }

    private var header: some View {
        Section {
            VStack(alignment: .leading, spacing: 6) {
                Text("Sign shortcuts on this iPhone")
                    .font(.title2.bold())
                Text("On-device. No Mac, server or Apple ID.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 4)
        }
    }

    private var certificateSection: some View {
        Section {
            Button {
                model.shareCertificate()
            } label: {
                Label("Install Certificate", systemImage: "checkmark.seal")
            }
        } header: {
            Text("Certificate")
        } footer: {
            Text("Save it to Files, tap the profile, install it, then enable full trust in Settings › General › About › Certificate Trust Settings. This section disappears when the certificate is trusted.")
        }
    }

    private var shortcutSection: some View {
        Section {
            if let summary = model.summary {
                LabeledContent("Name", value: summary.name)
                LabeledContent("Actions", value: "\(summary.actionCount)")
            }
            Button {
                isPicking = true
            } label: {
                Label("Choose Shortcut File", systemImage: "doc.badge.plus")
            }
            HStack(spacing: 8) {
                TextField("https://example.com/My.shortcut", text: $model.urlText)
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                Button {
                    model.download()
                } label: {
                    if model.isDownloading {
                        ProgressView()
                    } else {
                        Image(systemName: "arrow.down.circle")
                    }
                }
                .buttonStyle(.borderless)
                .disabled(!model.canDownload)
                .accessibilityLabel("Download shortcut")
            }
        } header: {
            Text("Shortcut")
        } footer: {
            Text("Unsigned .shortcut, .wflow or plist. Already-signed files are rejected.")
        }
    }

    private var actionSection: some View {
        Section {
            if model.signedURL == nil {
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
                .disabled(model.isSigning || model.isDownloading)
            } else {
                Button {
                    model.shareSigned()
                } label: {
                    Label("Share Again", systemImage: "square.and.arrow.up")
                }
            }
        } footer: {
            if model.signedURL != nil {
                Text("Choose Shortcuts, or save the file to Files and tap it.")
            }
        }
    }

    private var finePrint: some View {
        Section {
            Text("Self-signed: shortcuts import only on devices that trust your certificate. Not for public sharing. If import fails, check Settings › General › About › Certificate Trust Settings.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }
}

struct ShareItem: Identifiable {
    let id = UUID()
    let url: URL
}

@MainActor
@Observable
final class SignModel {
    var summary: ShortcutSigner.Summary?
    var signedURL: URL?
    var shareItem: ShareItem?
    var isSigning = false
    var error: String?
    var urlText = ""
    var isDownloading = false
    var certificateTrusted: Bool?

    var canDownload: Bool {
        !urlText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !isDownloading
            && !isSigning
    }

    func refreshCertificateTrust() {
        Task {
            let trusted = await Task.detached {
                ShortcutSigner.isCertificateTrusted()
            }.value
            certificateTrusted = trusted
        }
    }

    func shareCertificate() {
        guard let certificate = ShortcutFile.certificate else {
            error = "The bundled certificate is missing."
            return
        }
        shareItem = ShareItem(url: certificate)
    }

    func shareSigned() {
        if let signedURL {
            shareItem = ShareItem(url: signedURL)
        }
    }

    func load(_ url: URL) {
        error = nil
        signedURL = nil
        summary = nil

        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }

        do {
            summary = try ShortcutSigner.summarize(Data(contentsOf: url))
        } catch {
            self.error = error.localizedDescription
        }
    }

    func download() {
        let text = urlText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard
            let url = URL(string: text),
            url.scheme?.lowercased() == "https",
            url.host != nil
        else {
            error = "Enter a valid https:// URL."
            return
        }

        error = nil
        signedURL = nil
        summary = nil
        isDownloading = true

        Task {
            defer { isDownloading = false }
            do {
                let (data, response) = try await URLSession.shared.data(from: url)
                if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                    throw HTTPError(status: http.statusCode)
                }
                summary = try ShortcutSigner.summarize(data)
            } catch {
                self.error = error.localizedDescription
            }
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
                let url = try write(data, name: summary.name)
                signedURL = url
                shareItem = ShareItem(url: url)
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

private struct HTTPError: LocalizedError {
    let status: Int

    var errorDescription: String? {
        "The server returned HTTP \(status)."
    }
}

/// UIActivityViewController so ShortSign can hand files to other apps.
struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
