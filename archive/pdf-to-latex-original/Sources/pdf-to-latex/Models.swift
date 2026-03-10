import Foundation

struct ProjectManifest: Codable, Sendable {
    var schemaVersion: Int
    var createdAt: String
    var updatedAt: String
    var projectName: String
    var sourcePDF: String
    var projectRoot: String
    var pages: [PageRecord]
    var blocks: [BlockRecord]
}

struct PageRecord: Codable, Sendable {
    var number: Int
    var width: Double
    var height: Double
    var rotation: Int
    var renderedImagePath: String?
    var renderedDPI: Double?
}

struct BlockRecord: Codable, Sendable {
    var id: String
    var page: Int
    var type: BlockType
    var status: BlockStatus
    var bbox: BoundingBox
    var imagePath: String?
    var latexPath: String?
    var textPreview: String?
    var notes: String?
    var attemptCount: Int?
    var lastAttemptAt: String?
    var completedAt: String?
    var lastModel: String?
    var lastReasoningEffort: String?
    var lastTimeoutSeconds: Double?
}

struct BoundingBox: Codable, Sendable {
    var x: Double
    var y: Double
    var width: Double
    var height: Double
}

enum BlockType: String, Codable, CaseIterable, Sendable {
    case text
    case equation
    case table
    case figure
    case caption
    case footnote
    case theorem
    case proof
    case unknown
}

enum BlockStatus: String, Codable, CaseIterable, Sendable {
    case pending
    case segmented
    case queued
    case transcribing
    case transcribed
    case verified
    case fallbackImage = "fallback_image"
    case failed
}

extension BlockStatus {
    var isRunnableWithoutOverwrite: Bool {
        switch self {
        case .segmented, .queued, .failed:
            return true
        default:
            return false
        }
    }

    var countsAsSuccess: Bool {
        self == .transcribed || self == .fallbackImage
    }
}
