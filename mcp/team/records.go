package team

import (
	"os"
	"path/filepath"
	"regexp"
	"strings"
	"time"
)

// BoardRow is one row of the Active table on MISSION_BOARD.md, keyed by the
// table's own header, so both the plugin's default columns and a team's
// custom ones come through unchanged.
type BoardRow map[string]string

// statusSplit and assigneeSplit are the CONTRACT 3.2 tokenizers.
var (
	statusSplit   = regexp.MustCompile(`[/,;\s]+`)
	assigneeSplit = regexp.MustCompile(`[,/&+\s]+`)
)

func tokens(re *regexp.Regexp, cell string) []string {
	var out []string
	for _, tok := range re.Split(strings.TrimSpace(cell), -1) {
		if tok != "" {
			out = append(out, tok)
		}
	}
	return out
}

// StatusTokens splits a Status cell per CONTRACT 3.2: on "/", ",", ";" and
// whitespace. TARS uses the same split (GAP-26).
func StatusTokens(cell string) []string { return tokens(statusSplit, cell) }

// Complete reports whether every token of the row's Status cell is
// COMPLETE. An empty cell is not complete.
func (r BoardRow) Complete() bool {
	toks := StatusTokens(r["Status"])
	for _, tok := range toks {
		if tok != "COMPLETE" {
			return false
		}
	}
	return len(toks) > 0
}

var inFlight = map[string]bool{"ACTIVE": true, "QUEUED": true, "BLOCKED": true, "REVIEW": true, "PENDING": true}

// InFlight reports whether any Status token is one of the in-flight
// statuses, PENDING included as the legacy alias of QUEUED (GAP-26).
func (r BoardRow) InFlight() bool {
	for _, tok := range StatusTokens(r["Status"]) {
		if inFlight[tok] {
			return true
		}
	}
	return false
}

// Tier maps the row's Priority cell to the TARS cue tier (GAP-26):
// CRITICAL/P0/HIGH to CRITICAL, STANDARD/P1/MEDIUM to STANDARD, else LOW.
func (r BoardRow) Tier() string {
	switch strings.ToUpper(strings.TrimSpace(r["Priority"])) {
	case "CRITICAL", "P0", "HIGH":
		return "CRITICAL"
	case "STANDARD", "P1", "MEDIUM":
		return "STANDARD"
	}
	return "LOW"
}

// Board returns the Active rows of MISSION_BOARD.md. With a seat, it keeps
// only rows whose owner or assignee columns name that seat. COMPLETE rows
// are dropped unless all is set.
func (t *Team) Board(seat *Seat, all bool) ([]BoardRow, error) {
	text, err := t.readOptional(filepath.Join(t.Root, "MISSION_BOARD.md"))
	if err != nil || text == "" {
		return nil, err
	}
	var header []string
	var rows []BoardRow
	inActive := false
	for _, line := range strings.Split(text, "\n") {
		if strings.HasPrefix(line, "## ") {
			inActive = strings.EqualFold(strings.TrimSpace(line[3:]), "Active")
			header = nil
			continue
		}
		if !inActive || !strings.HasPrefix(strings.TrimSpace(line), "|") {
			continue
		}
		cells := splitRow(line)
		if header == nil {
			header = cells
			continue
		}
		if isSeparator(cells) {
			continue
		}
		row := BoardRow{}
		for i, h := range header {
			if i < len(cells) {
				row[h] = cells[i]
			}
		}
		if !all && row.Complete() {
			continue
		}
		if seat != nil && !rowNames(row, *seat) {
			continue
		}
		rows = append(rows, row)
	}
	return rows, nil
}

func splitRow(line string) []string {
	line = strings.TrimSpace(line)
	line = strings.TrimPrefix(line, "|")
	line = strings.TrimSuffix(line, "|")
	parts := strings.Split(line, "|")
	for i := range parts {
		parts[i] = strings.TrimSpace(parts[i])
	}
	return parts
}

func isSeparator(cells []string) bool {
	for _, c := range cells {
		if strings.Trim(c, "-: ") != "" {
			return false
		}
	}
	return true
}

var ownerColumns = []string{"Owner", "Assignee", "Assignees"}

// rowNames matches the seat's name, ignoring case, against each name in the
// owner and assignee cells, split on ",", "/", "&", "+" and whitespace.
// A substring never matches: "Sam" is not "Sam-Bot".
func rowNames(row BoardRow, s Seat) bool {
	for _, col := range ownerColumns {
		cell := strings.TrimSpace(row[col])
		if cell != "" && strings.EqualFold(cell, s.Name) {
			return true
		}
		for _, tok := range tokens(assigneeSplit, cell) {
			if strings.EqualFold(tok, s.Name) {
				return true
			}
		}
	}
	return false
}

// InboxEntry is one "## date — From X — STATUS" section of a seat's INBOX.md.
type InboxEntry struct {
	Header string `json:"header"`
	Unread bool   `json:"unread"`
	Body   string `json:"body"`
}

var headerSegments = regexp.MustCompile(` (?:—|-) `)

// EntryStatus applies amendment A-8 (which replaces CONTRACT 3.3) to an
// entry header. Strip the leading "## ", split on " — " or " - ", and take
// each segment's first whitespace-delimited token with any [ and ] removed.
// The first token that is exactly READ or UNREAD is the status. With no
// such token the entry is UNREAD. "(READ the spec)" and "READ-ONLY" are
// never status. TARS applies the same rule.
func EntryStatus(header string) string {
	header = strings.TrimPrefix(strings.TrimSpace(header), "## ")
	for _, seg := range headerSegments.Split(header, -1) {
		fields := strings.Fields(seg)
		if len(fields) == 0 {
			continue
		}
		if tok := strings.Trim(fields[0], "[]"); tok == "READ" || tok == "UNREAD" {
			return tok
		}
	}
	return "UNREAD"
}

// EntryRead reports whether an entry header's A-8 status is READ.
func EntryRead(header string) bool { return EntryStatus(header) == "READ" }

// Inbox returns a seat's inbox entries, unread ones only when asked.
func (t *Team) Inbox(s Seat, unreadOnly bool) ([]InboxEntry, error) {
	text, err := t.readOptional(t.seatFile(s, "INBOX.md"))
	if err != nil || text == "" {
		return nil, err
	}
	var entries []InboxEntry
	var cur *InboxEntry
	// The body grows in a strings.Builder: appending to a string copies the
	// whole body on every line, which took 27 s on a 1.5 MiB inbox (A-16).
	var body strings.Builder
	inFence := false
	flush := func() {
		if cur != nil {
			cur.Body = strings.TrimSpace(body.String())
			if !unreadOnly || cur.Unread {
				entries = append(entries, *cur)
			}
		}
		body.Reset()
	}
	for _, line := range strings.Split(text, "\n") {
		if strings.HasPrefix(strings.TrimSpace(line), "```") {
			inFence = !inFence
		}
		if !inFence && strings.HasPrefix(line, "## ") {
			flush()
			h := strings.TrimSpace(line[3:])
			cur = &InboxEntry{Header: h, Unread: !EntryRead(h)}
			continue
		}
		if cur != nil {
			body.WriteString(line)
			body.WriteByte('\n')
		}
	}
	flush()
	return entries, nil
}

// Handoff is a seat's staged HANDOFF.md, picked from its copies.
type Handoff struct {
	Path          string       `json:"path"`
	Written       string       `json:"written,omitempty"`
	WrittenSource string       `json:"written_source"`
	Activated     string       `json:"activated,omitempty"`
	Copies        []string     `json:"copies"`
	Differ        bool         `json:"copies_differ"`
	Other         *HandoffCopy `json:"other,omitempty"`
	Text          string       `json:"text"`
	at            time.Time
}

// HandoffCopy reports the copy that lost when both paths hold a handoff.
type HandoffCopy struct {
	Path          string `json:"path"`
	Written       string `json:"written,omitempty"`
	WrittenSource string `json:"written_source"`
	Activated     string `json:"activated,omitempty"`
}

// HeaderLines is how far into a handoff the header fields are looked for.
const HeaderLines = 40

var (
	writtenField   = regexp.MustCompile(`\bWRITTEN\**\s*:\**\s*(.*)$`)
	activatedField = regexp.MustCompile(`^\**ACTIVATED\**\s*:\**\s*(.+)$`)
	writtenValue   = regexp.MustCompile(`^(\d{4}-\d{2}-\d{2})(?:[ T](\d{2}:\d{2}))?(?:\s*(Z|[+-]\d{2}:\d{2}))?\b`)
)

// ParseWritten parses a WRITTEN value (CONTRACT 3.1): YYYY-MM-DD, optionally
// HH:MM, optionally Z or an offset. Without a zone it is local time.
func ParseWritten(v string) (time.Time, bool) {
	m := writtenValue.FindStringSubmatch(strings.TrimSpace(strings.Trim(strings.TrimSpace(v), "*")))
	if m == nil {
		return time.Time{}, false
	}
	layout, value := "2006-01-02", m[1]
	if m[2] != "" {
		layout, value = layout+" 15:04", value+" "+m[2]
	}
	var at time.Time
	var err error
	switch m[3] {
	case "":
		at, err = time.ParseInLocation(layout, value, time.Local)
	case "Z":
		at, err = time.Parse(layout, value)
	default:
		at, err = time.Parse(layout+" -07:00", value+" "+m[3])
	}
	return at, err == nil
}

// handoffHeader reads WRITTEN and ACTIVATED from the first HeaderLines
// lines, skipping fenced blocks. WRITTEN may sit mid-line and in bold.
func handoffHeader(text string) (written, activated string) {
	lines := strings.Split(text, "\n")
	if len(lines) > HeaderLines {
		lines = lines[:HeaderLines]
	}
	inFence := false
	for _, line := range lines {
		trimmed := strings.TrimSpace(line)
		if strings.HasPrefix(trimmed, "```") {
			inFence = !inFence
			continue
		}
		if inFence {
			continue
		}
		if m := writtenField.FindStringSubmatch(trimmed); m != nil && written == "" {
			written = strings.TrimSpace(strings.Trim(strings.TrimSpace(m[1]), "*"))
		}
		if m := activatedField.FindStringSubmatch(trimmed); m != nil && activated == "" {
			activated = strings.TrimSpace(m[1])
		}
	}
	return written, activated
}

// Handoff reads HANDOFF.md from the seat's folder root (canonical) and
// .auto-memory (legacy), and returns the copy written most recently, by
// time: the WRITTEN header when it parses, else the file's mtime. The other
// copy is reported. It returns nil when no copy exists.
func (t *Team) Handoff(s Seat) (*Handoff, error) {
	var found []*Handoff
	for _, rel := range [][]string{{"HANDOFF.md"}, {".auto-memory", "HANDOFF.md"}} {
		p := t.seatFile(s, rel...)
		text, err := t.readCapped(p)
		if err != nil {
			if os.IsNotExist(err) {
				continue
			}
			return nil, err
		}
		h := &Handoff{Path: filepath.ToSlash(filepath.Join(rel...)), Text: text, WrittenSource: "header"}
		h.Written, h.Activated = handoffHeader(text)
		at, ok := ParseWritten(h.Written)
		if !ok {
			info, err := os.Stat(p)
			if err != nil {
				return nil, t.redactErr(err)
			}
			at, h.WrittenSource = info.ModTime(), "mtime"
		}
		h.at = at
		found = append(found, h)
	}
	if len(found) == 0 {
		return nil, nil
	}
	best, other := found[0], (*Handoff)(nil)
	if len(found) == 2 {
		other = found[1]
		if other.at.After(best.at) {
			best, other = other, best
		}
	}
	for _, h := range found {
		best.Copies = append(best.Copies, h.Path)
	}
	if other != nil {
		best.Differ = other.Text != best.Text
		best.Other = &HandoffCopy{Path: other.Path, Written: other.Written, WrittenSource: other.WrittenSource, Activated: other.Activated}
	}
	return best, nil
}
