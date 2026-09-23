package team

import (
	"errors"
	"os"
	"path/filepath"
	"regexp"
	"strings"
	"testing"
)

func fixture(t *testing.T) *Team {
	t.Helper()
	tm, err := Open(filepath.Join("..", "testdata", "team"))
	if err != nil {
		t.Fatal(err)
	}
	return tm
}

func TestOpenRejectsMissingRoot(t *testing.T) {
	if _, err := Open(""); err == nil {
		t.Error("empty root: want error")
	}
	if _, err := Open(filepath.Join(t.TempDir(), "nope")); err == nil {
		t.Error("missing root: want error")
	}
}

func TestSeatsSkipsUnderscoreAndBootlessFolders(t *testing.T) {
	seats, err := fixture(t).Seats()
	if err != nil {
		t.Fatal(err)
	}
	var names []string
	for _, s := range seats {
		names = append(names, s.Name+"|"+s.Role)
	}
	got := strings.Join(names, ",")
	if got != "Alex-Bot|The Overmind,Sam|QA Tester" {
		t.Errorf("seats = %s", got)
	}
}

func TestSeatMatchesNameOrFolderIgnoringCase(t *testing.T) {
	tm := fixture(t)
	for _, in := range []string{"alex-bot", "Alex-Bot", "ALEX-BOT - THE OVERMIND", " Sam "} {
		if _, err := tm.Seat(in); err != nil {
			t.Errorf("Seat(%q): %v", in, err)
		}
	}
}

func TestSeatRefusesPathsAndUnknownNames(t *testing.T) {
	tm := fixture(t)
	for _, in := range []string{
		"", "../_Family", "_Family", "Alex-Bot/../../outside.md", `Alex-Bot\..\_Family`,
		"..", "C:", "/etc/passwd", "Notes", "Nobody",
	} {
		_, err := tm.Seat(in)
		if !errors.Is(err, ErrUnknownSeat) {
			t.Errorf("Seat(%q) err = %v, want ErrUnknownSeat", in, err)
		}
	}
}

func TestBootInlinesImportsAndRefusesUnsafeOnes(t *testing.T) {
	tm := fixture(t)
	s, _ := tm.Seat("Alex-Bot")
	boot, err := tm.Boot(s)
	if err != nil {
		t.Fatal(err)
	}
	if !strings.Contains(boot, "Initiative: 75%. Alex prefers answers first.") {
		t.Error("import of WORKING_WITH_ALEX.md was not inlined")
	}
	if !strings.Contains(boot, "```\n@../WORKING_WITH_ALEX.md\n```") {
		t.Error("an @ line inside a code fence was expanded; it must stay literal")
	}
	if strings.Contains(boot, "SECRET") {
		t.Error("import from outside the team root leaked into the boot")
	}
	if !strings.Contains(boot, "[import ../../outside.md not loaded: outside the team root]") {
		t.Error("outside import was not reported")
	}
	if strings.Contains(boot, "family data") || !strings.Contains(boot, "only .md files are imported") {
		t.Error("non-Markdown import was not refused")
	}
}

func TestBootStopsAtImportDepth(t *testing.T) {
	root := t.TempDir()
	seat := filepath.Join(root, "Deep - Seat")
	if err := os.MkdirAll(seat, 0o755); err != nil {
		t.Fatal(err)
	}
	write := func(p, s string) {
		if err := os.WriteFile(p, []byte(s), 0o644); err != nil {
			t.Fatal(err)
		}
	}
	write(filepath.Join(seat, "BOOT.md"), "boot\n@../n1.md\n")
	for i := 1; i <= MaxImportDepth+1; i++ {
		write(filepath.Join(root, "n"+string(rune('0'+i))+".md"), "level "+string(rune('0'+i))+"\n@n"+string(rune('0'+i+1))+".md\n")
	}
	tm, _ := Open(root)
	s, err := tm.Seat("Deep")
	if err != nil {
		t.Fatal(err)
	}
	boot, err := tm.Boot(s)
	if err != nil {
		t.Fatal(err)
	}
	if !strings.Contains(boot, "level 5") || strings.Contains(boot, "level 6") {
		t.Errorf("depth limit wrong:\n%s", boot)
	}
	if !strings.Contains(boot, "nesting deeper than 5") {
		t.Error("depth refusal not reported")
	}
}

func TestBoardFiltersBySeatAndStatus(t *testing.T) {
	tm := fixture(t)
	ids := func(rows []BoardRow) string {
		var out []string
		for _, r := range rows {
			out = append(out, r["ID"])
		}
		return strings.Join(out, ",")
	}
	all, err := tm.Board(nil, false)
	if err != nil {
		t.Fatal(err)
	}
	if got := ids(all); got != "M-001,M-002,M-004" {
		t.Errorf("active rows = %s (archive and COMPLETE must be excluded)", got)
	}
	withDone, _ := tm.Board(nil, true)
	if got := ids(withDone); got != "M-001,M-002,M-003,M-004" {
		t.Errorf("all=true rows = %s", got)
	}
	sam, _ := tm.Seat("Sam")
	samRows, _ := tm.Board(&sam, false)
	if got := ids(samRows); got != "M-001,M-002" {
		t.Errorf("Sam rows = %s (Samantha must not match Sam)", got)
	}
	if all[0]["Mission"] != "Quarterly report" || all[0]["Blocker"] != "" {
		t.Errorf("row cells keyed wrong: %v", all[0])
	}
}

func TestBoardMissingFileIsEmpty(t *testing.T) {
	tm, _ := Open(t.TempDir())
	rows, err := tm.Board(nil, false)
	if err != nil || rows != nil {
		t.Errorf("rows=%v err=%v", rows, err)
	}
}

func TestInboxTreatsUntaggedAsUnreadAndSkipsFencedTemplates(t *testing.T) {
	tm := fixture(t)
	s, _ := tm.Seat("Alex-Bot")
	all, err := tm.Inbox(s, false)
	if err != nil {
		t.Fatal(err)
	}
	if len(all) != 3 {
		t.Fatalf("entries = %d, want 3 (the fenced template is not an entry): %+v", len(all), all)
	}
	unread, _ := tm.Inbox(s, true)
	if len(unread) != 2 || !strings.Contains(unread[1].Header, "2026-09-21") {
		t.Errorf("unread = %+v", unread)
	}
	if !strings.HasPrefix(unread[0].Body, "Found a flaky test.\n") || !strings.Contains(unread[0].Body, "Template text inside a fence") {
		t.Errorf("body = %q", unread[0].Body)
	}
	sam, _ := tm.Seat("Sam")
	none, err := tm.Inbox(sam, false)
	if err != nil || none != nil {
		t.Errorf("missing inbox: %v %v", none, err)
	}
}

func TestHandoffPicksNewerCopy(t *testing.T) {
	tm := fixture(t)
	s, _ := tm.Seat("Alex-Bot")
	h, err := tm.Handoff(s)
	if err != nil {
		t.Fatal(err)
	}
	if h.Path != ".auto-memory/HANDOFF.md" || h.Written != "2026-09-22 09:00" || h.Activated != "" {
		t.Errorf("picked %+v", h)
	}
	if !h.Differ || len(h.Copies) != 2 {
		t.Errorf("copies=%v differ=%v", h.Copies, h.Differ)
	}
	sam, _ := tm.Seat("Sam")
	if h, err := tm.Handoff(sam); h != nil || err != nil {
		t.Errorf("no handoff: got %v %v", h, err)
	}
}

// TestRealTeamRoot runs only when OVERMIND_REAL_ROOT points at a live team.
// It proves every seat's boot resolves with no import left behind.
func TestRealTeamRoot(t *testing.T) {
	root := os.Getenv("OVERMIND_REAL_ROOT")
	if root == "" {
		t.Skip("OVERMIND_REAL_ROOT not set")
	}
	tm, err := Open(root)
	if err != nil {
		t.Fatal(err)
	}
	seats, err := tm.Seats()
	if err != nil || len(seats) == 0 {
		t.Fatalf("seats=%v err=%v", seats, err)
	}
	leftover := regexp.MustCompile(`(?m)^@\S+$|not loaded:`)
	for _, s := range seats {
		boot, err := tm.Boot(s)
		if err != nil {
			t.Errorf("%s: %v", s.Name, err)
			continue
		}
		if leftover.MatchString(boot) {
			t.Errorf("%s: unresolved import: %q", s.Name, leftover.FindString(boot))
		}
	}
}
