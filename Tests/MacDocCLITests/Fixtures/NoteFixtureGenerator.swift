// NoteFixtureGenerator — covers PsychQuant/macdoc#100 Plan-tier delivery.
//
// Synthesizes a minimal valid Notability `.note` archive at a target URL.
// Used by CLITestHelper.noteFixture() so Note→HTML / Note→PDF smoke tests
// can run in CI without a committed binary blob.
//
// Strategy A (synthetic generator) per the Plan-tier approval — see
// PsychQuant/macdoc#100 issue body and Implementation Plan comment.
//
// Privacy: this generator produces synthetic content only. No personal
// data, no real Apple Notes content. Per CLAUDE.md global rule
// "Git 隱私邊界 — 第三方逐字內容不進 remote".

import Foundation

public enum NoteFixtureGenerator {

    public enum GeneratorError: Error {
        case zipCommandFailed(exitCode: Int32, stderr: String)
        case missingPlistData
    }

    // Pre-encoded minimal Session.plist (Notability GLKeyedArchiver-compatible
    // shape — NoteCore.NoteParser accepts both NSKeyedArchiver and
    // GLKeyedArchiver formats per source comment at line 296).
    //
    // Object graph:
    //   $top.root → UID(1) → root object with `richText`
    //   richText (UID 2) → has `pageLayoutArray`
    //   pageLayoutArray (UID 3) → NSArray-shaped with one element → pageCount=1
    //
    // Omitted (parser handles absence): Handwriting Overlay (empty strokes),
    // contentPlaybackEventManager (empty timeline),
    // NBNoteTakingSessionDocumentPaperLayoutModelKey (default pageWidth=583.8).
    //
    // Generated via Python plistlib + plistlib.UID. See
    // openspec/changes/archive/<future>-note-fixture-generator/ for the
    // regeneration script if this needs updating.
    private static let sessionPlistBase64 = "YnBsaXN0MDDUAQIDBAUGICNZJGFyY2hpdmVyWCRvYmplY3RzVCR0b3BYJHZlcnNpb25fEA9OU0tleWVkQXJjaGl2ZXKnBwgNERYXHVUkbnVsbNIJCgsMViRjbGFzc1hyaWNoVGV4dIAFgALSCQ4PEF8QD3BhZ2VMYXlvdXRBcnJheYAFgAPSCRITFFpOUy5vYmplY3RzgAahFYAEVnBhZ2UtMdIYGRobWCRjbGFzc2VzWiRjbGFzc25hbWWiGxxeTm90YWJpbGl0eVJvb3RYTlNPYmplY3TSGBkeH6IfHFdOU0FycmF50SEiVHJvb3SAARIAAYagCBEbJCkyRExSV15naWtwgoSGi5aYmpyjqLG8v87X3N/n6u/xAAAAAAAAAQEAAAAAAAAAJAAAAAAAAAAAAAAAAAAAAPY="

    public static func generate(at url: URL) throws {
        guard let sessionData = Data(base64Encoded: sessionPlistBase64) else {
            throw GeneratorError.missingPlistData
        }

        let stagingRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("note-fixture-staging-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: stagingRoot) }

        try FileManager.default.createDirectory(at: stagingRoot, withIntermediateDirectories: true)

        // Inner note directory — NoteCore.NoteParser uses this as the note's
        // title (parser line 277). Keep it obviously synthetic.
        let innerDirName = "macdoc-fixture"
        let innerDir = stagingRoot.appendingPathComponent(innerDirName)
        try FileManager.default.createDirectory(at: innerDir, withIntermediateDirectories: true)

        // Write Session.plist — the only required file.
        try sessionData.write(to: innerDir.appendingPathComponent("Session.plist"))

        // Empty subdirectories — parser tolerates missing OR empty.
        // We omit them to keep the .note minimal.

        // ZIP via /usr/bin/zip — matches existing FixtureManager pattern.
        // Remove any existing file at the target URL first; /usr/bin/zip
        // refuses to overwrite without -o flag, but we want clean creation.
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }

        let zipProcess = Process()
        zipProcess.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
        zipProcess.arguments = ["-r", "-q", url.path, innerDirName]
        zipProcess.currentDirectoryURL = stagingRoot
        let stderrPipe = Pipe()
        zipProcess.standardError = stderrPipe
        try zipProcess.run()
        zipProcess.waitUntilExit()

        if zipProcess.terminationStatus != 0 {
            let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
            let stderrText = String(data: stderrData, encoding: .utf8) ?? "(no stderr)"
            throw GeneratorError.zipCommandFailed(
                exitCode: zipProcess.terminationStatus,
                stderr: stderrText
            )
        }
    }
}
