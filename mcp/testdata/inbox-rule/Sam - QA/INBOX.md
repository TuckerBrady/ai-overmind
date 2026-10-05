<!-- expected unread: 7 -->
# INBOX - Sam

Shared fixture for the CONTRACT 3.3 inbox rule (GAP-27). An entry is read
only when the last " — " or " - " segment of its header, trimmed and
uppercased, is exactly READ. Untagged entries are unread. overmind-mcp and
TARS both count this file; the count on line 1 is the oracle.

## 2026-10-01 — From T-Bot (READ the spec) — UNREAD
unread: READ appears only in the subject.

## 2026-10-02 — From T-Bot — READ
processed.

## 2026-10-03 — From T-Bot
unread: untagged.

## 2026-10-04 — From T-Bot — READ-ONLY audit of the repo
unread: READ-ONLY is a subject, not a status.

## 2026-10-04 — From Nash — please READ before merge
unread: READ is a word in the subject.

## 2026-10-05 - From Nash - READ
processed, hyphen separator.

## 2026-10-05 — From Nash — read
processed, lowercase tag.

## 2026-10-06 — From Vaughn —  READ  
processed, padded tag.

## 2026-10-06 — From Vaughn — UNREAD
unread: tagged UNREAD.

## 2026-10-07 — From Vaughn — READ?
unread: the tag is not exactly READ.

```markdown
## 2026-01-01 — From Nobody — UNREAD
Template inside a fence, not an entry.
```

## READ
unread: no separator, so the header carries no status segment.
