import Foundation
import Observation
import SwiftUI
import UIKit
import UniformTypeIdentifiers

struct RootView: View {
    @State private var model = SignModel()
    @State private var isPicking = false
    @AppStorage("showCertificateSetup") private var showCertificateSetup = true
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
                if model.certificateTrusted == false && showCertificateSetup {
                    certificateSection
                }
                shortcutsSection
                if !model.shortcuts.isEmpty {
                    actionSection
                }
                finePrint
            }
            .navigationTitle("ShortSign")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink {
                        SettingsView()
                    } label: {
                        Image(systemName: "gearshape")
                    }
                }
            }
            .fileImporter(
                isPresented: $isPicking,
                allowedContentTypes: [.item],
                allowsMultipleSelection: true
            ) { result in
                switch result {
                case .success(let urls):
                    model.add(urls)
                case .failure(let error):
                    model.error = error.localizedDescription
                }
            }
            .onOpenURL { url in
                if url.isFileURL {
                    model.add([url])
                }
            }
            .sheet(item: $model.shareItem) { item in
                ShareSheet(items: item.urls)
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
            Text("Save it to Files, tap the profile, install it, then enable full trust in Settings › General › About › Certificate Trust Settings. This section disappears when the certificate is installed.")
        }
    }

    private var shortcutsSection: some View {
        Section {
            if model.shortcuts.isEmpty {
                Text("No shortcuts selected")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(model.shortcuts) { item in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.name)
                        Text(item.wasSigned
                             ? "\(item.actionCount) actions · \(item.source) · will re-sign"
                             : "\(item.actionCount) actions · \(item.source)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .onDelete { model.remove(at: $0) }
                .deleteDisabled(model.isSigning)
            }
            Button {
                isPicking = true
            } label: {
                Label("Choose Shortcut Files", systemImage: "doc.badge.plus")
            }
            .disabled(model.isSigning || model.isDownloading)
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
            Text("Shortcuts")
        } footer: {
            Text("Unsigned or signed .shortcut, .wflow or plist. Signed files are extracted and re-signed. Swipe to remove.")
        }
    }

    private var actionSection: some View {
        Section {
            if model.signedURLs.isEmpty {
                Button {
                    model.signAll()
                } label: {
                    HStack {
                        Label(
                            model.shortcuts.count == 1
                                ? "Sign Shortcut"
                                : "Sign \(model.shortcuts.count) Shortcuts",
                            systemImage: "signature"
                        )
                        Spacer()
                        if model.isSigning {
                            if !model.signProgress.isEmpty {
                                Text(model.signProgress)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            ProgressView()
                        }
                    }
                }
                .disabled(!model.canSign)
            } else {
                Button {
                    model.shareSigned()
                } label: {
                    Label("Share Again", systemImage: "square.and.arrow.up")
                }
            }
        } footer: {
            if !model.signedURLs.isEmpty {
                Text("Choose Shortcuts, or save the files to Files and tap them.")
            }
        }
    }

    private var finePrint: some View {
        Section {
            Text("Self-signed: shortcuts import only on devices that trust your certificate. The key is generated on this device. For public sharing, import first, then use Shortcuts → Copy iCloud Link.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }
}

struct ShortcutItem: Identifiable, Sendable {
    let id = UUID()
    let name: String
    let actionCount: Int
    let plist: Data
    let source: String
    let wasSigned: Bool
}

struct ShareItem: Identifiable {
    let id = UUID()
    let urls: [URL]
}

@MainActor
@Observable
final class SignModel {
    var shortcuts: [ShortcutItem] = []
    var signedURLs: [URL] = []
    var shareItem: ShareItem?
    var isSigning = false
    var signProgress = ""
    var error: String?
    var urlText = ""
    var isDownloading = false
    var certificateTrusted: Bool?

    var canDownload: Bool {
        !urlText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !isDownloading
            && !isSigning
    }

    var canSign: Bool {
        !shortcuts.isEmpty && !isSigning && !isDownloading
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
            error = "The signing certificate is missing."
            return
        }
        shareItem = ShareItem(urls: [certificate])
    }

    func shareSigned() {
        if !signedURLs.isEmpty {
            shareItem = ShareItem(urls: signedURLs)
        }
    }

    func add(_ urls: [URL]) {
        for url in urls {
            let accessing = url.startAccessingSecurityScopedResource()
            defer { if accessing { url.stopAccessingSecurityScopedResource() } }

            do {
                let summary = try ShortcutSigner.summarize(Data(contentsOf: url))
                shortcuts.append(ShortcutItem(
                    name: summary.name,
                    actionCount: summary.actionCount,
                    plist: summary.plist,
                    source: url.lastPathComponent,
                    wasSigned: summary.wasSigned
                ))
            } catch {
                self.error = "\(url.lastPathComponent): \(error.localizedDescription)"
            }
        }
        signedURLs = []
    }

    func remove(at offsets: IndexSet) {
        shortcuts.remove(atOffsets: offsets)
        signedURLs = []
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
        isDownloading = true

        Task {
            defer { isDownloading = false }
            do {
                let (data, response) = try await URLSession.shared.data(from: url)
                if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                    throw HTTPError(status: http.statusCode)
                }
                let summary = try ShortcutSigner.summarize(data)
                shortcuts.append(ShortcutItem(
                    name: summary.name,
                    actionCount: summary.actionCount,
                    plist: summary.plist,
                    source: url.host ?? "URL",
                    wasSigned: summary.wasSigned
                ))
                signedURLs = []
                urlText = ""
            } catch {
                self.error = error.localizedDescription
            }
        }
    }

    func signAll() {
        guard !shortcuts.isEmpty else { return }
        let items = shortcuts
        isSigning = true
        error = nil
        signedURLs = []
        signProgress = ""

        Task {
            defer {
                isSigning = false
                signProgress = ""
            }
            var urls: [URL] = []
            do {
                for (index, item) in items.enumerated() {
                    signProgress = items.count > 1 ? "\(index + 1)/\(items.count)" : ""
                    do {
                        let data = try await Task.detached {
                            try ShortcutSigner.sign(item.plist)
                        }.value
                        urls.append(try write(data, name: item.name))
                    } catch {
                        throw SignItemError(name: item.name, reason: error.localizedDescription)
                    }
                }
                signedURLs = urls
                shareItem = ShareItem(urls: urls)
            } catch {
                signedURLs = []
                self.error = error.localizedDescription
            }
        }
    }

    private func write(_ data: Data, name: String) throws -> URL {
        let safeName = name
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("\(safeName).shortcut")
        try data.write(to: url, options: .atomic)
        return url
    }
}

private struct SignItemError: LocalizedError {
    let name: String
    let reason: String

    var errorDescription: String? {
        "Couldn't sign \(name): \(reason)"
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
