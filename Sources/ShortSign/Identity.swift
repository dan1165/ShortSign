import CShortcutSign
import Foundation

struct SigningIdentity: Sendable {
    let keyURL: URL
    let authURL: URL
    let certificateURL: URL
}

/// Creates and stores one signing identity per install.
final class SigningIdentityStore: @unchecked Sendable {
    static let shared = SigningIdentityStore()

    private let lock = NSLock()
    private var cached: SigningIdentity?

    func current() throws -> SigningIdentity {
        lock.lock()
        defer { lock.unlock() }
        if let cached {
            return cached
        }
        let identity = try loadOrCreate()
        cached = identity
        return identity
    }

    private func loadOrCreate() throws -> SigningIdentity {
        let fileManager = FileManager.default
        let base = try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let directory = base.appendingPathComponent("Identity", isDirectory: true)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)

        let identity = SigningIdentity(
            keyURL: directory.appendingPathComponent("key.dat"),
            authURL: directory.appendingPathComponent("auth.plist"),
            certificateURL: directory.appendingPathComponent("root.cer")
        )
        if fileManager.fileExists(atPath: identity.keyURL.path),
           fileManager.fileExists(atPath: identity.authURL.path),
           fileManager.fileExists(atPath: identity.certificateURL.path) {
            return identity
        }

        try generate(into: identity)
        return identity
    }

    private func generate(into identity: SigningIdentity) throws {
        var key: UnsafeMutableRawPointer?
        var leaf: UnsafeMutableRawPointer?
        var root: UnsafeMutableRawPointer?
        var keySize = 0
        var leafSize = 0
        var rootSize = 0

        let status = shorts_create_identity(
            &key, &keySize,
            &leaf, &leafSize,
            &root, &rootSize
        )
        guard status == 0, let key, let leaf, let root else {
            throw IdentityError.generationFailed
        }
        defer {
            shorts_free(key)
            shorts_free(leaf)
            shorts_free(root)
        }

        let keyData = Data(bytes: key, count: keySize)
        let leafData = Data(bytes: leaf, count: leafSize)
        let rootData = Data(bytes: root, count: rootSize)
        let authData = try PropertyListSerialization.data(
            fromPropertyList: ["SigningCertificateChain": [leafData, rootData]],
            format: .binary,
            options: 0
        )

        let protection: Data.WritingOptions = [.atomic, .completeFileProtection]
        try keyData.write(to: identity.keyURL, options: protection)
        try authData.write(to: identity.authURL, options: protection)
        try rootData.write(to: identity.certificateURL, options: protection)
    }
}

enum IdentityError: LocalizedError {
    case generationFailed

    var errorDescription: String? {
        "Couldn't create the signing certificate."
    }
}
