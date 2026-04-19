// APACSS.swift — APA 7 reference list CSS styles

public enum APACSS {

    /// Minimal APA 7 reference list CSS.
    /// Includes hanging indent, proper spacing, and link styling.
    public static let minimal = """
    .apa-reference-list {
        font-family: "Times New Roman", Times, serif;
        font-size: 12pt;
        line-height: 2;
    }

    .apa-reference {
        padding-left: 0.5in;
        text-indent: -0.5in;
        margin-bottom: 0;
    }

    .apa-reference a {
        color: inherit;
        text-decoration: none;
    }

    .apa-reference a:hover {
        text-decoration: underline;
    }

    .apa-reference:target {
        background-color: #FEF3C7;
        transition: background-color 2s ease;
    }
    """

    /// Web-friendly APA CSS with modern font stack and responsive sizing.
    public static let web = """
    .apa-reference-list {
        font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif;
        font-size: 1rem;
        line-height: 1.8;
        max-width: 48rem;
    }

    .apa-reference {
        padding-left: 2rem;
        text-indent: -2rem;
        margin-bottom: 0.75rem;
    }

    .apa-reference em {
        font-style: italic;
    }

    .apa-reference a {
        color: #2563eb;
        text-decoration: none;
        word-break: break-all;
    }

    .apa-reference a:hover {
        text-decoration: underline;
    }

    .apa-reference:target {
        background-color: #DBEAFE;
        transition: background-color 2s ease;
    }
    """

    /// Wrap CSS in a <style> tag.
    public static func styleTag(_ css: String) -> String {
        "<style>\n\(css)\n</style>"
    }
}
