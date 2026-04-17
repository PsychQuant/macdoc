# note-core-parsing Specification

## Purpose

Shared Notability `.note` file parsing — ZIP extraction, `Session.plist` stroke decoding, image extraction, page geometry. Consumed by both the HTML converter and the PDF converter.

## Requirements

- NoteParser extracts ParsedNote from .note ZIP bundle
- StrokeDecoder produces Curve array with color and width
- ParsedNote exposes page geometry
