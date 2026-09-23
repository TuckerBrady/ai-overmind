// Package team reads an Overmind team root: seats, boot layers, the mission
// board, inboxes and handoffs. It is read-only, and every path it opens is
// built from the team root plus a fixed file name, never from caller input.
package team

import (
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"regexp"
	"sort"
	"strings"
)

// MaxImportDepth matches Claude Code's own limit on nested @ imports.
const MaxImportDepth = 5

// Team is a team root on disk.
type Team struct {
	Root string
}

// Seat is one team member: a top-level folder, not prefixed with "_",
// that holds a BOOT.md.
type Seat struct {
	Name   string `json:"name"`
	Folder string `json:"folder"`
	Role   string `json:"role,omitempty"`
}

// Open validates the root and returns a Team.
func Open(root string) (*Team, error) {
	if root == "" {
		return nil, errors.New("no team root: pass --root or set OVERMIND_ROOT")
	}
	abs, err := filepath.Abs(root)
	if err != nil {
		return nil, err
	}
	info, err := os.Stat(abs)
	if err != nil {
		return nil, fmt.Errorf("team root %s: %w", abs, err)
	}
	if !info.IsDir() {
		return nil, fmt.Errorf("team root %s is not a folder", abs)
	}
	return &Team{Root: abs}, nil
}

// Seats lists every seat, sorted by name.
func (t *Team) Seats() ([]Seat, error) {
	entries, err := os.ReadDir(t.Root)
	if err != nil {
		return nil, err
	}
	var seats []Seat
	for _, e := range entries {
		if !e.IsDir() || strings.HasPrefix(e.Name(), "_") || strings.HasPrefix(e.Name(), ".") {
			continue
		}
		if _, err := os.Stat(filepath.Join(t.Root, e.Name(), "BOOT.md")); err != nil {
			continue
		}
		name, role, _ := strings.Cut(e.Name(), " - ")
		seats = append(seats, Seat{Name: strings.TrimSpace(name), Folder: e.Name(), Role: strings.TrimSpace(role)})
	}
	sort.Slice(seats, func(i, j int) bool { return seats[i].Name < seats[j].Name })
	return seats, nil
}

// ErrUnknownSeat is returned when a seat name matches nothing on disk.
var ErrUnknownSeat = errors.New("unknown seat")

// Seat resolves a caller-supplied name to a seat. It matches the short name
// or the full folder name, ignoring case. Anything that looks like a path is
// refused before matching, so a caller can never steer a read outside a seat.
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
		if strings.EqualFold(s.Name, name) || strings.EqualFold(s.Folder, name) {
			return s, nil
		}
	}
	names := make([]string, len(seats))
	for i, s := range seats {
		names[i] = s.Name
	}
	return Seat{}, fmt.Errorf("%w: %q (seats: %s)", ErrUnknownSeat, name, strings.Join(names, ", "))
}

func (t *Team) seatFile(s Seat, rel ...string) string {
	return filepath.Join(append([]string{t.Root, s.Folder}, rel...)...)
}

// inside reports whether path sits within the team root.
func (t *Team) inside(path string) bool {
	rel, err := filepath.Rel(t.Root, path)
	if err != nil {
		return false
	}
	return rel != ".." && !strings.HasPrefix(rel, ".."+string(filepath.Separator)) && !filepath.IsAbs(rel)
}

var importLine = regexp.MustCompile(`^@(\S+)$`)

// Boot returns a seat's BOOT.md with every whole-line @ import replaced by
// the imported file's text, the way Claude Code's CLAUDE.md loader does.
// Imports must be Markdown files inside the team root.
func (t *Team) Boot(s Seat) (string, error) {
	return t.expand(t.seatFile(s, "BOOT.md"), 0)
}

func (t *Team) expand(path string, depth int) (string, error) {
	raw, err := os.ReadFile(path)
	if err != nil {
		return "", err
	}
	lines := strings.Split(strings.ReplaceAll(string(raw), "\r\n", "\n"), "\n")
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
		target := filepath.Clean(filepath.Join(filepath.Dir(path), filepath.FromSlash(m[1])))
		switch {
		case depth+1 > MaxImportDepth:
			lines[i] = fmt.Sprintf("> [import %s not loaded: nesting deeper than %d]", m[1], MaxImportDepth)
		case !t.inside(target):
			lines[i] = fmt.Sprintf("> [import %s not loaded: outside the team root]", m[1])
		case !strings.EqualFold(filepath.Ext(target), ".md"):
			lines[i] = fmt.Sprintf("> [import %s not loaded: only .md files are imported]", m[1])
		default:
			body, err := t.expand(target, depth+1)
			if err != nil {
				lines[i] = fmt.Sprintf("> [import %s not loaded: %v]", m[1], err)
			} else {
				lines[i] = fmt.Sprintf("<!-- imported from %s -->\n%s\n<!-- end %s -->", m[1], strings.TrimRight(body, "\n"), m[1])
			}
		}
	}
	return strings.Join(lines, "\n"), nil
}

// readOptional reads a file, returning "" when it does not exist.
func readOptional(path string) (string, error) {
	b, err := os.ReadFile(path)
	if errors.Is(err, os.ErrNotExist) {
		return "", nil
	}
	return strings.ReplaceAll(string(b), "\r\n", "\n"), err
}
