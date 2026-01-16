import Foundation

enum SensitiveFileProtection {
    enum ValidationError: LocalizedError {
        case unsupportedFileType
        case fileTooLarge(maxMB: Int)
        case notAFile
        case emptyFile

        var errorDescription: String? {
            switch self {
            case .unsupportedFileType:
                return "Unsupported file type. Please choose a CSV (.csv/.txt/.tsv) or Escape Budget export (.ebexport)."
            case .fileTooLarge(let maxMB):
                return "File is too large. Please choose a file smaller than \(maxMB) MB."
            case .notAFile:
                return "That selection isn’t a file. Please choose a valid file."
            case .emptyFile:
                return "That file is empty."
            }
        }
    }

    static func apply(to url: URL, protection: FileProtectionType = .completeUnlessOpen) {
        try? FileManager.default.setAttributes([.protectionKey: protection], ofItemAtPath: url.path)

        applyBackupExclusion(to: url, excluded: true)
    }

    static func apply(to url: URL, protection: FileProtectionType = .completeUnlessOpen, excludeFromBackup: Bool) {
        try? FileManager.default.setAttributes([.protectionKey: protection], ofItemAtPath: url.path)
        applyBackupExclusion(to: url, excluded: excludeFromBackup)
    }

    static func applyBackupExclusion(to url: URL, excluded: Bool) {
        var values = URLResourceValues()
        values.isExcludedFromBackup = excluded
        var mutableURL = url
        try? mutableURL.setResourceValues(values)
    }

    static func validateImportableFile(at url: URL, maxBytes: Int64, allowedExtensions: Set<String>) throws {
        let ext = url.pathExtension.lowercased()
        // If the user picked a file with no extension (common), allow it and rely on deeper parsing validation.
        if !ext.isEmpty, !allowedExtensions.contains(ext) {
            throw ValidationError.unsupportedFileType
        }

        let values = try url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
        guard values.isRegularFile == true else {
            throw ValidationError.notAFile
        }

        let size = Int64(values.fileSize ?? 0)
        if size <= 0 {
            throw ValidationError.emptyFile
        }
        if size > maxBytes {
            throw ValidationError.fileTooLarge(maxMB: Int(maxBytes / 1024 / 1024))
        }
    }
}
