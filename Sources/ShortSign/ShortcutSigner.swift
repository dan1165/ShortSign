import CShortcutSign
import CryptoKit
import Foundation
import Security

/// Parses a shortcut plist, extracts signed shortcuts, and signs with the
/// bundled self-signed identity. Everything is local.
enum ShortcutSigner {
    struct Summary: Sendable {
        let name: String
        let actionCount: Int
        let plist: Data
        let wasSigned: Bool
    }

    struct CertificateDetails: Sendable {
        let subject: String
        let fingerprint: String
    }

    enum SignError: LocalizedError {
        case notAShortcut
        case extractFailed
        case missingIdentity
        case failed

        var errorDescription: String? {
            switch self {
            case .notAShortcut:
                "That file is not a shortcut plist."
            case .extractFailed:
                "Couldn't extract the shortcut data."
            case .missingIdentity:
                "The bundled signing identity is missing."
            case .failed:
                "Signing failed."
            }
        }
    }

    static func summarize(_ data: Data) throws -> Summary {
        let wasSigned = data.starts(with: Array("AEA1".utf8))
        let plistData = wasSigned ? try extract(data) : data

        guard
            let object = try? PropertyListSerialization.propertyList(from: plistData, format: nil),
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
            plist: plist,
            wasSigned: wasSigned
        )
    }

    /// Extracts Shortcut.wflow from a signed AEA1 shortcut.
    static func extract(_ data: Data) throws -> Data {
        var output: UnsafeMutableRawPointer?
        var outputSize = 0
        let status = data.withUnsafeBytes { bytes in
            shorts_extract(bytes.baseAddress, data.count, &output, &outputSize)
        }
        guard status == 0, let output else { throw SignError.extractFailed }
        defer { shorts_free(output) }
        return Data(bytes: output, count: outputSize)
    }

    /// True when the bundled root certificate is installed in the trust store.
    /// iOS has no public API for reading the full-trust toggle, so try the
    /// policies the toggle can apply to and treat a chain success as installed.
    static func isCertificateTrusted() -> Bool {
        guard
            let url = ShortcutFile.certificate,
            let data = try? Data(contentsOf: url),
            let root = SecCertificateCreateWithData(nil, data as CFData)
        else {
            return false
        }

        return isTrusted(root, SecPolicyCreateSSL(true, nil))
            || isTrusted(root, SecPolicyCreateSSL(false, nil))
            || isTrusted(root, SecPolicyCreateBasicX509())
    }

    private static func isTrusted(_ certificate: SecCertificate, _ policy: SecPolicy) -> Bool {
        var trust: SecTrust?
        guard
            SecTrustCreateWithCertificates(certificate, policy, &trust) == errSecSuccess,
            let trust
        else {
            return false
        }
        return SecTrustEvaluateWithError(trust, nil)
    }

    static func certificateDetails() -> CertificateDetails? {
        guard
            let url = ShortcutFile.certificate,
            let data = try? Data(contentsOf: url),
            let certificate = SecCertificateCreateWithData(nil, data as CFData)
        else {
            return nil
        }
        let subject = (SecCertificateCopySubjectSummary(certificate) as String?) ?? "ShortSign Root"
        let fingerprint = SHA256.hash(data: SecCertificateCopyData(certificate) as Data)
            .map { String(format: "%02X", $0) }
            .joined(separator: ":")
        return CertificateDetails(subject: subject, fingerprint: fingerprint)
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

/// The bundled root certificate, shared with Settings to enable trust.
enum ShortcutFile {
    static let certificate: URL? = Bundle.module.url(forResource: "ShortSign", withExtension: "cer")
}
