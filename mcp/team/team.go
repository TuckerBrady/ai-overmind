// Package team reads an Overmind team root: seats, boot layers, the mission
// board, inboxes and handoffs. It is read-only. Every path it opens is built
// from the team root plus a fixed file name, never from caller input, and is
// resolved through symlinks and junctions before a containment check, so
// nothing outside the root is ever read.
package team

import (
	"errors"
	"fmt"
	"io"
	"io/fs"
	"os"
	"path/filepath"
	"regexp"
	"sort"
	"strings"
	"unicode/utf8"
)

// MaxImportDepth matches Claude Code's own limit on nested @ imports.
const MaxImportDepth = 5

// Read and output caps (CONTRACT 3.5). Overflow is cut and marked.
const (
	MaxFileBytes   = 1 << 20 // per file read
	MaxOutputBytes = 2 << 20 // per boot, and per tool result
	TruncMarker    = "[truncated by overmind-mcp]"
)

// RootToken stands in for the team root in every string the server
// composes, so no tool output carries an absolute host path (CONTRACT 3.8).
const RootToken = "<team-root>"

// Team is a team root on disk.
type Team struct {
	Root string // absolute path as given
	real string // Root with every symlink and junction resolved
}

// Seat is one team member: a top-level folder, not prefixed with "_" or
// ".", that holds a BOOT.md.
type Seat struct {
	Name   string `json:"name"`
	Folder string `json:"folder"`
	Role   string `json:"role,omitempty"`
}

// ErrUnknownSeat is returned when a seat name matches nothing on disk.
var ErrUnknownSeat = errors.New("unknown seat")

// ErrAmbiguousSeat is returned when a short name matches more than one seat.
var ErrAmbiguousSeat = errors.New("ambiguous seat")

// ErrOutsideRoot is returned for a path that resolves outside the team root.
var ErrOutsideRoot = errors.New("resolves outside the team root")

// Open validates the root and returns a Team.
func Open(root string) (*Team, error) {
	if root == "" {
		return nil, errors.New("no team root: pass --root or set OVERMIND_ROOT")
	}
	abs, err := filepath.Abs(root)
	if err != nil {
		return nil, err
	}
	real, err := realPath(abs)
	if err != nil {
		return nil, fmt.Errorf("team root %s: %w", abs, err)
	}
	if info, err := os.Stat(real); err != nil || !info.IsDir() {
		return nil, fmt.Errorf("team root %s is not a folder", abs)
	}
	return &Team{Root: abs, real: real}, nil
}

// Redact replaces the team root, in every spelling the server may compose,
// with RootToken. File content is never passed through it (GAP-37).
func (t *Team) Redact(s string) string {
	// Longest spelling first: on macOS the resolved root (/private/var/...)
	// contains the given one (/var/...), and must not be half-replaced.
	paths := []string{t.real, t.Root}
	if len(t.Root) > len(t.real) {
		paths = []string{t.Root, t.real}
	}
	for _, p := range paths {
		s = strings.ReplaceAll(s, p, RootToken)
		s = strings.ReplaceAll(s, filepath.ToSlash(p), RootToken)
	}
	return s
}

// redactErr rewrites an error's text through Redact.
func (t *Team) redactErr(err error) error {
	if err == nil {
		return nil
	}
	var pe *fs.PathError
	if errors.As(err, &pe) {
		return &fs.PathError{Op: pe.Op, Path: t.Redact(pe.Path), Err: pe.Err}
	}
	if msg := t.Redact(err.Error()); msg != err.Error() {
		return redacted{msg: msg, err: err}
	}
	return err
}

type redacted struct {
	msg string
	err error
}

func (r redacted) Error() string { return r.msg }
func (r redacted) Unwrap() error { return r.err }

// within reports whether path sits at or below root. Both must already be
// resolved; filepath.Rel compares case-insensitively on Windows.
func within(root, path string) bool {
	rel, err := filepath.Rel(root, path)
	if err != nil {
		return false
	}
	return rel != ".." && !strings.HasPrefix(rel, ".."+string(filepath.Separator)) && !filepath.IsAbs(rel)
}

// inside is the lexical check, used before anything is resolved.
func (t *Team) inside(path string) bool { return within(t.Root, path) }

// resolve follows every symlink and junction in path (realPath) and
// refuses a result outside the resolved root (CONTRACT 3.4).
func (t *Team) resolve(path string) (string, error) {
	real, err := realPath(path)
	if err != nil {
		return "", t.redactErr(err)
	}
	if !within(t.real, real) {
		rel := strings.TrimLeft(strings.TrimPrefix(path, t.Root), `/\`)
		return "", fmt.Errorf("%s %w", filepath.ToSlash(rel), ErrOutsideRoot)
	}
	return real, nil
}

// readCapped resolves path, then reads at most MaxFileBytes of it with
// CRLF folded to LF. Overflow is cut on a character boundary and marked.
func (t *Team) readCapped(path string) (string, error) {
	real, err := t.resolve(path)
	if err != nil {
		return "", err
	}
	f, err := os.Open(real)
	if err != nil {
		return "", t.redactErr(err)
	}
	defer f.Close()
	b, err := io.ReadAll(io.LimitReader(f, MaxFileBytes+1))
	if err != nil {
		return "", t.redactErr(err)
	}
	over := len(b) > MaxFileBytes
	if over {
		b = b[:runeStart(b, MaxFileBytes)]
	}
	s := strings.ReplaceAll(string(b), "\r\n", "\n")
	if over {
		s = strings.TrimSuffix(s, "\r") + "\n" + TruncMarker
	}
	return s, nil
}

// readOptional reads a file through readCapped, returning "" when it does
// not exist.
func (t *Team) readOptional(path string) (string, error) {
	s, err := t.readCapped(path)
	if errors.Is(err, fs.ErrNotExist) {
		return "", nil
	}
	return s, err
}

// runeStart backs n off to the start of a UTF-8 character in b.
func runeStart(b []byte, n int) int {
	for n > 0 && n < len(b) && !utf8.RuneStart(b[n]) {
		n--
	}
	return n
}

// Cap cuts s to at most max bytes. A cut string ends in TruncMarker on its
// own line and still fits in max.
func Cap(s string, max int) string {
	if len(s) <= max {
		return s
	}
	return capForce(s, max)
}

func capForce(s string, max int) string {
	keep := max - len(TruncMarker) - 1
	if keep < 0 {
		keep = 0
	}
	if keep > len(s) {
		keep = len(s)
	}
	keep = runeStart([]byte(s), keep)
	return s[:keep] + "\n" + TruncMarker
}

var bootName = regexp.MustCompile(`You are \*\*([^*\r\n]{1,60})\*\*`)

// seatName applies CONTRACT 3.9: the **X** in the BOOT.md line
// "You are **X**", else the folder name before " - ", else the folder name.
func seatName(folder, boot string) (name, role string) {
	short, role, hasRole := strings.Cut(folder, " - ")
	short, role = strings.TrimSpace(short), strings.TrimSpace(role)
	if m := bootName.FindStringSubmatch(boot); m != nil {
		n := strings.TrimSpace(m[1])
		if n != "" && !strings.ContainsAny(n, `/\:`) && !strings.Contains(n, "..") && !strings.HasPrefix(n, "_") {
			if !hasRole && !strings.EqualFold(n, folder) {
				role = folder
			}
			return n, role
		}
	}
	return short, role
}

// Seats lists every seat, sorted by name and then folder. A folder that is
// a symlink or junction leading outside the root is not a seat.
func (t *Team) Seats() ([]Seat, error) {
	entries, err := os.ReadDir(t.Root)
	if err != nil {
		return nil, t.redactErr(err)
	}
	var seats []Seat
	for _, e := range entries {
		if strings.HasPrefix(e.Name(), "_") || strings.HasPrefix(e.Name(), ".") {
			continue
		}
		dir, err := t.resolve(filepath.Join(t.Root, e.Name()))
		if err != nil {
			continue
		}
		if info, err := os.Stat(dir); err != nil || !info.IsDir() {
			continue
		}
		boot, err := t.readCapped(filepath.Join(t.Root, e.Name(), "BOOT.md"))
		if err != nil {
			continue
		}
		name, role := seatName(e.Name(), boot)
		seats = append(seats, Seat{Name: name, Folder: e.Name(), Role: role})
	}
	sort.SliceStable(seats, func(i, j int) bool {
		if seats[i].Name != seats[j].Name {
			return seats[i].Name < seats[j].Name
		}
		return seats[i].Folder < seats[j].Folder
	})
	return seats, nil
}

// Seat resolves a caller-supplied name to a seat. A full folder name wins;
// otherwise the short name must match exactly one seat, ignoring case.
// Anything that looks like a path is refused before matching, so a caller
// can never steer a read outside a seat.
func (t *Team) Seat(name string) (Seat, error) {
	name = strings.TrimSpace(name)
	if name == "" {
		return Seat{}, fmt.Errorf("%w: empty name", ErrUnknownSeat)
	}
	if strings.ContainsAny(name, `/\:`) || strings.Contains(name, "..") {
		return Seat{}, fmt.Errorf("%w: %q is not a seat name", ErrUnknownSeat, name)
	}
	seats, err := t.Seats()
	if err != nil {
		return Seat{}, err
	}
	for _, s := range seats {
		if strings.EqualFold(s.Folder, name) {
			return s, nil
		}
	}
	var hits []Seat
	for _, s := range seats {
		if strings.EqualFold(s.Name, name) {
			hits = append(hits, s)
		}
	}
	switch len(hits) {
	case 1:
		return hits[0], nil
	case 0:
		names := make([]string, len(seats))
		for i, s := range seats {
			names[i] = s.Name
		}
		return Seat{}, fmt.Errorf("%w: %q (seats: %s)", ErrUnknownSeat, name, strings.Join(names, ", "))
	}
	folders := make([]string, len(hits))
	for i, s := range hits {
		folders[i] = fmt.Sprintf("%q", s.Folder)
	}
	return Seat{}, fmt.Errorf("%w: %q names more than one seat folder: %s; use the full folder name",
		ErrAmbiguousSeat, name, strings.Join(folders, " and "))
}

func (t *Team) seatFile(s Seat, rel ...string) string {
	return filepath.Join(append([]string{t.Root, s.Folder}, rel...)...)
}

var importLine = regexp.MustCompile(`^@(\S+)$`)

// Boot returns a seat's BOOT.md with every whole-line @ import replaced by
// the imported file's text, the way Claude Code's CLAUDE.md loader does.
// Imports must be Markdown files that resolve inside the team root. Each
// file is inlined at most once, nesting stops at MaxImportDepth, every read
// is capped at MaxFileBytes and the result at MaxOutputBytes.
func (t *Team) Boot(s Seat) (string, error) {
	x := &expander{t: t, visited: map[string]bool{}}
	out, err := x.expand(t.seatFile(s, "BOOT.md"), 0)
	if err != nil {
		return "", err
	}
	if x.full {
		return capForce(out, MaxOutputBytes), nil
	}
	return Cap(out, MaxOutputBytes), nil
}

type expander struct {
	t       *Team
	visited map[string]bool
	size    int  // bytes read so far
	full    bool // an import was skipped because the output cap was reached
}

func visitKey(real string) string {
	k := filepath.Clean(real)
	if filepath.Separator == '\\' {
		k = strings.ToLower(k)
	}
	return k
}

func (x *expander) expand(path string, depth int) (string, error) {
	raw, err := x.t.readCapped(path)
	if err != nil {
		return "", err
	}
	if real, err := realPath(path); err == nil {
		x.visited[visitKey(real)] = true
	}
	x.size += len(raw)
	lines := strings.Split(raw, "\n")
	inFence := false
	for i, line := range lines {
		trimmed := strings.TrimSpace(line)
		if strings.HasPrefix(trimmed, "```") {
			inFence = !inFence
			continue
		}
		m := importLine.FindStringSubmatch(trimmed)
		if inFence || m == nil {
			continue
		}
		lines[i] = x.importOne(path, m[1], depth)
	}
	return strings.Join(lines, "\n"), nil
}

func (x *expander) importOne(from, spec string, depth int) string {
	refuse := func(why string) string { return fmt.Sprintf("> [import %s not loaded: %s]", spec, why) }
	target := filepath.Clean(filepath.Join(filepath.Dir(from), filepath.FromSlash(spec)))
	switch {
	case depth+1 > MaxImportDepth:
		return refuse(fmt.Sprintf("nesting deeper than %d", MaxImportDepth))
	case !x.t.inside(target):
		return refuse("outside the team root")
	case !strings.EqualFold(filepath.Ext(target), ".md"):
		return refuse("only .md files are imported")
	}
	real, err := realPath(target)
	switch {
	case errors.Is(err, fs.ErrNotExist):
		return refuse("file not found")
	case err != nil:
		return refuse(x.t.redactErr(err).Error())
	case !within(x.t.real, real):
		return refuse("outside the team root")
	case x.visited[visitKey(real)]:
		return refuse("already imported above")
	case x.size >= MaxOutputBytes:
		x.full = true
		return refuse("output cap reached")
	}
	body, err := x.expand(target, depth+1)
	if err != nil {
		return refuse(x.t.redactErr(err).Error())
	}
	return fmt.Sprintf("<!-- imported from %s -->\n%s\n<!-- end %s -->", spec, strings.TrimRight(body, "\n"), spec)
}
