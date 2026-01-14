import Foundation

/// 轉換選項
public struct ConversionOptions: Sendable {
    /// 是否包含 YAML frontmatter
    public var includeFrontmatter: Bool

    /// 是否將軟換行轉為硬換行
    public var hardLineBreaks: Bool

    /// 表格樣式
    public var tableStyle: TableStyle

    /// 標題樣式
    public var headingStyle: HeadingStyle

    public static let `default` = ConversionOptions(
        includeFrontmatter: false,
        hardLineBreaks: false,
        tableStyle: .pipe,
        headingStyle: .atx
    )

    public init(
        includeFrontmatter: Bool = false,
        hardLineBreaks: Bool = false,
        tableStyle: TableStyle = .pipe,
        headingStyle: HeadingStyle = .atx
    ) {
        self.includeFrontmatter = includeFrontmatter
        self.hardLineBreaks = hardLineBreaks
        self.tableStyle = tableStyle
        self.headingStyle = headingStyle
    }

    /// 表格樣式
    public enum TableStyle: Sendable {
        case pipe    // | col1 | col2 |
        case simple  // col1    col2
    }

    /// 標題樣式
    public enum HeadingStyle: Sendable {
        case atx     // # Heading
        case setext  // Heading\n=======
    }
}
