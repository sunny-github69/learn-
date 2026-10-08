import CoreVideo
import Foundation
import Vision

/// Works out who is talking from Zoom's own UI: in Gallery view Zoom draws a green border around the
/// active speaker's tile, and the participant's name sits in that tile's bottom-left corner.
/// Frames are analysed in memory about once a second and never saved.
final class SpeakerDetector {
    struct Sample {
        let time: TimeInterval  // seconds from the start of the meeting
        let name: String
    }

    private let sessionStart: Date
    private let onChange: @MainActor (String?) -> Void
    private let queue = DispatchQueue(label: "speaker-detector")
    private var samples: [Sample] = []
    private var current: String?

    init(sessionStart: Date, onChange: @escaping @MainActor (String?) -> Void) {
        self.sessionStart = sessionStart
        self.onChange = onChange
    }

    func process(_ frame: CVPixelBuffer) {
        let time = Date().timeIntervalSince(sessionStart)
        queue.async { [self] in
            let name = Self.activeTile(in: frame).flatMap { Self.readName(in: frame, tile: $0) }
            if let name { samples.append(Sample(time: time, name: name)) }
            guard name != current else { return }
            current = name
            Task { @MainActor [onChange] in onChange(name) }
        }
    }

    func finish() -> [Sample] {
        queue.sync { samples }
    }

    /// The name seen most often while a segment was spoken. Zoom moves the border about a second
    /// after someone starts talking, so the window reaches a little past the segment.
    static func dominantSpeaker(in samples: [Sample], from start: TimeInterval, to end: TimeInterval) -> String? {
        let names = samples.filter { $0.time >= start - 0.5 && $0.time <= end + 1.5 }.map(\.name)
        return Dictionary(names.map { ($0, 1) }, uniquingKeysWith: +).max { $0.value < $1.value }?.key
    }

    /// Bounding box (pixels, top-left origin) of the green active-speaker border, if one is on screen.
    /// Only long straight runs count, so green in someone's video (plants, shirts) is ignored.
    private static func activeTile(in frame: CVPixelBuffer) -> CGRect? {
        CVPixelBufferLockBaseAddress(frame, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(frame, .readOnly) }
        guard let base = CVPixelBufferGetBaseAddress(frame) else { return nil }
        let width = CVPixelBufferGetWidth(frame)
        let height = CVPixelBufferGetHeight(frame)
        let bytesPerRow = CVPixelBufferGetBytesPerRow(frame)
        let pixels = base.assumingMemoryBound(to: UInt8.self)

        var rowCounts = [Int](repeating: 0, count: height)
        var colCounts = [Int](repeating: 0, count: width)
        for y in 0..<height {
            let row = pixels + y * bytesPerRow
            for x in 0..<width {
                let p = row + x * 4  // BGRA
                let b = Int(p[0]), g = Int(p[1]), r = Int(p[2])
                if g > 160 && g - max(r, b) > 70 {
                    rowCounts[y] += 1
                    colCounts[x] += 1
                }
            }
        }
        let rows = rowCounts.indices.filter { rowCounts[$0] > width / 10 }
        let cols = colCounts.indices.filter { colCounts[$0] > height / 10 }
        guard let top = rows.first, let bottom = rows.last, let left = cols.first, let right = cols.last,
              bottom - top > height / 10, right - left > width / 10 else { return nil }
        return CGRect(x: left, y: top, width: right - left, height: bottom - top)
    }

    private static func readName(in frame: CVPixelBuffer, tile: CGRect) -> String? {
        let width = CGFloat(CVPixelBufferGetWidth(frame))
        let height = CGFloat(CVPixelBufferGetHeight(frame))
        // Bottom-left quarter of the tile; Vision wants it normalised with a bottom-left origin.
        let region = CGRect(x: tile.minX / width, y: (height - tile.maxY) / height,
                            width: tile.width * 0.75 / width, height: tile.height * 0.25 / height)
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = false
        request.regionOfInterest = region.intersection(CGRect(x: 0, y: 0, width: 1, height: 1))
        try? VNImageRequestHandler(cvPixelBuffer: frame).perform([request])

        // The name label is the lowest line of text in the tile; drop the mic icon read as a symbol.
        guard let text = request.results?.min(by: { $0.boundingBox.minY < $1.boundingBox.minY })?
            .topCandidates(1).first?.string else { return nil }
        let name = String(text.drop { !$0.isLetter }).trimmingCharacters(in: .whitespaces)
        return (2...40).contains(name.count) ? name : nil
    }
}
