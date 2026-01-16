import Foundation
import SwiftData

@Model
final class DiagnosticEvent {
    var timestamp: Date
    var area: String
    var severity: String
    var title: String
    var message: String

    var operation: String?
    var errorType: String?
    var errorDomain: String?
    var errorCode: Int?

    var appVersion: String?
    var appBuild: String?
    var osVersion: String?

    var contextJSON: String?
    var isDemoData: Bool = false

    init(
        timestamp: Date = Date(),
        area: String,
        severity: String,
        title: String,
        message: String,
        operation: String? = nil,
        errorType: String? = nil,
        errorDomain: String? = nil,
        errorCode: Int? = nil,
        appVersion: String? = nil,
        appBuild: String? = nil,
        osVersion: String? = nil,
        contextJSON: String? = nil,
        isDemoData: Bool = false
    ) {
        self.timestamp = timestamp
        self.area = area
        self.severity = severity
        self.title = title
        self.message = message
        self.operation = operation
        self.errorType = errorType
        self.errorDomain = errorDomain
        self.errorCode = errorCode
        self.appVersion = appVersion
        self.appBuild = appBuild
        self.osVersion = osVersion
        self.contextJSON = contextJSON
        self.isDemoData = isDemoData
    }
}

