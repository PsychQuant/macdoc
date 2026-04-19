// Re-export BiblatexAPA so that Layer 4 consumers (CLI, MCP) can access
// BibParser, BibEntry, OrderedDict etc. through BibAPAToHTML without
// importing the Layer 1 module directly.
@_exported import BiblatexAPA
