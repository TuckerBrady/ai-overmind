<!-- expected unread: 10 -->
# INBOX - Sam

Shared fixture for the inbox status rule, amendment A-8 (replaces CONTRACT
3.3). Strip "## ", split the header on " — " or " - ", and take each
segment's first whitespace token with [ and ] removed. The first token that
is exactly READ or UNREAD is the status; none means unread. overmind-mcp and
TARS both count this file; the count on line 1 is the oracle. Every entry
whose body starts "unread:" is unread; every other entry is read.

## 2026-10-01 — READ — Spec review from T-Bot
processed: status in the middle, the most common live format.

## 2026-10-02 — From T-Bot — READ
processed: status at the end.

## [UNREAD] 2026-10-03 — From Nash — merge note
unread: bracketed status leading the date.

## [READ] 2026-10-03 — From Mercer — invoice
processed: bracketed status leading the date.

## READ 2026-09-14 23:20 — From Vaughn — gate results
processed: READ followed by a date.

## 2026-10-04 — From Pierce — READ (closed by Nash)
processed: READ followed by a closing note.

## UNREAD — 2026-10-05 — From Ledger — budget question
unread: leading status.

## 2026-10-01 — From T-Bot (READ the spec) — design review
unread: decoy, READ inside parentheses is not status.

## 2026-10-04 — From T-Bot — READ-ONLY audit of the repo
unread: decoy, READ-ONLY is not status.

## 2026-10-04 — From Nash — please READ before merge
unread: decoy, READ is not the first token of its segment.

## 2026-10-03 — From T-Bot
unread: untagged.

## 2026-10-06 — UNREAD — From Vaughn — READ later
unread: the first status token wins.

## 2026-10-05 - From Nash - READ
processed: hyphen separator.

## 2026-10-06 — From Vaughn —  READ  
processed: padded status.

## 2026-10-07 — From Vaughn — read
unread: the status must be exactly READ.

## 2026-10-07 — From Dean — READ?
unread: READ? is not exactly READ.

## 2026-10-08 — From Birdie — UNREAD
unread: tagged UNREAD at the end.

```markdown
## 2026-01-01 — From Nobody — UNREAD
Template inside a fence, not an entry.
```
