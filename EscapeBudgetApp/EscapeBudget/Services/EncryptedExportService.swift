import CommonCrypto
import CryptoKit
import Foundation
import Security

enum EncryptedExportService {
    enum EncryptedExportError: LocalizedError {
        case invalidPassword
        case randomBytesFailed(OSStatus)
        case keyDerivationFailed(Int32)
        case invalidContainer

        var errorDescription: String? {
            switch self {
            case .invalidPassword:
                return "Invalid password."
            case .randomBytesFailed:
                return "Unable to generate secure random bytes."
            case .keyDerivationFailed:
                return "Unable to derive encryption key."
            case .invalidContainer:
                return "Invalid encrypted export file."
            }
        }
    }

    private static let magic = Data([0x4D, 0x4D, 0x45, 0x31]) // "MME1"
    private static let saltLength = 16
    private static let keyLength = 32
    private static let defaultIterations = 200_000

    /// Encrypts data with AES-256-GCM using a PBKDF2-derived key (HMAC-SHA256).
    /// File format (binary):
    /// - 4 bytes: magic "MME1"
    /// - 4 bytes: iterations (UInt32, big-endian)
    /// - 16 bytes: salt
    /// - 4 bytes: combined length (UInt32, big-endian)
    /// - N bytes: AES.GCM sealedBox.combined (nonce + ciphertext + tag)
    static func encrypt(
        plaintext: Data,
        password: String,
        iterations: Int = defaultIterations
    ) throws -> Data {
        guard !password.isEmpty else { throw EncryptedExportError.invalidPassword }

        let salt = try randomBytes(count: saltLength)
        let key = try deriveKey(password: password, salt: salt, iterations: iterations)

        let sealedBox = try AES.GCM.seal(plaintext, using: key)
        guard let combined = sealedBox.combined else { throw EncryptedExportError.invalidContainer }

        var container = Data()
        container.append(magic)
        container.append(UInt32(iterations).bigEndianData)
        container.append(salt)
        container.append(UInt32(combined.count).bigEndianData)
        container.append(combined)
        return container
    }

    static func decrypt(ciphertext: Data, password: String) throws -> Data {
        guard !password.isEmpty else { throw EncryptedExportError.invalidPassword }

        var offset = 0
        guard ciphertext.count >= 4 + 4 + saltLength + 4 else { throw EncryptedExportError.invalidContainer }

        let magicRange = offset..<(offset + 4)
        guard ciphertext.subdata(in: magicRange) == magic else { throw EncryptedExportError.invalidContainer }
        offset += 4

        let iterations = Int(try readUInt32(from: ciphertext, offset: &offset))
        let saltRange = offset..<(offset + saltLength)
        let salt = ciphertext.subdata(in: saltRange)
        offset += saltLength

        let combinedLength = Int(try readUInt32(from: ciphertext, offset: &offset))
        let combinedRange = offset..<(offset + combinedLength)
        guard combinedRange.upperBound <= ciphertext.count else { throw EncryptedExportError.invalidContainer }
        let combined = ciphertext.subdata(in: combinedRange)

        let key = try deriveKey(password: password, salt: salt, iterations: iterations)
        let sealedBox = try AES.GCM.SealedBox(combined: combined)
        return try AES.GCM.open(sealedBox, using: key)
    }

    private static func deriveKey(password: String, salt: Data, iterations: Int) throws -> SymmetricKey {
        guard iterations > 0 else { throw EncryptedExportError.keyDerivationFailed(-1) }

        let passwordData = Data(password.utf8)
        var derivedKey = Data(repeating: 0, count: keyLength)

        let result: Int32 = derivedKey.withUnsafeMutableBytes { derivedBytes in
            salt.withUnsafeBytes { saltBytes in
                passwordData.withUnsafeBytes { passwordBytes in
                    CCKeyDerivationPBKDF(
                        CCPBKDFAlgorithm(kCCPBKDF2),
                        passwordBytes.bindMemory(to: Int8.self).baseAddress,
                        passwordData.count,
                        saltBytes.bindMemory(to: UInt8.self).baseAddress,
                        salt.count,
                        CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256),
                        UInt32(iterations),
                        derivedBytes.bindMemory(to: UInt8.self).baseAddress,
                        keyLength
                    )
                }
            }
        }

        guard result == kCCSuccess else { throw EncryptedExportError.keyDerivationFailed(result) }
        return SymmetricKey(data: derivedKey)
    }

    private static func randomBytes(count: Int) throws -> Data {
        var bytes = [UInt8](repeating: 0, count: count)
        let status = SecRandomCopyBytes(kSecRandomDefault, count, &bytes)
        guard status == errSecSuccess else { throw EncryptedExportError.randomBytesFailed(status) }
        return Data(bytes)
    }

    private static func readUInt32(from data: Data, offset: inout Int) throws -> UInt32 {
        let end = offset + 4
        guard end <= data.count else { throw EncryptedExportError.invalidContainer }
        var value: UInt32 = 0
        for byte in data[offset..<end] {
            value = (value << 8) | UInt32(byte)
        }
        offset = end
        return value
    }
}

private extension UInt32 {
    var bigEndianData: Data {
        withUnsafeBytes(of: bigEndian) { Data($0) }
    }
}
