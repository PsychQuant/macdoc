import CoreGraphics
import Foundation
import Vision

struct DetectedBlock {
    var bbox: BoundingBox
    var type: BlockType
    var textPreview: String?
}

private struct RecognizedLine {
    var text: String
    var confidence: Float
    var bbox: BoundingBox

    var top: Double { bbox.y + bbox.height }
    var bottom: Double { bbox.y }
    var left: Double { bbox.x }
    var right: Double { bbox.x + bbox.width }
    var midX: Double { bbox.x + (bbox.width / 2.0) }
}

private struct LineCluster {
    var lines: [RecognizedLine]

    mutating func append(_ line: RecognizedLine) {
        lines.append(line)
    }

    var bbox: BoundingBox {
        let minX = lines.map(\.bbox.x).min() ?? 0
        let minY = lines.map(\.bbox.y).min() ?? 0
        let maxX = lines.map { $0.bbox.x + $0.bbox.width }.max() ?? 0
        let maxY = lines.map { $0.bbox.y + $0.bbox.height }.max() ?? 0
        return BoundingBox(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

    var textPreview: String {
        lines.map(\.text).joined(separator: "\n")
    }
}

enum BlockSegmentationError: LocalizedError {
    case invalidImageSize

    var errorDescription: String? {
        switch self {
        case .invalidImageSize:
            return "頁面圖片尺寸無效，無法做區塊切分。"
        }
    }
}

struct BlockSegmenter {
    var minimumConfidence: Float = 0.35
    var verticalGapThreshold: Double = 18
    var horizontalOverlapThreshold: Double = 0.2
    var blockPadding: Double = 8

    func segment(pageImage: CGImage, pageWidth: Double, pageHeight: Double) throws -> [DetectedBlock] {
        guard pageImage.width > 0, pageImage.height > 0 else {
            throw BlockSegmentationError.invalidImageSize
        }

        let request = VNRecognizeTextRequest()
        request.recognitionLanguages = ["en-US"]
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = false
        request.minimumTextHeight = 0.008

        let handler = VNImageRequestHandler(cgImage: pageImage, options: [:])
        try handler.perform([request])

        let observations = request.results ?? []
        let lines = observations.compactMap { observation -> RecognizedLine? in
            guard let candidate = observation.topCandidates(1).first else {
                return nil
            }

            let text = candidate.string.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty, candidate.confidence >= minimumConfidence else {
                return nil
            }

            let bbox = BoundingBox(
                x: Double(observation.boundingBox.origin.x) * pageWidth,
                y: Double(observation.boundingBox.origin.y) * pageHeight,
                width: Double(observation.boundingBox.size.width) * pageWidth,
                height: Double(observation.boundingBox.size.height) * pageHeight
            )

            return RecognizedLine(text: text, confidence: candidate.confidence, bbox: bbox)
        }
        .sorted {
            if abs($0.top - $1.top) > 1 {
                return $0.top > $1.top
            }
            return $0.left < $1.left
        }

        var clusters: [LineCluster] = []
        for line in lines {
            if let lastIndex = clusters.indices.last, shouldMerge(line: line, into: clusters[lastIndex]) {
                clusters[lastIndex].append(line)
                continue
            }

            clusters.append(LineCluster(lines: [line]))
        }

        return clusters.enumerated().map { _, cluster in
            let padded = paddedBox(cluster.bbox, pageWidth: pageWidth, pageHeight: pageHeight)
            let preview = cluster.textPreview
            return DetectedBlock(
                bbox: padded,
                type: classify(text: preview, bbox: padded, pageHeight: pageHeight, lineCount: cluster.lines.count),
                textPreview: preview
            )
        }
    }

    private func shouldMerge(line: RecognizedLine, into cluster: LineCluster) -> Bool {
        guard let previous = cluster.lines.last else {
            return true
        }

        let verticalGap = previous.bottom - line.top
        let overlap = horizontalOverlap(lhs: previous.bbox, rhs: line.bbox)
        let leftDelta = abs(previous.left - line.left)
        let centerDelta = abs(previous.midX - line.midX)

        if verticalGap < -6 {
            return false
        }

        return verticalGap <= max(verticalGapThreshold, previous.bbox.height * 1.4)
            && (overlap >= horizontalOverlapThreshold || leftDelta <= 48 || centerDelta <= 80)
    }

    private func horizontalOverlap(lhs: BoundingBox, rhs: BoundingBox) -> Double {
        let left = max(lhs.x, rhs.x)
        let right = min(lhs.x + lhs.width, rhs.x + rhs.width)
        let overlap = max(0, right - left)
        let base = min(lhs.width, rhs.width)
        guard base > 0 else { return 0 }
        return overlap / base
    }

    private func paddedBox(_ bbox: BoundingBox, pageWidth: Double, pageHeight: Double) -> BoundingBox {
        let minX = max(0, bbox.x - blockPadding)
        let minY = max(0, bbox.y - blockPadding)
        let maxX = min(pageWidth, bbox.x + bbox.width + blockPadding)
        let maxY = min(pageHeight, bbox.y + bbox.height + blockPadding)
        return BoundingBox(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

    private func classify(text: String, bbox: BoundingBox, pageHeight: Double, lineCount: Int) -> BlockType {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = trimmed.lowercased()
        let symbolCount = trimmed.filter { "=+-*/^_[](){}".contains($0) }.count

        if lower.hasPrefix("figure ") || lower.hasPrefix("fig. ") || lower.hasPrefix("table ") {
            return .caption
        }
        if lower.hasPrefix("theorem") || lower.hasPrefix("lemma") || lower.hasPrefix("proposition") {
            return .theorem
        }
        if lower.hasPrefix("proof") {
            return .proof
        }
        if bbox.y < pageHeight * 0.12 && lineCount <= 3 {
            return .footnote
        }
        if lineCount <= 3 && symbolCount >= 2 {
            return .equation
        }
        return .text
    }
}
