package team

import (
	"os"
	"path/filepath"
	"regexp"
	"strings"
)

// BoardRow is one row of the Active table on MISSION_BOARD.md, keyed by the
// table's own header, so both the plugin's default columns and a team's
// custom ones come through unchanged.
type BoardRow map[string]string

// Board returns the Active rows of MISSION_BOARD.md. With a seat, it keeps
// only rows whose owner or assignee columns name that seat. Rows marked
// COMPLETE are dropped unless all is set.
func (t *Team) Board(seat *Seat, all bool) ([]BoardRow, error) {
	text, err := readOptional(filepath.Join(t.Root, "MISSION_BOARD.md"))
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
		if !all && strings.Contains(strings.ToUpper(row["Status"]), "COMPLETE") {
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

func rowNames(row BoardRow, s Seat) bool {
	word := regexp.MustCompile(`(?i)(^|[^A-Za-z0-9])` + regexp.QuoteMeta(s.Name) + `($|[^A-Za-z0-9])`)
	for _, col := range ownerColumns {
		if word.MatchString(row[col]) {
			return true
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

var readTag = regexp.MustCompile(`(^|\W)READ(\W|$)`)

// Inbox returns a seat's inbox entries. An entry is unread when its header
// says UNREAD or carries no READ tag at all: an untagged header has not
// been processed.
func (t *Team) Inbox(s Seat, unreadOnly bool) ([]InboxEntry, error) {
	text, err := readOptional(t.seatFile(s, "INBOX.md"))
	if err != nil || text == "" {
		return nil, err
	}
	var entries []InboxEntry
	var cur *InboxEntry
	inFence := false
	flush := func() {
		if cur != nil {
			cur.Body = strings.TrimSpace(cur.Body)
			if !unreadOnly || cur.Unread {
				entries = append(entries, *cur)
			}
		}
	}
	for _, line := range strings.Split(text, "\n") {
		if strings.HasPrefix(strings.TrimSpace(line), "```") {
			inFence = !inFence
		}
		if !inFence && strings.HasPrefix(line, "## ") {
			flush()
			h := strings.TrimSpace(line[3:])
			unread := strings.Contains(h, "UNREAD") || !readTag.MatchString(h)
			cur = &InboxEntry{Header: h, Unread: unread}
			continue
		}
		if cur != nil {
			cur.Body += line + "\n"
		}
	}
	flush()
	return entries, nil
}

// Handoff is a seat's staged HANDOFF.md, picked from its copies.
type Handoff struct {
	Path      string   `json:"path"`
	Written   string   `json:"written,omitempty"`
	Activated string   `json:"activated,omitempty"`
	Copies    []string `json:"copies"`
	Differ    bool     `json:"copies_differ"`
	Text      string   `json:"text"`
}

var (
	writtenLine   = regexp.MustCompile(`(?m)^WRITTEN:\s*(.+)$`)
	activatedLine = regexp.MustCompile(`(?m)^ACTIVATED:\s*(.+)$`)
)

// Handoff reads HANDOFF.md from the seat's folder root and .auto-memory,
// returning the copy with the newer WRITTEN header. It returns nil when no
// copy exists.
func (t *Team) Handoff(s Seat) (*Handoff, error) {
	var best *Handoff
	var texts []string
	var copies []string
	for _, rel := range [][]string{{"HANDOFF.md"}, {".auto-memory", "HANDOFF.md"}} {
		p := t.seatFile(s, rel...)
		text, err := readOptional(p)
		if err != nil {
			return nil, err
		}
		if text == "" {
			if _, statErr := os.Stat(p); statErr != nil {
				continue
			}
		}
		relPath := filepath.ToSlash(filepath.Join(rel...))
		copies = append(copies, relPath)
		texts = append(texts, text)
		h := &Handoff{Path: relPath, Text: text}
		if m := writtenLine.FindStringSubmatch(text); m != nil {
			h.Written = strings.TrimSpace(m[1])
		}
		if m := activatedLine.FindStringSubmatch(text); m != nil {
			h.Activated = strings.TrimSpace(m[1])
		}
		if best == nil || h.Written > best.Written {
			best = h
		}
	}
	if best == nil {
		return nil, nil
	}
	best.Copies = copies
	for _, x := range texts[1:] {
		if x != texts[0] {
			best.Differ = true
		}
	}
	return best, nil
}
