# docx-container-parsing Specification

## Purpose

Defines the expected container-reading coverage of `DocxReader.read()` — which OOXML parts (`word/header*.xml`, `word/footer*.xml`, `word/footnotes.xml`, `word/endnotes.xml`) are read and how their paragraph content populates the `WordDocument` model. Includes the `Revision.source` enum and `getRevisionsFull()` API for disambiguating where each revision originated.

## Requirements

(Synced from change delta specs — see archived change for scenario details with @trace comments.)

- DocxReader reads header parts from the ZIP
- DocxReader reads footer parts from the ZIP
- DocxReader reads footnotes from the ZIP
- DocxReader reads endnotes from the ZIP
- RevisionSource enum disambiguates revision origin
- getRevisionsFull returns Revisions with source
