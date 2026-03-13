// Sources/CheBiblatexMCPCore/APADataModel.swift
// APA 7 data model — hardcoded from apa.dbx (Philip Kime, v9.17)
// + biblatex standard entry types.

import Foundation

public struct APADataModel {

    // MARK: - Entry Types

    /// APA-specific entry types declared in apa.dbx
    public static let apaEntryTypes: Set<String> = [
        "PRESENTATION", "CONSTITUTION", "LEGMATERIAL",
        "LEGADMINMATERIAL", "NAMEONLY"
    ]

    /// Standard biblatex entry types commonly used in APA style
    public static let standardEntryTypes: Set<String> = [
        "ARTICLE", "BOOK", "INBOOK", "INCOLLECTION", "INPROCEEDINGS",
        "PROCEEDINGS", "COLLECTION", "REFERENCE", "INREFERENCE",
        "REPORT", "THESIS", "PHDTHESIS", "MASTERSTHESIS",
        "ONLINE", "UNPUBLISHED", "MANUAL", "PATENT", "PERIODICAL",
        "MISC", "VIDEO", "AUDIO", "IMAGE", "SOFTWARE", "DATASET",
        "HARDWARE", "JURISDICTION", "LEGISLATION", "LEGAL"
    ]

    /// All valid entry types
    public static let allEntryTypes: Set<String> =
        apaEntryTypes.union(standardEntryTypes)

    // MARK: - Valid Fields per Entry Type (from apa.dbx)

    /// Fields declared in apa.dbx for @PRESENTATION
    public static let presentationFields: Set<String> = [
        "ADDENDUM", "AUTHOR", "BOOKSUBTITLE", "BOOKTITLE", "BOOKTITLEADDON",
        "CHAPTER", "DOI", "EDITOR", "EDITORTYPE", "EPRINT", "EPRINTCLASS",
        "EPRINTTYPE", "EVENTDAY", "EVENTENDDAY", "EVENTENDHOUR",
        "EVENTENDMINUTE", "EVENTENDMONTH", "EVENTENDSEASON", "EVENTENDSECOND",
        "EVENTENDTIMEZONE", "EVENTENDYEAR", "EVENTHOUR", "EVENTMINUTE",
        "EVENTMONTH", "EVENTSEASON", "EVENTSECOND", "EVENTTIMEZONE",
        "EVENTYEAR", "EVENTTITLE", "EVENTTITLEADDON", "ISBN", "LANGUAGE",
        "LOCATION", "MAINSUBTITLE", "MAINTITLE", "MAINTITLEADDON", "NOTE",
        "NUMBER", "ORGANIZATION", "PAGES", "PART", "PUBLISHER", "PUBSTATE",
        "SERIES", "SUBTITLE", "TITLE", "TITLEADDON", "VENUE", "VOLUME",
        "VOLUMES", "DATE", "EVENTDATE", "URL", "URLDATE",
        // Common universal fields
        "KEYWORDS", "ANNOTATION", "ABSTRACT", "WITH",
        "NARRATOR", "EXECPRODUCER", "EXECDIRECTOR"
    ]

    /// Fields declared in apa.dbx for @REPORT
    public static let reportFields: Set<String> = [
        "ADDENDUM", "AUTHOR", "AUTHORTYPE", "CHAPTER", "DOI", "EPRINT",
        "EPRINTCLASS", "EPRINTTYPE", "INSTITUTION", "ISRN", "LANGUAGE",
        "LOCATION", "NOTE", "NUMBER", "PAGES", "PAGETOTAL", "PUBSTATE",
        "SUBTITLE", "TITLE", "TITLEADDON", "TYPE", "VERSION", "DATE",
        "URL", "URLDATE", "KEYWORDS", "ANNOTATION", "ABSTRACT"
    ]

    /// Fields for @CONSTITUTION
    public static let constitutionFields: Set<String> = [
        "ARTICLE", "SECTION", "AMENDMENT", "TITLE", "DATE"
    ]

    /// Fields for @LEGMATERIAL
    public static let legmaterialFields: Set<String> = [
        "SOURCE", "TITLE", "DATE", "NUMBER", "URL"
    ]

    /// Fields for @LEGADMINMATERIAL
    public static let legadminmaterialFields: Set<String> = [
        "CITATION", "SOURCE", "TITLE", "DATE", "NUMBER", "URL"
    ]

    // MARK: - Required Fields (from apa.dbx constraints + APA 7 conventions)

    /// Mandatory fields — error if missing
    public static let requiredFields: [String: [String]] = [
        "ARTICLE":        ["AUTHOR", "TITLE", "JOURNALTITLE", "DATE"],
        "BOOK":           ["AUTHOR", "TITLE", "DATE"],
        "INBOOK":         ["AUTHOR", "TITLE", "BOOKTITLE", "DATE"],
        "INCOLLECTION":   ["AUTHOR", "TITLE", "BOOKTITLE", "DATE"],
        "INPROCEEDINGS":  ["AUTHOR", "TITLE", "BOOKTITLE", "DATE"],
        "REPORT":         ["AUTHOR", "TITLE", "DATE"],
        "PRESENTATION":   ["AUTHOR", "TITLE", "DATE"],
        "THESIS":         ["AUTHOR", "TITLE", "INSTITUTION", "DATE"],
        "PHDTHESIS":      ["AUTHOR", "TITLE", "INSTITUTION", "DATE"],
        "MASTERSTHESIS":  ["AUTHOR", "TITLE", "INSTITUTION", "DATE"],
        "ONLINE":         ["TITLE", "DATE"],  // AUTHOR or EDITOR recommended
        "VIDEO":          ["TITLE", "DATE"],
        "AUDIO":          ["TITLE", "DATE"],
        "SOFTWARE":       ["TITLE", "DATE"],
        "DATASET":        ["TITLE", "DATE"],
    ]

    /// Recommended fields — warning if missing
    public static let recommendedFields: [String: [String]] = [
        "ARTICLE":        ["DOI", "VOLUME", "PAGES"],
        "BOOK":           ["PUBLISHER"],
        "INCOLLECTION":   ["EDITOR", "PUBLISHER", "PAGES"],
        "INPROCEEDINGS":  ["PUBLISHER"],
        "REPORT":         ["INSTITUTION", "NUMBER"],
        "PRESENTATION":   ["EVENTTITLE", "VENUE"],
        "THESIS":         ["TYPE"],
        "ONLINE":         ["URL", "AUTHOR"],
        "VIDEO":          ["PUBLISHER"],
    ]

    /// Context-aware recommended fields for PRESENTATION entries.
    /// - Symposium (has MAINTITLE): needs MAINTITLEADDON, EDITORA; TITLEADDON not expected.
    /// - Standalone (no MAINTITLE): needs TITLEADDON (e.g. "Poster presentation").
    public static func presentationRecommendedFields(hasMainTitle: Bool) -> [String] {
        if hasMainTitle {
            return ["EVENTTITLE", "VENUE", "MAINTITLEADDON", "EDITORA"]
        } else {
            return ["EVENTTITLE", "VENUE", "TITLEADDON"]
        }
    }

    // MARK: - Field Aliases (non-APA → APA biblatex mapping)

    /// Maps commonly used non-biblatex field names to correct APA biblatex equivalents.
    public static let fieldAliases: [String: String] = [
        // BibTeX classic → biblatex
        "JOURNAL":       "JOURNALTITLE",
        "ADDRESS":       "LOCATION",
        "SCHOOL":        "INSTITUTION",
        "YEAR":          "DATE",

        // Common mistakes
        "CONFERENCE":    "EVENTTITLE",
        "MEETING":       "EVENTTITLE",
        "PLACE":         "VENUE",
        "CITY":          "LOCATION",
        "HOWPUBLISHED":  "NOTE",    // or URL if it contains a URL

        // Zotero export quirks
        "MEETINGNAME":   "EVENTTITLE",
        "CONFERENCENAME": "EVENTTITLE",
        "PRESENTATIONTYPE": "TITLEADDON",
    ]

    // MARK: - Entry Type Aliases (non-standard → standard APA biblatex)

    /// Maps legacy/non-standard entry types to APA biblatex equivalents.
    public static let entryTypeAliases: [String: String] = [
        // BibTeX classic types → biblatex
        "CONFERENCE":     "INPROCEEDINGS",
        "TECHREPORT":     "REPORT",
        "BOOKLET":        "BOOK",
        "INBOOK":         "INCOLLECTION",  // in biblatex-apa, INBOOK ≈ INCOLLECTION

        // Common conversions
        "WEBPAGE":        "ONLINE",
        "ELECTRONIC":     "ONLINE",
        "WWW":            "ONLINE",
        "MOVIE":          "VIDEO",
        "FILM":           "VIDEO",
    ]

    // MARK: - Entry Type Upgrade Rules

    /// Conditions under which an entry type should be changed.
    /// Returns (suggestedType, reason) or nil.
    public static func suggestTypeUpgrade(
        currentType: String,
        fields: OrderedDict
    ) -> (newType: String, reason: String)? {
        let type = currentType.uppercased()
        let fieldKeys = Set(fields.keys.map { $0.uppercased() })

        // MISC with URL → ONLINE
        if type == "MISC" && fieldKeys.contains("URL") && !fieldKeys.contains("DOI") {
            return ("ONLINE", "MISC with URL should use @ONLINE")
        }

        // INPROCEEDINGS with EVENTTITLE → PRESENTATION
        if type == "INPROCEEDINGS" && fieldKeys.contains("EVENTTITLE")
            && !fieldKeys.contains("BOOKTITLE") {
            return ("PRESENTATION",
                    "INPROCEEDINGS with EVENTTITLE (no BOOKTITLE) is better as @PRESENTATION")
        }

        // PHDTHESIS/MASTERSTHESIS → THESIS with type field
        if type == "PHDTHESIS" {
            return ("THESIS", "Use @THESIS with type={phdthesis} for APA biblatex")
        }
        if type == "MASTERSTHESIS" {
            return ("THESIS", "Use @THESIS with type={mathesis} for APA biblatex")
        }

        return nil
    }

    // MARK: - Date Patterns

    /// Valid DATE field patterns per APA 7 / biblatex
    public static let datePatterns: [(pattern: String, description: String)] = [
        (#"^\d{4}$"#,                      "Year only: 2020"),
        (#"^\d{4}-\d{2}$"#,               "Year-month: 2020-03"),
        (#"^\d{4}-\d{2}-\d{2}$"#,          "Full date: 2020-03-15"),
        (#"^\d{4}-\d{2}/\d{4}-\d{2}$"#,    "Date range: 2020-03/2020-04"),
        (#"^\d{4}-\d{2}-\d{2}/\d{4}-\d{2}-\d{2}$"#, "Date range: 2020-03-15/2020-03-20"),
        (#"^\d{4}-2[1-4]$"#,               "Season: 2020-21 (Spring)"),
        (#"^\d{4}-2[1-4]/\d{4}-2[1-4]$"#,  "Season range: 2020-21/2020-22"),
        (#"^\d{4}[a-z]$"#,                 "Disambiguated: 2020a"),
    ]

    /// Season codes used in biblatex date fields
    public static let seasonCodes: [String: String] = [
        "21": "Spring", "22": "Summer",
        "23": "Fall/Autumn", "24": "Winter"
    ]

    // MARK: - APA Section Classification

    /// APA 7 manual section info.
    public struct APASection: Equatable, CustomStringConvertible {
        public let number: String      // e.g. "10.1"
        public let title: String       // e.g. "Periodicals"
        public let chapter: Int        // 10 or 11

        public var description: String { "APA \(number) — \(title)" }
    }

    /// All APA 7 reference sections (Chapter 10 & 11).
    public static let sections: [APASection] = [
        APASection(number: "10.1",  title: "Periodicals", chapter: 10),
        APASection(number: "10.2",  title: "Books and Reference Works", chapter: 10),
        APASection(number: "10.3",  title: "Edited Book Chapters and Entries in Reference Works", chapter: 10),
        APASection(number: "10.4",  title: "Reports and Gray Literature", chapter: 10),
        APASection(number: "10.5",  title: "Conference Sessions and Presentations", chapter: 10),
        APASection(number: "10.6",  title: "Dissertations and Theses", chapter: 10),
        APASection(number: "10.7",  title: "Reviews", chapter: 10),
        APASection(number: "10.8",  title: "Unpublished Works and Informally Published Works", chapter: 10),
        APASection(number: "10.9",  title: "Data Sets", chapter: 10),
        APASection(number: "10.10", title: "Computer Software, Mobile Apps, Apparatuses, and Equipment", chapter: 10),
        APASection(number: "10.11", title: "Tests, Scales, and Inventories", chapter: 10),
        APASection(number: "10.12", title: "Audiovisual Works", chapter: 10),
        APASection(number: "10.13", title: "Audio Works", chapter: 10),
        APASection(number: "10.14", title: "Visual Works", chapter: 10),
        APASection(number: "10.15", title: "Social Media", chapter: 10),
        APASection(number: "10.16", title: "Webpages and Websites", chapter: 10),
        APASection(number: "11.4",  title: "Cases or Court Decisions", chapter: 11),
        APASection(number: "11.5",  title: "Statutes (Laws and Acts)", chapter: 11),
        APASection(number: "11.6",  title: "Legislative Materials", chapter: 11),
        APASection(number: "11.7",  title: "Administrative and Executive Materials", chapter: 11),
        APASection(number: "11.8",  title: "Patents", chapter: 11),
        APASection(number: "11.9",  title: "Constitutions and Charters", chapter: 11),
        APASection(number: "11.10", title: "Treaties and International Conventions", chapter: 11),
    ]

    /// Classify a BibEntry into the most likely APA 7 manual section.
    /// Uses entry type and field heuristics — does NOT rely on the entry key.
    public static func classifySection(entry: BibEntry) -> APASection {
        let type = entry.entryType.uppercased()
        let fieldKeys = Set(entry.fields.keys.map { $0.uppercased() })

        // --- Chapter 11: Legal references ---
        switch type {
        case "JURISDICTION":
            return section("11.4")
        case "LEGISLATION":
            // 11.5 Statutes: enacted laws/acts
            // 11.6 Legislative Materials: bills, resolutions, hearings
            // Heuristic: bills have H.R./S./H.J.Res in LOCATION or title
            if let location = caseInsensitiveField(entry, "LOCATION") {
                let lower = location.lowercased()
                if lower.contains("h.r") || lower.contains("s.") && lower.contains("cong") {
                    return section("11.6")
                }
            }
            if let title = entry.title?.lowercased() {
                if title.contains("bill") || title.contains("improvement act")
                    || title.contains("resolution") {
                    return section("11.6")
                }
            }
            return section("11.5")
        case "LEGMATERIAL":
            return section("11.6")
        case "LEGADMINMATERIAL":
            return section("11.7")
        case "PATENT":
            return section("11.8")
        case "CONSTITUTION":
            return section("11.9")
        case "LEGAL":
            return section("11.10")
        default:
            break
        }

        // --- Chapter 10: Standard references ---
        switch type {
        case "ARTICLE", "PERIODICAL":
            // 10.7 Reviews: only if RELATEDTYPE is "reviewof"
            if let relType = caseInsensitiveField(entry, "RELATEDTYPE"),
               relType.lowercased() == "reviewof" {
                return section("10.7")
            }
            // 10.1 Periodicals (journals, magazines, newspapers)
            return section("10.1")

        case "BOOK", "COLLECTION", "REFERENCE":
            return section("10.2")

        case "INBOOK", "INCOLLECTION", "INREFERENCE":
            return section("10.3")

        case "REPORT":
            return section("10.4")

        case "PRESENTATION", "INPROCEEDINGS", "PROCEEDINGS":
            return section("10.5")

        case "THESIS", "PHDTHESIS", "MASTERSTHESIS":
            return section("10.6")

        case "UNPUBLISHED":
            return section("10.8")

        case "DATASET":
            return section("10.9")

        case "HARDWARE":
            return section("10.10")

        case "SOFTWARE":
            return classifySoftware(entry: entry, fieldKeys: fieldKeys)

        case "MANUAL":
            return classifyManual(entry: entry)

        case "VIDEO":
            // 10.7 if it's a reviewed work; 10.12 otherwise
            if fieldKeys.contains("RELATED") || fieldKeys.contains("RELATEDTYPE") {
                return section("10.7")
            }
            return section("10.12")

        case "AUDIO":
            return section("10.13")

        case "IMAGE":
            return section("10.14")

        case "ONLINE":
            return classifyOnline(entry: entry, fieldKeys: fieldKeys)

        case "MISC":
            if fieldKeys.contains("JOURNALTITLE") { return section("10.1") }
            if fieldKeys.contains("URL") { return section("10.16") }
            return section("10.16")

        default:
            if fieldKeys.contains("JOURNALTITLE") { return section("10.1") }
            if fieldKeys.contains("BOOKTITLE") { return section("10.3") }
            return section("10.16")
        }
    }

    // MARK: - Classification Helpers

    /// Classify @SOFTWARE: 10.10 (apps/software) vs 10.11 (tests/scales/inventories).
    private static func classifySoftware(entry: BibEntry, fieldKeys: Set<String>) -> APASection {
        // ENTRYSUBTYPE "Database record" → 10.11 (test from database like PsycTESTS)
        if let subtype = caseInsensitiveField(entry, "ENTRYSUBTYPE") {
            let lower = subtype.lowercased()
            if lower.contains("database") || lower.contains("record") {
                return section("10.11")
            }
        }
        // Publisher in test databases → 10.11
        if let pub = caseInsensitiveField(entry, "PUBLISHER") {
            let lower = pub.lowercased()
            if lower.contains("psyctests") || lower.contains("ets testlink") {
                return section("10.11")
            }
        }
        // Title contains test/scale/questionnaire/inventory/IAT → 10.11
        if let title = entry.title?.lowercased() {
            if title.contains("questionnaire") || title.contains("inventory")
                || title.contains("iat") || title.contains("scale") {
                return section("10.11")
            }
        }
        return section("10.10")
    }

    /// Classify @MANUAL: 10.11 (test manual) vs 10.2 (general manual/book).
    private static func classifyManual(entry: BibEntry) -> APASection {
        let combined = [entry.title, entry.fields["SUBTITLE"] ?? entry.fields["subtitle"]]
            .compactMap { $0?.lowercased() }
            .joined(separator: " ")
        // Reference books with EDITION (DSM, ICD) are 10.2, not 10.11
        if entry.fields.keys.contains(where: { $0.uppercased() == "EDITION" }) {
            return section("10.2")
        }
        // Test/scale manuals — subtitle "Technical Manual" or title with test keywords
        if combined.contains("inventory") || combined.contains("personality")
            || combined.contains("mmpi") || combined.contains("scale")
            || (combined.contains("manual") && combined.contains("technical")) {
            return section("10.11")
        }
        return section("10.2")
    }

    /// Classify @ONLINE: 10.7 (review) vs 10.8 (preprint) vs 10.15 (social media) vs 10.16 (webpage).
    private static func classifyOnline(entry: BibEntry, fieldKeys: Set<String>) -> APASection {
        // 10.7 Reviews: only if RELATEDTYPE is "reviewof"
        if let relType = caseInsensitiveField(entry, "RELATEDTYPE"),
           relType.lowercased() == "reviewof" {
            return section("10.7")
        }

        // 10.15 Social Media: check EPRINT platform or ENTRYSUBTYPE
        let socialPlatforms = ["twitter", "facebook", "instagram", "reddit",
                               "tumblr", "linkedin", "tiktok"]
        if let eprint = caseInsensitiveField(entry, "EPRINT") {
            if socialPlatforms.contains(where: { eprint.lowercased().contains($0) }) {
                return section("10.15")
            }
        }
        if let subtype = caseInsensitiveField(entry, "ENTRYSUBTYPE") {
            let lower = subtype.lowercased()
            if lower.contains("tweet") || lower.contains("status")
                || lower.contains("profile") || lower.contains("infographic")
                || lower.contains("highlight") {
                return section("10.15")
            }
        }

        // 10.8 Preprints/Informally Published: check EPRINT archives
        let archivePlatforms = ["psyarxiv", "pubmed central", "eric", "arxiv",
                                "biorxiv", "medrxiv", "ssrn", "osf"]
        if let eprint = caseInsensitiveField(entry, "EPRINT") {
            if archivePlatforms.contains(where: { eprint.lowercased().contains($0) }) {
                return section("10.8")
            }
        }

        // 10.16 Webpages (default for ONLINE)
        return section("10.16")
    }

    /// Case-insensitive field lookup.
    private static func caseInsensitiveField(_ entry: BibEntry, _ name: String) -> String? {
        let lower = name.lowercased()
        if let key = entry.fields.keys.first(where: { $0.lowercased() == lower }) {
            return entry.fields[key]
        }
        return nil
    }

    /// Lookup section by number.
    private static func section(_ number: String) -> APASection {
        sections.first { $0.number == number }!
    }
}
