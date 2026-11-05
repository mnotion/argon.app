# Argon document format (.agn)

## Version 1.0

An .agn file is a versioned binary container. It is Argon's canonical document boundary: normalized content and descriptive metadata are stored separately from the optional original source payload.

### Binary layout

All integer fields are unsigned and big-endian. The fixed header is 36 bytes:

| Offset | Size | Field |
|---:|---:|---|
| 0 | 8 | ASCII magic: ARGONAGN |
| 8 | 2 | Major version (1) |
| 10 | 2 | Minor version (0) |
| 12 | 4 | Flags |
| 16 | 4 | UTF-8 JSON metadata length |
| 20 | 8 | Stored normalized-content section length |
| 28 | 8 | Stored original-source section length |

The sections follow in this order: metadata JSON, normalized content, original source. Section lengths are stored lengths, after optional compression.

Flag 0x01 means the original source is retained. Flag 0x02 means a normalized UTF-8 text representation is present. Unknown flags and unsupported major versions are rejected.

Each payload uses either none or Qt qCompress encoding. The writer uses compression level 5 only when the compressed result is smaller than the raw bytes. This avoids wasting space on formats that are already compressed.

### Metadata

The compact UTF-8 JSON metadata contains:

- schema: org.argon.document
- formatVersion: metadata schema version
- documentId, createdAt, and title
- source: original file name, extension, MIME type, byte count, SHA-256, and retention status
- representation: text or opaque, content MIME type, and text normalization details
- encoding: codec for each binary section
- integrity: SHA-256 hashes for normalized content and retained source bytes

Text conversion currently supports common UTF-8 text, markup, data, and source-code extensions. Line endings become LF and Unicode text is normalized to NFC. Invalid UTF-8 is treated as opaque binary rather than silently altered. PDF, Office, image, audio, video, and other binary files are preserved as opaque originals; semantic extraction adapters can be added independently later.

The original source is retained by default. Disabling retention is permitted only for recognized UTF-8 text files. Source files are never modified.

### Safety and limits

- Maximum source section: 512 MiB.
- Maximum normalized content: 256 MiB.
- Maximum metadata: 1 MiB.
- Writes use QSaveFile so incomplete conversions do not replace an existing document.
- Reads validate the magic, version, flags, exact section sizes, schema, codecs, decompressed sizes, UTF-8 validity, and SHA-256 integrity before returning content.
- The format is not an archive and does not extract arbitrary filesystem paths.

The version 1 reader rejects unknown major versions and unknown flags. Future incompatible formats must increment the major version.
