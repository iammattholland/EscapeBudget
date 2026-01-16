import Foundation
import Testing
@testable import EscapeBudget

struct EncryptedExportServiceTests {
    @Test func encryptDecryptRoundTrip() throws {
        let plaintext = Data("hello-world".utf8)
        let password = "correct horse battery staple"

        let encrypted = try EncryptedExportService.encrypt(
            plaintext: plaintext,
            password: password,
            iterations: 10_000
        )
        let decrypted = try EncryptedExportService.decrypt(ciphertext: encrypted, password: password)

        #expect(decrypted == plaintext)
    }

    @Test func decryptWrongPasswordThrows() throws {
        let plaintext = Data("hello-world".utf8)
        let encrypted = try EncryptedExportService.encrypt(
            plaintext: plaintext,
            password: "password-1",
            iterations: 10_000
        )

        do {
            _ = try EncryptedExportService.decrypt(ciphertext: encrypted, password: "password-2")
            #expect(Bool(false), "Expected decrypt to throw with wrong password.")
        } catch {
            #expect(Bool(true))
        }
    }
}

