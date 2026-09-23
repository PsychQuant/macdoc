import XCTest
import BiblatexAPA
@testable import BibAPA

final class APAStylerTests: XCTestCase {

    // MARK: - Style produces correct case

    func testStyleArticle() {
        let entry = makeEntry(type: "ARTICLE", fields: [
            "AUTHOR": "Cheng, Che",
            "TITLE": "Some Article Title",
            "JOURNALTITLE": "Psychometrika",
            "DATE": "2025",
        ])
        let ref = APAStyler.style(entry)
        guard case .article(let article) = ref else {
            XCTFail("Expected .article"); return
        }
        XCTAssertEqual(article.journal, "Psychometrika")
        XCTAssertEqual(article.date, "2025")
    }

    func testStylePresentation() {
        let entry = makeEntry(type: "PRESENTATION", fields: [
            "AUTHOR": "Cheng, Che",
            "TITLE": "Test Talk",
            "TITLEADDON": "Oral presentation",
            "EVENTTITLE": "Conference Name",
            "VENUE": "Taipei, Taiwan",
            "EVENTDATE": "2025-05-01/2025-05-03",
            "DATE": "2025",
        ])
        let ref = APAStyler.style(entry)
        guard case .presentation(let pres) = ref else {
            XCTFail("Expected .presentation"); return
        }
        XCTAssertEqual(pres.presentationType, "Oral presentation")
        XCTAssertEqual(pres.conference, "Conference Name")
        XCTAssertEqual(pres.venue, "Taipei, Taiwan")
        XCTAssertEqual(pres.date, "2025, May 1–3")
    }

    func testStyleThesis() {
        let entry = makeEntry(type: "THESIS", fields: [
            "AUTHOR": "Cheng, Che",
            "TITLE": "My Thesis Title",
            "INSTITUTION": "National Taiwan University",
            "TYPE": "mathesis",
            "DATE": "2020",
        ])
        let ref = APAStyler.style(entry)
        guard case .thesis(let thesis) = ref else {
            XCTFail("Expected .thesis"); return
        }
        XCTAssertEqual(thesis.thesisType, "Master's thesis")
        XCTAssertEqual(thesis.institution, "National Taiwan University")
    }

    // MARK: - Helpers

    func makeEntry(type: String, fields: [String: String]) -> BibEntry {
        var dict = OrderedDict()
        for (k, v) in fields { dict[k] = v }
        return BibEntry(entryType: type, key: "test", fields: dict, rawText: "", lineNumber: 1)
    }

    // MARK: - SUBTITLE reaches every entry type (macdoc#183)

    /// `buildTitle` has always folded a standalone `SUBTITLE` field into the
    /// rendered title, but only `styleArticle` and `styleBook` called it. Four
    /// other per-type functions inlined `toSentenceCase(stripBraces(title))`
    /// and dropped the field silently — a real bibliography lost the subtitle
    /// of 8 `@PRESENTATION` entries. `styleChapter` is a fifth instance the
    /// issue's table did not list.
    func testSubtitleIsFoldedIntoTheTitleForEveryEntryType() {
        func title(_ type: String, extra: [String: String] = [:]) -> String {
            var fields = [
                "AUTHOR": "Cheng, Che",
                "TITLE": "Main Title",
                "SUBTITLE": "The Subtitle",
                "DATE": "2025",
            ]
            fields.merge(extra) { _, new in new }
            switch APAStyler.style(makeEntry(type: type, fields: fields)) {
            case .article(let r):      return r.title
            case .book(let r):         return r.title
            case .chapter(let r):      return r.chapterTitle
            case .thesis(let r):       return r.title
            case .report(let r):       return r.title
            case .presentation(let r): return r.title
            case .online(let r):       return r.title
            @unknown default:          return ""
            }
        }
        let cases: [(String, [String: String])] = [
            ("ARTICLE", ["JOURNALTITLE": "Psychometrika"]),
            ("BOOK", [:]),
            ("INCOLLECTION", ["BOOKTITLE": "A Handbook"]),
            ("THESIS", ["INSTITUTION": "NTU"]),
            ("REPORT", ["INSTITUTION": "Academia Sinica"]),
            ("PRESENTATION", ["EVENTTITLE": "A Conference"]),
            ("ONLINE", ["URL": "https://example.com"]),
            ("MISC", ["URL": "https://example.com"]),
        ]
        for (type, extra) in cases {
            XCTAssertEqual(title(type, extra: extra), "Main title: The subtitle", "\(type) must fold SUBTITLE into the title")
        }
    }

    /// An entry without `SUBTITLE` renders exactly as before — the fix must not
    /// append a stray colon.
    func testATitleWithoutASubtitleIsUnchanged() {
        let entry = makeEntry(type: "PRESENTATION", fields: [
            "AUTHOR": "Cheng, Che", "TITLE": "Main Title", "EVENTTITLE": "A Conference", "DATE": "2025",
        ])
        guard case .presentation(let pres) = APAStyler.style(entry) else { XCTFail("Expected .presentation"); return }
        XCTAssertEqual(pres.title, "Main title")
    }

    // MARK: - LaTeX leaks into rendered fields (macdoc#197)

    /// Only fields that went through `toSentenceCase` lost their mid-string
    /// protective braces, and no field decoded accent macros or `\&`. These are
    /// the two entries from the issue's reproduction, asserted field by field.
    func testMidStringBracesAndEscapesAreRemovedFromEveryField() {
        let entry = makeEntry(type: "PRESENTATION", fields: [
            "AUTHOR": "Doe, Jane",
            "TITLE": "A Talk About {GitHub} and {SEM}",
            "TITLEADDON": "Invited talk",
            "EVENTTITLE": "Research \\& Evaluation {SIG} Webinar, {SITE} 2026",
            "VENUE": "Online",
            "EVENTDATE": "2026-08-27",
            "DATE": "2026",
        ])
        guard case .presentation(let pres) = APAStyler.style(entry) else { XCTFail("Expected .presentation"); return }
        XCTAssertEqual(pres.title, "A talk about GitHub and SEM")
        XCTAssertEqual(pres.conference, "Research & Evaluation SIG Webinar, SITE 2026")
        XCTAssertEqual(pres.presentationType, "Invited talk")
    }

    func testAccentMacrosAreDecodedInEveryField() {
        let entry = makeEntry(type: "PRESENTATION", fields: [
            "AUTHOR": "Doe, Jane",
            "TITLE": "The {Cram\\'{e}r-Rao} Bound and {Sch\\\"{o}nemann}'s Problem",
            "TITLEADDON": "Oral presentation",
            "EVENTTITLE": "Soci\\'{e}t\\'{e} de Statistique Annual Meeting",
            "VENUE": "Montr\\'{e}al, Canada",
            "EVENTDATE": "2025-10-18/2025-10-19",
            "DATE": "2025",
        ])
        guard case .presentation(let pres) = APAStyler.style(entry) else { XCTFail("Expected .presentation"); return }
        XCTAssertEqual(pres.title, "The Cramér-Rao bound and Schönemann's problem")
        XCTAssertEqual(pres.conference, "Société de Statistique Annual Meeting")
        XCTAssertEqual(pres.venue, "Montréal, Canada")
    }

    func testOtherPlainFieldsLoseBracesAndDecode() {
        let article = makeEntry(type: "ARTICLE", fields: [
            "AUTHOR": "Doe, Jane", "TITLE": "T", "DATE": "2020",
            "JOURNALTITLE": "Journal of {R} \\& {SAS} Users",
        ])
        guard case .article(let a) = APAStyler.style(article) else { XCTFail("Expected .article"); return }
        XCTAssertEqual(a.journal, "Journal of R & SAS Users")

        let thesis = makeEntry(type: "THESIS", fields: [
            "AUTHOR": "Doe, Jane", "TITLE": "T", "DATE": "2020", "TYPE": "phdthesis",
            "INSTITUTION": "Universit\\\"{a}t {Z}\\\"{u}rich",
        ])
        guard case .thesis(let th) = APAStyler.style(thesis) else { XCTFail("Expected .thesis"); return }
        XCTAssertEqual(th.institution, "Universität Zürich")
    }

    func testAuthorNamesAreDecodedBeforeParsing() {
        let entry = makeEntry(type: "ARTICLE", fields: [
            "AUTHOR": "Sch\\\"{o}nemann, J\\\"{o}rg and {\\'E}mile, Zo\\\"{e}",
            "TITLE": "T", "JOURNALTITLE": "J", "DATE": "2020",
        ])
        guard case .article(let a) = APAStyler.style(entry) else { XCTFail("Expected .article"); return }
        XCTAssertEqual(a.authors, "Schönemann, J., & Émile, Z.")
    }

    func testURLIsNotDecoded() {
        let url = "https://example.org/a\\_b?q=1\\%20"
        let entry = makeEntry(type: "ARTICLE", fields: [
            "AUTHOR": "Doe, Jane", "TITLE": "T", "JOURNALTITLE": "J", "DATE": "2020", "URL": url,
        ])
        guard case .article(let a) = APAStyler.style(entry) else { XCTFail("Expected .article"); return }
        XCTAssertEqual(a.url, url, "biblatex treats URL as verbatim; decoding would change the address")
    }

    func testDecodeLaTeXForms() {
        let cases: [(String, String)] = [
            ("Cram\\'er", "Cramér"), ("Cram\\'{e}r", "Cramér"), ("Cram{\\'e}r", "Cram{é}r"),
            ("Cram{\\'{e}}r", "Cram{é}r"), ("\\\"{o}", "ö"), ("\\`{a}", "à"), ("\\^{o}", "ô"),
            ("\\~{n}", "ñ"), ("\\c{c}", "ç"), ("\\c c", "ç"), ("\\v{s}", "š"), ("\\'{\\i}", "í"),
            ("\\ss", "ß"), ("Stra\\ss{}e", "Straße"), ("{\\o}", "{ø}"), ("\\aa", "å"), ("\\l{}", "ł"),
            ("A \\& B", "A & B"), ("50\\%", "50%"), ("\\$5", "$5"), ("\\#1", "#1"), ("a\\_b", "a_b"),
            ("\\unknown{x}", "\\unknown{x}"), ("no macros here", "no macros here"),
        ]
        for (input, expected) in cases {
            XCTAssertEqual(decodeLaTeX(input), expected, "decodeLaTeX(\(input))")
        }
    }

    func testPlainTextRemovesProtectiveBracesButKeepsEscapedOnes() {
        XCTAssertEqual(plainText("{SIG} and {Cram\\'{e}r}"), "SIG and Cramér")
        XCTAssertEqual(plainText("set \\{a, b\\}"), "set {a, b}")
        XCTAssertEqual(plainText("Plain text"), "Plain text")
    }

    // MARK: - #197 verify round 1 (Codex): parser boundaries and remaining fields

    func testDotlessIOnlyMatchesTheWholeCommandName() {
        XCTAssertEqual(decodeLaTeX("\\'\\input"), "\\'\\input", "\\input is not \\i; keep it verbatim")
        XCTAssertEqual(decodeLaTeX("\\'\\i"), "í")
        XCTAssertEqual(decodeLaTeX("\\'\\i{}"), "í")
        XCTAssertEqual(decodeLaTeX("\\'{\\i{}}"), "í")
    }

    func testAccentArgumentsFollowTeXSpacingAndNesting() {
        XCTAssertEqual(decodeLaTeX("\\c  c"), "ç", "control words skip all following spaces")
        XCTAssertEqual(decodeLaTeX("\\v\ts"), "š", "including tabs")
        XCTAssertEqual(decodeLaTeX("\\'{{e}}"), "é", "nested group")
        XCTAssertEqual(plainText("\\'{{e}}"), "é", "must not leak as \\'e after braces are removed")
        XCTAssertEqual(decodeLaTeX("Stra\\ss e"), "Straße", "a letter macro swallows the following space")
    }

    func testUnknownCommandsSurviveTheRenderedOutput() {
        XCTAssertEqual(plainText("\\emph{Nice} work"), "\\emph{Nice} work")
        XCTAssertEqual(sentenceCaseText("A \\emph{Nice} Title"), "A \\emph{Nice} title")
        XCTAssertEqual(plainText("\\unknown{a {b} c}"), "\\unknown{a {b} c}")
    }

    func testMalformedInputDoesNotCrashOrLeakBraces() {
        XCTAssertEqual(plainText("abc\\"), "abc\\")
        XCTAssertFalse(plainText("\\'{e").contains("{"))
        XCTAssertEqual(plainText("}{"), "")
    }

    func testPrivateUseCharactersInInputAreNotRewritten() {
        XCTAssertEqual(plainText("A\u{E000}B\u{E001}C {x}"), "A\u{E000}B\u{E001}Cx".replacingOccurrences(of: "Cx", with: "C x"))
        XCTAssertEqual(plainText("set \\{a\\} and \u{E000}"), "set {a} and \u{E000}")
    }

    func testEditorsVolumeNumberAndCorporateAuthorsAreDecoded() {
        let chapter = makeEntry(type: "INCOLLECTION", fields: [
            "AUTHOR": "{Soci\\'{e}t\\'{e} de Statistique}", "TITLE": "C", "DATE": "2020",
            "BOOKTITLE": "B", "EDITOR": "Sch\\\"{o}nemann, J\\\"{o}rg", "VOLUME": "{12}", "PUBLISHER": "P",
        ])
        guard case .chapter(let c) = APAStyler.style(chapter) else { XCTFail("Expected .chapter"); return }
        XCTAssertEqual(c.authors, "Société de Statistique.")
        XCTAssertEqual(c.editors, "J. Schönemann (Ed.)")
        XCTAssertEqual(c.volume, "Vol. 12")

        let article = makeEntry(type: "ARTICLE", fields: [
            "AUTHOR": "Doe, Jane", "TITLE": "T", "JOURNALTITLE": "J", "DATE": "2020",
            "VOLUME": "{7}", "NUMBER": "{3}", "DOI": "10.1000/a\\_b",
        ])
        guard case .article(let a) = APAStyler.style(article) else { XCTFail("Expected .article"); return }
        XCTAssertEqual(a.volume, "7")
        XCTAssertEqual(a.issue, "3")
        XCTAssertEqual(a.doi, "https://doi.org/10.1000/a\\_b", "DOI is verbatim; never decode it")

        let report = makeEntry(type: "REPORT", fields: [
            "AUTHOR": "Doe, Jane", "TITLE": "T", "DATE": "2020", "TYPE": "Technical Report", "NUMBER": "{A}",
        ])
        guard case .report(let r) = APAStyler.style(report) else { XCTFail("Expected .report"); return }
        XCTAssertEqual(r.number, "Technical Report A")
    }

    // MARK: - #197 verify round 2 (Codex)

    func testSymbolAccentArgumentMayFollowWhitespace() {
        XCTAssertEqual(plainText("\\' e"), "é")
        XCTAssertEqual(plainText("\\'\te"), "é")
        XCTAssertEqual(plainText("\\\" {o}"), "ö")
    }

    func testUnknownCommandKeepsSpacedArgumentsVerbatim() {
        XCTAssertEqual(plainText("\\unknown {x}"), "\\unknown {x}")
        XCTAssertEqual(sentenceCaseText("A \\emph {Nice} Title"), "A \\emph {Nice} title")
        XCTAssertEqual(plainText("\\unknown text"), "\\unknown text", "no group: nothing consumed")
        XCTAssertEqual(sentenceCaseText("See {\\emph{X}} Now"), "See \\emph{X} now", "unknown command inside a protected group")
    }

    func testPlaceholderPoolExhaustionDoesNotCrash() {
        let everyBMPPrivateUse = String(String.UnicodeScalarView((0xE000...0xF8FF).compactMap(Unicode.Scalar.init)))
        let input = everyBMPPrivateUse + " \\{x\\}"
        XCTAssertEqual(plainText(input), everyBMPPrivateUse + " {x}", "falls back to the supplementary private-use planes")
    }

    func testEditionAndPagesAreDecoded() {
        let book = makeEntry(type: "BOOK", fields: [
            "AUTHOR": "Doe, Jane", "TITLE": "T", "DATE": "2020", "PUBLISHER": "P", "EDITION": "{2}",
        ])
        guard case .book(let b) = APAStyler.style(book) else { XCTFail("Expected .book"); return }
        XCTAssertEqual(b.edition, "2nd ed.")

        let article = makeEntry(type: "ARTICLE", fields: [
            "AUTHOR": "Doe, Jane", "TITLE": "T", "JOURNALTITLE": "J", "DATE": "2020", "PAGES": "{1--51}",
        ])
        guard case .article(let a) = APAStyler.style(article) else { XCTFail("Expected .article"); return }
        XCTAssertEqual(a.pages, "1–51")
    }
}
