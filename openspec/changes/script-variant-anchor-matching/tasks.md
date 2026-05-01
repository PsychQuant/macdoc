## Tasks

- [ ] Add OOXMLSwift `AnchorLookupOptions` or equivalent public options type with exact matching as the default.
- [ ] Implement a shared math-script canonicalization helper with explicit mapping for supported Unicode subscript/superscript characters.
- [ ] Thread the options type through `findBodyChildContainingText` and the insertion-anchor call sites that depend on it.
- [ ] Add OOXMLSwift tests for exact mode, math-script-insensitive mode, bidirectional matching, nth-instance behavior, and unsupported-character preservation.
- [ ] Add che-word-mcp `match_options.math_script_insensitive` schema support to the 4 scoped insertion tools.
- [ ] Parse MCP `match_options` into the OOXMLSwift anchor lookup option in Direct Mode and Session Mode.
- [ ] Add che-word-mcp tests proving schema exposure, default exact behavior, and successful `H₀` / `H0` insertion anchors when the option is enabled.
- [ ] Update README/tool documentation with the exact matching default and opt-in math-script matching examples.
- [ ] Verify with targeted Swift tests in both affected repos.
- [ ] Open implementation PRs referencing PsychQuant/che-word-mcp#90.
