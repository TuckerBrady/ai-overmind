// Package firmware carries the plugin's doctrine inside the binary, so the
// server hands out the version it was built with.
//
// Since v5 the doctrine is a set of files, not one document: the kernel
// (hooks/kernel.md, injected at session start) and one reference file per
// topic (reference/*.md, read on demand). kernel.md and reference/*.md in this
// directory are copies made by ../build.sh; a test fails if any copy drifts
// from its source or goes stale.
package firmware

import (
	"embed"
	"io/fs"
	"path"
	"sort"
	"strings"
)

//go:generate sh ../build.sh copy

//go:embed kernel.md reference/*.md
var files embed.FS

// Section is one file of the doctrine: the kernel, or one reference topic.
type Section struct {
	Title   string   // "KERNEL", or the reference file's H1
	File    string   // relative path in the plugin, e.g. "reference/tars.md"
	Aliases []string // old firmware section titles moved into this file
	Body    string   // the file's text, CRLF normalized to LF
}

// Text is the whole doctrine in the fixed v5 concatenation order: for each
// file, "=== <relpath>\n" and then its text. hooks/kernel.md comes first,
// then reference/*.md in byte order of relative path. Its sha256 is the
// firmware hash that /diagnostic and overmind-mcp compare.
var Text string

var sections []Section

func init() {
	Text, sections = build(files)
}

// build reads the kernel and the reference files from fsys, laid out as in
// this package (kernel.md at the root, reference/*.md beside it).
func build(fsys fs.FS) (string, []Section) {
	type entry struct{ rel, name string }
	list := []entry{{"hooks/kernel.md", "kernel.md"}}
	refs, _ := fs.Glob(fsys, "reference/*.md")
	sort.Strings(refs)
	for _, r := range refs {
		list = append(list, entry{r, r})
	}
	var b strings.Builder
	var out []Section
	for _, e := range list {
		raw, err := fs.ReadFile(fsys, e.name)
		if err != nil {
			continue
		}
		body := strings.ReplaceAll(string(raw), "\r\n", "\n")
		if !strings.HasSuffix(body, "\n") {
			body += "\n"
		}
		b.WriteString("=== " + e.rel + "\n")
		b.WriteString(body)
		s := Section{File: e.rel, Body: body}
		if e.rel == "hooks/kernel.md" {
			s.Title = "KERNEL"
		} else {
			s.Title, s.Aliases = heading(body)
			if s.Title == "" {
				s.Title = strings.TrimSuffix(path.Base(e.rel), ".md")
			}
		}
		out = append(out, s)
	}
	return b.String(), out
}

// heading returns a reference file's H1 and the titles in its
// "<!-- aliases: a; b -->" comment.
func heading(body string) (title string, aliases []string) {
	for _, line := range strings.Split(body, "\n") {
		if title == "" && strings.HasPrefix(line, "# ") {
			title = strings.TrimSpace(line[2:])
			continue
		}
		if a, ok := strings.CutPrefix(line, "<!-- aliases:"); ok {
			a = strings.TrimSpace(strings.TrimSuffix(strings.TrimSpace(a), "-->"))
			for _, x := range strings.Split(a, ";") {
				if x = strings.TrimSpace(x); x != "" {
					aliases = append(aliases, x)
				}
			}
			break
		}
	}
	return title, aliases
}

// Sections returns one section per file: the kernel first, then each
// reference topic in byte order of its path.
func Sections() []Section {
	return append([]Section(nil), sections...)
}

// Find returns the section a query names, ignoring case. It tries, in order:
// an exact title, an exact file stem ("tars", "kernel"), an exact alias (an
// old firmware section title), then a substring of a title. An empty query
// never matches.
func Find(query string) (Section, bool) {
	return find(sections, query)
}

func find(all []Section, query string) (Section, bool) {
	q := strings.ToLower(strings.TrimSpace(query))
	if q == "" {
		return Section{}, false
	}
	for _, s := range all {
		if strings.ToLower(s.Title) == q {
			return s, true
		}
	}
	for _, s := range all {
		if strings.TrimSuffix(path.Base(s.File), ".md") == q {
			return s, true
		}
	}
	for _, s := range all {
		for _, a := range s.Aliases {
			if strings.ToLower(a) == q {
				return s, true
			}
		}
	}
	for _, s := range all {
		if strings.Contains(strings.ToLower(s.Title), q) {
			return s, true
		}
	}
	return Section{}, false
}
