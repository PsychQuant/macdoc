import XCTest
@testable import MDToWord

final class MetadataReaderTests: XCTestCase {

    func testBasicMetadata() throws {
        let yaml = """
        version: "1.0"
        source:
          format: "docx"
          file: "test.docx"
        """

        let meta = try MetadataReader.parse(yaml)
        XCTAssertEqual(meta.version, "1.0")
        XCTAssertEqual(meta.source.format, "docx")
        XCTAssertEqual(meta.source.file, "test.docx")
    }

    func testDocumentProperties() throws {
        let yaml = """
        version: "1.0"
        source:
          format: "docx"

        document:
          properties:
            title: "Test Document"
            creator: "Author Name"
            subject: "Test Subject"
        """

        let meta = try MetadataReader.parse(yaml)
        XCTAssertNotNil(meta.document)
        XCTAssertEqual(meta.document?.properties.title, "Test Document")
        XCTAssertEqual(meta.document?.properties.creator, "Author Name")
        XCTAssertEqual(meta.document?.properties.subject, "Test Subject")
    }

    func testDocumentPropertiesKeywords() throws {
        let yaml = """
        version: "1.0"
        source:
          format: "docx"

        document:
          properties:
            title: "Test"
            keywords: "swift, docx, converter"
        """

        let meta = try MetadataReader.parse(yaml)
        XCTAssertEqual(meta.document?.properties.keywords, "swift, docx, converter")
    }

    func testDocumentPropertiesTimestamps() throws {
        let yaml = """
        version: "1.0"
        source:
          format: "docx"

        document:
          properties:
            title: "Test"
            created: "2024-01-15T10:30:00Z"
            modified: "2024-06-20T15:45:00Z"
        """

        let meta = try MetadataReader.parse(yaml)
        XCTAssertEqual(meta.document?.properties.created, "2024-01-15T10:30:00Z")
        XCTAssertEqual(meta.document?.properties.modified, "2024-06-20T15:45:00Z")
    }

    func testStyles() throws {
        let yaml = """
        version: "1.0"
        source:
          format: "docx"

        document:
          properties:
            title: "Test"
          styles:
            - id: "Heading1"
              name: "heading 1"
              basedOn: "Normal"
            - id: "Normal"
              name: "Normal"
        """

        let meta = try MetadataReader.parse(yaml)
        XCTAssertEqual(meta.document?.styles.count, 2)
        XCTAssertEqual(meta.document?.styles[0].id, "Heading1")
        XCTAssertEqual(meta.document?.styles[0].basedOn, "Normal")
    }

    func testSectionProperties() throws {
        let yaml = """
        version: "1.0"
        source:
          format: "docx"

        document:
          properties:
            title: "Test"
          sections:
            - pageSize:
                width: 12240
                height: 15840
              orientation: portrait
              margins:
                top: 1440
                bottom: 1440
                left: 1440
                right: 1440
        """

        let meta = try MetadataReader.parse(yaml)
        let section = meta.document?.sections.first
        XCTAssertNotNil(section)
        XCTAssertEqual(section?.pageSize?.width, 12240)
        XCTAssertEqual(section?.pageSize?.height, 15840)
        XCTAssertEqual(section?.orientation, "portrait")
        XCTAssertEqual(section?.margins?.top, 1440)
    }

    // MARK: - Comment Content

    func testCommentMeta() throws {
        let yaml = """
        version: "1.0"
        source:
          format: "docx"

        document:
          properties:
            title: "Test"
          comments:
            - id: 1
              author: "Alice"
              text: "Review this"
              paragraphIndex: 0
            - id: 2
              author: "Bob"
              text: "Done"
              paragraphIndex: 0
              parentId: 1
              done: true
        """

        let meta = try MetadataReader.parse(yaml)
        XCTAssertEqual(meta.document?.comments.count, 2)

        let comment1 = meta.document?.comments[0]
        XCTAssertEqual(comment1?.id, 1)
        XCTAssertEqual(comment1?.author, "Alice")
        XCTAssertEqual(comment1?.text, "Review this")
        XCTAssertNil(comment1?.parentId)
        XCTAssertEqual(comment1?.done, false)

        let comment2 = meta.document?.comments[1]
        XCTAssertEqual(comment2?.parentId, 1)
        XCTAssertEqual(comment2?.done, true)
    }

    // MARK: - Numbering Definitions

    func testNumberingDefMeta() throws {
        let yaml = """
        version: "1.0"
        source:
          format: "docx"

        document:
          properties:
            title: "Test"
          numbering:
            - abstractNumId: 0
              levels:
                - ilvl: 0
                  numFmt: bullet
                  lvlText: "•"
                  start: 1
                  indent: 720
                  fontName: "Symbol"
                - ilvl: 1
                  numFmt: bullet
                  lvlText: "o"
                  start: 1
                  indent: 1440
        """

        let meta = try MetadataReader.parse(yaml)
        XCTAssertEqual(meta.document?.numbering.count, 1)

        let def = meta.document?.numbering[0]
        XCTAssertEqual(def?.abstractNumId, 0)
        XCTAssertEqual(def?.levels.count, 2)
        XCTAssertEqual(def?.levels[0].numFmt, "bullet")
        XCTAssertEqual(def?.levels[0].fontName, "Symbol")
        XCTAssertEqual(def?.levels[1].indent, 1440)
    }

    // MARK: - Paragraph Meta

    func testParagraphMeta() throws {
        let yaml = """
        version: "1.0"
        source:
          format: "docx"

        paragraphs:
          - index: 0
            alignment: center
            spacing: { before: 240, after: 0 }
          - index: 3
            alignment: right
            indentation: { left: 720, firstLine: 360 }
            runs:
              - range: [0, 5]
                font: "Arial"
                fontSize: 24
                color: "#FF0000"
        """

        let meta = try MetadataReader.parse(yaml)
        XCTAssertEqual(meta.paragraphs.count, 2)

        let para0 = meta.paragraphs[0]
        XCTAssertEqual(para0.index, 0)
        XCTAssertEqual(para0.alignment, "center")
        XCTAssertEqual(para0.spacing?.before, 240)
        XCTAssertEqual(para0.spacing?.after, 0)

        let para3 = meta.paragraphs[1]
        XCTAssertEqual(para3.index, 3)
        XCTAssertEqual(para3.alignment, "right")
        XCTAssertEqual(para3.indentation?.left, 720)
        XCTAssertEqual(para3.indentation?.firstLine, 360)

        XCTAssertEqual(para3.runs.count, 1)
        XCTAssertEqual(para3.runs[0].range, [0, 5])
        XCTAssertEqual(para3.runs[0].fontName, "Arial")
        XCTAssertEqual(para3.runs[0].fontSize, 24)
        XCTAssertEqual(para3.runs[0].color, "FF0000")  // "#" 已被移除
    }

    // MARK: - Paragraph Advanced Properties

    func testParagraphKeepNext() throws {
        let yaml = """
        version: "1.0"
        source:
          format: "docx"

        paragraphs:
          - index: 0
            keepNext: true
        """

        let meta = try MetadataReader.parse(yaml)
        XCTAssertEqual(meta.paragraphs[0].keepNext, true)
    }

    func testParagraphKeepLines() throws {
        let yaml = """
        version: "1.0"
        source:
          format: "docx"

        paragraphs:
          - index: 0
            keepLines: true
        """

        let meta = try MetadataReader.parse(yaml)
        XCTAssertEqual(meta.paragraphs[0].keepLines, true)
    }

    func testParagraphPageBreakBefore() throws {
        let yaml = """
        version: "1.0"
        source:
          format: "docx"

        paragraphs:
          - index: 0
            pageBreakBefore: true
        """

        let meta = try MetadataReader.parse(yaml)
        XCTAssertEqual(meta.paragraphs[0].pageBreakBefore, true)
    }

    func testParagraphBorder() throws {
        let yaml = """
        version: "1.0"
        source:
          format: "docx"

        paragraphs:
          - index: 0
            border:
              top: { type: single, color: "FF0000", size: 8 }
              bottom: { type: single, color: "FF0000", size: 8 }
        """

        let meta = try MetadataReader.parse(yaml)
        let border = meta.paragraphs[0].border
        XCTAssertNotNil(border)
        XCTAssertEqual(border?.top?.type, "single")
        XCTAssertEqual(border?.top?.color, "FF0000")
        XCTAssertEqual(border?.top?.size, 8)
        XCTAssertNotNil(border?.bottom)
        XCTAssertNil(border?.left)
    }

    func testParagraphShading() throws {
        let yaml = """
        version: "1.0"
        source:
          format: "docx"

        paragraphs:
          - index: 0
            shading: { fill: "FFFF00", pattern: clear }
        """

        let meta = try MetadataReader.parse(yaml)
        let shading = meta.paragraphs[0].shading
        XCTAssertNotNil(shading)
        XCTAssertEqual(shading?.fill, "FFFF00")
        XCTAssertEqual(shading?.pattern, "clear")
    }

    // MARK: - CharacterSpacing in RunMeta

    func testRunCharacterSpacing() throws {
        let yaml = """
        version: "1.0"
        source:
          format: "docx"

        paragraphs:
          - index: 0
            runs:
              - range: [0, 5]
                characterSpacing: { spacing: 20, position: 5, kern: 16 }
        """

        let meta = try MetadataReader.parse(yaml)
        let run = meta.paragraphs[0].runs[0]
        XCTAssertNotNil(run.characterSpacing)
        XCTAssertEqual(run.characterSpacing?.spacing, 20)
        XCTAssertEqual(run.characterSpacing?.position, 5)
        XCTAssertEqual(run.characterSpacing?.kern, 16)
    }

    // MARK: - Table Meta

    func testTableMeta() throws {
        let yaml = """
        version: "1.0"
        source:
          format: "docx"

        tables:
          - index: 1
            width: 9000
            widthType: dxa
            alignment: center
            layout: fixed
            rows:
              - rowIndex: 0
                isHeader: true
                height: 400
        """

        let meta = try MetadataReader.parse(yaml)
        XCTAssertEqual(meta.tables.count, 1)

        let table = meta.tables[0]
        XCTAssertEqual(table.index, 1)
        XCTAssertEqual(table.width, 9000)
        XCTAssertEqual(table.widthType, "dxa")
        XCTAssertEqual(table.alignment, "center")
        XCTAssertEqual(table.layout, "fixed")

        XCTAssertEqual(table.rows.count, 1)
        XCTAssertEqual(table.rows[0].isHeader, true)
        XCTAssertEqual(table.rows[0].height, 400)
    }

    // MARK: - Figure Meta

    func testFigureMeta() throws {
        let yaml = """
        version: "1.0"
        source:
          format: "docx"

        figures:
          - id: "rId5"
            file: "figures/image1.png"
            contentType: "image/png"
            placement: inline
            width: 4572000
            height: 3429000
            altText: "A test image"
        """

        let meta = try MetadataReader.parse(yaml)
        XCTAssertEqual(meta.figures.count, 1)

        let fig = meta.figures[0]
        XCTAssertEqual(fig.id, "rId5")
        XCTAssertEqual(fig.file, "figures/image1.png")
        XCTAssertEqual(fig.contentType, "image/png")
        XCTAssertEqual(fig.placement, "inline")
        XCTAssertEqual(fig.width, 4572000)
        XCTAssertEqual(fig.height, 3429000)
        XCTAssertEqual(fig.altText, "A test image")
    }

    func testEmptyMetadata() throws {
        let yaml = """
        version: "1.0"
        source:
          format: "docx"
        """

        let meta = try MetadataReader.parse(yaml)
        XCTAssertNil(meta.document)
        XCTAssertTrue(meta.paragraphs.isEmpty)
        XCTAssertTrue(meta.tables.isEmpty)
        XCTAssertTrue(meta.figures.isEmpty)
    }
}
