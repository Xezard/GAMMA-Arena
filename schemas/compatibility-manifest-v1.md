# Compatibility manifest v1

Every Release ZIP contains `gamma-arena-manifest.json` at its root. The file is a deterministic compatibility and integrity record; it is not runtime state and is never read from or written to an Anomaly installation.

## Root object

The JSON root is an object with exactly these fields in this order:

| Field | JSON type | v1 value / rule |
| --- | --- | --- |
| `addon_version` | string | `"0.5.0"`; must equal the repository `VERSION` used for the build |
| `state_schema_version` | integer | `1`; durable UI preference schema |
| `session_schema_version` | integer | `1`; `ArenaSession` and resume-intent schema |
| `fight_spec_schema_version` | integer | `9`; validated universal `FightSpec` schema |
| `catalog_schema_version` | integer | `10`; exact catalog structure |
| `catalog_revision` | integer | `11`; exact catalog semantics |
| `generator_version` | integer | `11`; deterministic generator behavior |
| `layout_revision` | integer | `2`; exact layout semantics (called `layout_version` inside `FightSpec`) |
| `compatibility_manifest_version` | integer | `1`; this JSON contract |
| `files` | array | zero or more file records as defined below |

No version field implies compatibility with another field. In particular, matching state schemas do not make an active `FightSpec`, hidden checkpoint, `ArenaSession`, generator, catalog, or layout compatible across add-on versions.

## File records

Each `files` element is an object with exactly two fields in this order:

| Field | JSON type | Rule |
| --- | --- | --- |
| `path` | string | ZIP-root-relative path using `/`, with no leading slash, `.` segment, or `..` segment |
| `sha256` | string | uppercase 64-character hexadecimal SHA-256 of the staged file's exact bytes |

The manifest does not list or hash itself. It lists every other regular staged file, including `README.md`, `CHANGELOG.md`, and all files under `gamedata/`.

## Sorting and serialization

Before the manifest is created, all staged absolute file paths are sorted with .NET `StringComparer.Ordinal`. Their emitted `/`-separated relative paths therefore have the same ordinal order. No locale, filesystem enumeration order, or modification time participates in sorting.

SHA-256 is computed over each staged file exactly as packaged: no newline, encoding, or metadata normalization occurs during hashing. JSON property order is the order specified above. The manifest is serialized as UTF-8 without a byte-order mark, uses LF line endings, ends with exactly one LF, and contains no timestamp, host name, absolute path, MO2 profile, or installation-derived value.

Archive entry names are sorted ordinally and archive timestamps remain fixed by the build. Given identical tracked inputs, version, PowerShell/.NET JSON formatting, and compression implementation, repeated builds produce identical manifest bytes and ZIP bytes.
