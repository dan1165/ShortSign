import CShortcutSign
import Foundation

/// Parses an unsigned shortcut plist and signs it with the bundled self-signed
/// identity. Signing needs no network, Apple ID or Mac.
enum ShortcutSigner {
    struct Summary: Sendable {
        let name: String
        let actionCount: Int
        let plist: Data
    }

    enum SignError: LocalizedError {
        case notAShortcut
        case alreadySigned
        case missingIdentity
        case failed

        var errorDescription: String? {
            switch self {
            case .notAShortcut:
                "That file is not a shortcut plist."
            case .alreadySigned:
                "That shortcut is already signed. Pick the unsigned .shortcut or plist."
            case .missingIdentity:
                "The bundled signing identity is missing."
            case .failed:
                "Signing failed."
            }
        }
    }

    static func summarize(_ data: Data) throws -> Summary {
        if data.starts(with: Array("AEA1".utf8)) {
            throw SignError.alreadySigned
        }
        guard
            let object = try? PropertyListSerialization.propertyList(from: data, format: nil),
            let workflow = object as? [String: Any],
            let actions = workflow["WFWorkflowActions"] as? [Any]
        else {
            throw SignError.notAShortcut
        }
        let name = (workflow["WFWorkflowName"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        let plist = try PropertyListSerialization.data(
            fromPropertyList: workflow, format: .binary, options: 0
        )
        return Summary(
            name: name.flatMap { $0.isEmpty ? nil : $0 } ?? "Untitled",
            actionCount: actions.count,
            plist: plist
        )
    }

    static func sign(_ plist: Data) throws -> Data {
        guard
            let key = Bundle.module.url(forResource: "key", withExtension: "dat"),
            let auth = Bundle.module.url(forResource: "auth", withExtension: "plist")
        else {
            throw SignError.missingIdentity
        }
        let keyData = try Data(contentsOf: key)
        let authData = try Data(contentsOf: auth)

        var output: UnsafeMutableRawPointer?
        var outputSize = 0
        let status = plist.withUnsafeBytes { plistBytes in
            keyData.withUnsafeBytes { keyBytes in
                authData.withUnsafeBytes { authBytes in
                    shorts_sign(
                        plistBytes.baseAddress, plist.count,
                        keyBytes.baseAddress, keyData.count,
                        authBytes.baseAddress, authData.count,
                        &output, &outputSize
                    )
                }
            }
        }
        guard status == 0, let output else { throw SignError.failed }
        defer { shorts_free(output) }

        let signed = Data(bytes: output, count: outputSize)
        guard signed.starts(with: Array("AEA1".utf8)) else { throw SignError.failed }
        return signed
    }
}

/// `UTType.data` keeps the picker useful for `.shortcut`, `.plist` and `.wflow`
/// files, which have no public type identifier.
enum ShortcutFile {
    static let certificate: URL? = Bundle.module.url(forResource: "ShortSign", withExtension: "cer")
}
