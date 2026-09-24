import Testing
import Foundation
import CLISpec

/// CONVERSIONS.md ↔ cli-spec.yaml consistency (Spectra change `cli-spec-yaml`,
/// requirement "CONVERSIONS.md agrees with the specification";
/// PsychQuant/macdoc#72). The first cell of every data row of the
/// "Converter Details" table is a conversion `label` in the specification,
/// and vice versa.
struct CLISpecConversionsDocTests {

    /// First-cell labels of the data rows of the table under `## Converter Details`.
    static func converterDetailLabels(in markdown: String) -> [String] {
        let lines = markdown.components(separatedBy: "\n")
        guard let heading = lines.firstIndex(where: { $0.trimmingCharacters(in: .whitespaces) == "## Converter Details" }) else {
            return []
        }
        var tableLines: [String] = []
        for line in lines[(heading + 1)...] {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("|") {
                tableLines.append(trimmed)
            } else if !tableLines.isEmpty || trimmed.hasPrefix("#") {
                break   // end of the table, or the next heading before any table
            }
        }
        // Row 0 is the header, row 1 the |---| separator.
        return tableLines.dropFirst(2).compactMap { row in
            let cells = row.split(separator: "|", omittingEmptySubsequences: false)
            guard cells.count > 1 else { return nil }
            let label = cells[1].trimmingCharacters(in: .whitespaces)
            return label.isEmpty ? nil : label
        }
    }

    /// Labels present on only one side; both empty means the two agree.
    static func mismatch(docLabels: [String], specLabels: [String]) -> (onlyInDoc: [String], onlyInSpec: [String]) {
        let doc = Set(docLabels)
        let spec = Set(specLabels)
        return (docLabels.filter { !spec.contains($0) }, specLabels.filter { !doc.contains($0) })
    }

    static var specLabels: [String] {
        MacDocCLIMetadata.overlay.conversions.map(\.label)
    }

    @Test("CONVERSIONS.md Converter Details labels equal the specification's conversion labels")
    func conversionsDocMatchesSpec() throws {
        let url = CLITestHelper.repoRoot.appendingPathComponent("CONVERSIONS.md")
        let markdown = try String(contentsOf: url, encoding: .utf8)
        let docLabels = Self.converterDetailLabels(in: markdown)
        #expect(docLabels.count == Set(docLabels).count, "duplicate rows in CONVERSIONS.md: \(docLabels)")

        let (onlyInDoc, onlyInSpec) = Self.mismatch(docLabels: docLabels, specLabels: Self.specLabels)
        #expect(onlyInDoc.isEmpty, "CONVERSIONS.md 有、cli-spec.yaml 沒有的 conversion：\(onlyInDoc)")
        #expect(onlyInSpec.isEmpty, "cli-spec.yaml 有、CONVERSIONS.md 沒有的 conversion：\(onlyInSpec)")

        for label in ["Word → Marker", "HTML → PDF", "LaTeX → Word", "PDF → LaTeX", "UTF-8 text → Token count"] {
            #expect(docLabels.contains(label), "\(label) missing from CONVERSIONS.md")
            #expect(Self.specLabels.contains(label), "\(label) missing from the specification")
        }
    }

    @Test("the committed cli-spec.yaml carries every overlay conversion label")
    func committedSpecCarriesLabels() throws {
        let yaml = try String(contentsOf: CLISpecHarness.specURL, encoding: .utf8)
        for label in Self.specLabels {
            #expect(yaml.contains("\n  - label: \(YAMLEmitter.scalar(label))\n"), "\(label) not in cli-spec.yaml")
        }
    }

    @Test("an undocumented route is named as present only in the specification")
    func undocumentedRoute() {
        let markdown = """
        # macdoc Conversion Matrix

        ## Converter Details

        | Source → Target | Package | Status | Notes |
        |-----------------|---------|--------|-------|
        | Word → Markdown | `word-to-md-swift` | ✅ implemented | Layer 3 converter |
        | Obsolete → Thing | `gone-swift` | ✅ implemented | removed long ago |

        ### Next section

        | Not | Part |
        |-----|------|
        | Of | Table |
        """
        let docLabels = Self.converterDetailLabels(in: markdown)
        #expect(docLabels == ["Word → Markdown", "Obsolete → Thing"])
        let (onlyInDoc, onlyInSpec) = Self.mismatch(
            docLabels: docLabels, specLabels: ["Word → Markdown", "HTML → PDF"])
        #expect(onlyInDoc == ["Obsolete → Thing"])
        #expect(onlyInSpec == ["HTML → PDF"])
    }
}
