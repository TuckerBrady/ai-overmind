// Package firmware carries the plugin's firmware inside the binary, so the
// server hands out the version it was built with. firmware.md is a copy of
// ../../hooks/firmware.md made by build.sh; a test fails if the two drift.
package firmware

import (
	_ "embed"
	"strings"
)

//go:generate cp ../../hooks/firmware.md firmware.md

//go:embed firmware.md
var Text string

// Section is one top-level part of the firmware.
type Section struct {
	Title string
	Body  string
}

// Sections splits the firmware at its top-level "## " headings: those
// outside code fences whose title has no lowercase letters. Templates inside
// the firmware use "## " headings too, and those stay inside their section.
func Sections() []Section {
	text := strings.ReplaceAll(Text, "\r\n", "\n")
	var out []Section
	cur := Section{Title: "PREAMBLE"}
	inFence := false
	for _, line := range strings.Split(text, "\n") {
		if strings.HasPrefix(strings.TrimSpace(line), "```") {
			inFence = !inFence
		}
		if !inFence && strings.HasPrefix(line, "## ") {
			title := strings.TrimSpace(line[3:])
			if title == strings.ToUpper(title) {
				out = append(out, cur)
				cur = Section{Title: title}
			}
		}
		cur.Body += line + "\n"
	}
	return append(out, cur)
}

// Find returns the section whose title contains query, ignoring case.
func Find(query string) (Section, bool) {
	q := strings.ToUpper(strings.TrimSpace(query))
	for _, s := range Sections() {
		if s.Title == q {
			return s, true
		}
	}
	for _, s := range Sections() {
		if q != "" && strings.Contains(s.Title, q) {
			return s, true
		}
	}
	return Section{}, false
}
