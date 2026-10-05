package team

// Findings MCP-1..5, 8..10 and 13 (OPS-030 L5). The audit probes in
// audit-skills-mcp/mcp-copy/team/audit_probe_test.go are promoted here as
// asserting tests named TestMCP<n>_<slug>.

import (
	"errors"
	"fmt"
	"go/ast"
	"go/parser"
	"go/token"
	"io/fs"
	"math/rand"
	"os"
	"os/exec"
	"path/filepath"
	"runtime"
	"strings"
	"testing"
	"time"
	"unicode/utf8"
)

func w(t *testing.T, p, s string) {
	t.Helper()
	if err := os.MkdirAll(filepath.Dir(p), 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(p, []byte(s), 0o644); err != nil {
		t.Fatal(err)
	}
}

// link makes a directory link: a junction on Windows (mklink /J, which
// needs no privilege), a symlink elsewhere. It never skips (GAP-38).
func link(t *testing.T, linkPath, target string) {
	t.Helper()
	if runtime.GOOS == "windows" {
		out, err := exec.Command("cmd", "/c", "mklink", "/J", linkPath, target).CombinedOutput()
		if err != nil {
			t.Fatalf("mklink /J %s %s: %v %s", linkPath, target, err, out)
		}
		return
	}
	if err := os.Symlink(target, linkPath); err != nil {
		t.Fatalf("symlink: %v", err)
	}
}

func open(t *testing.T, root string) *Team {
	t.Helper()
	tm, err := Open(root)
	if err != nil {
		t.Fatal(err)
	}
	return tm
}

func mustSeat(t *testing.T, tm *Team, name string) Seat {
	t.Helper()
	s, err := tm.Seat(name)
	if err != nil {
		t.Fatal(err)
	}
	return s
}

func setMtime(t *testing.T, p string, at time.Time) {
	t.Helper()
	if err := os.Chtimes(p, at, at); err != nil {
		t.Fatal(err)
	}
}

func local(s string) time.Time {
	at, err := time.ParseInLocation("2006-01-02 15:04", s, time.Local)
	if err != nil {
		panic(err)
	}
	return at
}

// ---- MCP-1: handoff parsing -------------------------------------------

func TestMCP1_ParseWrittenFormats(t *testing.T) {
	cases := []struct {
		in   string
		want time.Time
		ok   bool
	}{
		{"2026-10-04", local("2026-10-04 00:00"), true},
		{"2026-10-04 09:00", local("2026-10-04 09:00"), true},
		{"2026-10-04T09:00", local("2026-10-04 09:00"), true},
		{"2026-10-04 09:00Z", time.Date(2026, 10, 4, 9, 0, 0, 0, time.UTC), true},
		{"2026-10-04 09:00 +02:00", time.Date(2026, 10, 4, 7, 0, 0, 0, time.UTC), true},
		{"2026-10-04 09:00-05:30", time.Date(2026, 10, 4, 14, 30, 0, 0, time.UTC), true},
		{"**2026-10-04 09:00**", local("2026-10-04 09:00"), true},
		{"2026-10-04 09:00 by Nash", local("2026-10-04 09:00"), true},
		{"2026-10-4 09:00", time.Time{}, false},
		{"2026-13-04", time.Time{}, false},
		{"[time]", time.Time{}, false},
		{"", time.Time{}, false},
	}
	for _, c := range cases {
		got, ok := ParseWritten(c.in)
		if ok != c.ok || (ok && !got.Equal(c.want)) {
			t.Errorf("ParseWritten(%q) = %v %v, want %v %v", c.in, got, ok, c.want, c.ok)
		}
	}
}

func TestMCP1_HeaderFieldShapes(t *testing.T) {
	cases := []struct{ text, written, activated string }{
		{"TYPE: SELF-HANDOFF · SEAT: Sam · WRITTEN: 2026-10-04 09:00\nNEW\n", "2026-10-04 09:00", ""},
		{"**TYPE:** DISPATCH\n**WRITTEN:** 2026-10-04 09:00\n**ACTIVATED:** 2026-10-04 10:00 by Sam\n", "2026-10-04 09:00", "2026-10-04 10:00 by Sam"},
		{"WRITTEN**:** 2026-10-04\n", "2026-10-04", ""},
		{"TYPE: DISPATCH\nWRITTEN: 2026-10-04 08:00\n## NEXT STEPS\n```\nACTIVATED: [time] by [seat]\nWRITTEN: 2099-01-01 00:00\n```\n", "2026-10-04 08:00", ""},
		{"REWRITTEN: 2026-10-04\nUNWRITTEN: 2026-10-05\n", "", ""},
		{strings.Repeat("filler\n", HeaderLines) + "WRITTEN: 2026-10-04 09:00\n", "", ""},
		{strings.Repeat("filler\n", HeaderLines-1) + "WRITTEN: 2026-10-04 09:00\n", "2026-10-04 09:00", ""},
	}
	for i, c := range cases {
		wr, ac := handoffHeader(c.text)
		if wr != c.written || ac != c.activated {
			t.Errorf("case %d: written=%q activated=%q, want %q %q", i, wr, ac, c.written, c.activated)
		}
	}
}

func handoffTeam(t *testing.T, rootCopy, legacyCopy string) (*Team, Seat, string) {
	t.Helper()
	root := t.TempDir()
	seat := filepath.Join(root, "Sam - QA")
	w(t, filepath.Join(seat, "BOOT.md"), "# b")
	if rootCopy != "" {
		w(t, filepath.Join(seat, "HANDOFF.md"), rootCopy)
	}
	if legacyCopy != "" {
		w(t, filepath.Join(seat, ".auto-memory", "HANDOFF.md"), legacyCopy)
	}
	tm := open(t, root)
	return tm, mustSeat(t, tm, "Sam"), seat
}

// Probe A: a fresh dispatch brief at the root with no WRITTEN line, and an
// old self-handoff in .auto-memory. The fresh one wins by mtime.
func TestMCP1_StaleLegacyLosesToFreshRootByMtime(t *testing.T) {
	tm, s, seat := handoffTeam(t,
		"CLASSIFIED — MISSION BRIEF\nDATE DISPATCHED: 2026-10-04\nMISSION ID: M-099\nFRESH DISPATCH\n",
		"TYPE: SELF-HANDOFF · SEAT: Sam · WRITTEN: 2026-09-01 10:00\nOLD SELF HANDOFF\n")
	setMtime(t, filepath.Join(seat, "HANDOFF.md"), local("2026-10-04 12:00"))
	setMtime(t, filepath.Join(seat, ".auto-memory", "HANDOFF.md"), local("2026-10-04 12:30"))
	h, err := tm.Handoff(s)
	if err != nil {
		t.Fatal(err)
	}
	if h.Path != "HANDOFF.md" || h.WrittenSource != "mtime" || !strings.Contains(h.Text, "FRESH DISPATCH") {
		t.Fatalf("picked %s (%s), want the fresh root brief", h.Path, h.WrittenSource)
	}
	if h.Other == nil || h.Other.Path != ".auto-memory/HANDOFF.md" || h.Other.Written != "2026-09-01 10:00" || h.Other.WrittenSource != "header" {
		t.Errorf("other copy not reported: %+v", h.Other)
	}
	if !h.Differ || strings.Join(h.Copies, ",") != "HANDOFF.md,.auto-memory/HANDOFF.md" {
		t.Errorf("copies=%v differ=%v", h.Copies, h.Differ)
	}
}

// Probe B: the template puts WRITTEN mid-line. The newer one wins.
func TestMCP1_MidLineWrittenTemplate(t *testing.T) {
	tm, s, _ := handoffTeam(t,
		"TYPE: SELF-HANDOFF · SEAT: Sam · WRITTEN: 2026-10-04 09:00\nNEW\n",
		"TYPE: SELF-HANDOFF · SEAT: Sam · WRITTEN: 2026-09-01 09:00\nOLD\n")
	h, _ := tm.Handoff(s)
	if h.Path != "HANDOFF.md" || h.Written != "2026-10-04 09:00" || h.WrittenSource != "header" {
		t.Errorf("picked %+v", h)
	}
}

// Probe C: an unparseable WRITTEN falls back to mtime, and an ACTIVATED
// line inside a fenced template is not a stamp.
func TestMCP1_UnparseableFallsBackToMtimeAndFencedStampIgnored(t *testing.T) {
	tm, s, seat := handoffTeam(t,
		"WRITTEN: 2026-10-4 09:00\nNEW (unpadded day)\n",
		"WRITTEN: 2026-10-04 08:00\nOLDER\n## NEXT STEPS\n```\nACTIVATED: [time] by [seat]\n```\n")
	setMtime(t, filepath.Join(seat, "HANDOFF.md"), local("2026-10-04 09:00"))
	h, _ := tm.Handoff(s)
	if h.Path != "HANDOFF.md" || h.WrittenSource != "mtime" || h.Written != "2026-10-4 09:00" {
		t.Errorf("picked %+v", h)
	}
	if h.Other == nil || h.Other.Activated != "" {
		t.Errorf("fenced ACTIVATED read as a stamp: %+v", h.Other)
	}
}

// The newer by time wins, not by string comparison: 09:00+02:00 is 07:00Z,
// earlier than 08:00Z although it sorts later as text.
func TestMCP1_NewerByTimeNotByString(t *testing.T) {
	tm, s, _ := handoffTeam(t,
		"WRITTEN: 2026-10-04 09:00+02:00\nROOT\n",
		"**WRITTEN:** 2026-10-04 08:00Z\nLEGACY\n")
	h, _ := tm.Handoff(s)
	if h.Path != ".auto-memory/HANDOFF.md" || h.Other.Path != "HANDOFF.md" {
		t.Errorf("picked %s, want the legacy copy (later instant)", h.Path)
	}
	tm2, s2, _ := handoffTeam(t, "WRITTEN: 2026-10-04\nDATE ONLY, LATER DAY\n", "WRITTEN: 2026-10-03 23:59\nEARLIER\n")
	if h2, _ := tm2.Handoff(s2); h2.Path != "HANDOFF.md" {
		t.Errorf("date-only: picked %s", h2.Path)
	}
	tm3, s3, _ := handoffTeam(t, "WRITTEN: 2026-10-04 09:00\nSAME\n", "WRITTEN: 2026-10-04 09:00\nSAME TIME\n")
	if h3, _ := tm3.Handoff(s3); h3.Path != "HANDOFF.md" {
		t.Errorf("tie: picked %s, want the canonical root", h3.Path)
	}
}

func TestMCP1_SingleCopies(t *testing.T) {
	tm, s, _ := handoffTeam(t, "", "WRITTEN: 2026-10-04 09:00\nLEGACY ONLY\n")
	h, err := tm.Handoff(s)
	if err != nil || h.Path != ".auto-memory/HANDOFF.md" || h.Other != nil || h.Differ {
		t.Errorf("legacy only: %+v %v", h, err)
	}
	tm2, s2, _ := handoffTeam(t, "", "")
	if h, err := tm2.Handoff(s2); h != nil || err != nil {
		t.Errorf("none: %+v %v", h, err)
	}
}

// ---- MCP-2: board status and seat matching ----------------------------

const probeBoard = "## Active\n" +
	"| ID | Mission | Owner | Assignee | Status | Priority |\n" +
	"|---|---|---|---|---|---|\n" +
	"| M-1 | a | Sam-Bot | Sam-Bot | ACTIVE | HIGH |\n" +
	"| M-2 | b | Sam | Sam | INCOMPLETE - rework | P1 |\n" +
	"| M-3 | c | Sam | Sam | sam: ACTIVE · nash: COMPLETE | LOW |\n" +
	"| M-4 | d | Nash | Nash, sam | ACTIVE / COMPLETE | P0 |\n" +
	"| M-5 | e | Sam | Sam | COMPLETE / COMPLETE | |\n" +
	"| M-6 | f | Nash | Nash+Sam | QUEUED | MEDIUM |\n" +
	"| M-7 | g | Nash | Samuel & Nash | QUEUED | |\n" +
	"| M-8 | h | Nash | Nash | complete | |\n" +
	"| M-9 | i | Sam | Sam | | |\n" +
	"\n## Archive\n" +
	"| ID | Mission | Owner | Assignee | Status | Priority |\n" +
	"|---|---|---|---|---|---|\n" +
	"| M-0 | z | Sam | Sam | ACTIVE | |\n"

func boardIDs(rows []BoardRow) string {
	var out []string
	for _, r := range rows {
		out = append(out, r["ID"])
	}
	return strings.Join(out, ",")
}

func TestMCP2_StatusTokensAndExactSeatMatch(t *testing.T) {
	root := t.TempDir()
	w(t, filepath.Join(root, "Sam - QA", "BOOT.md"), "# b")
	w(t, filepath.Join(root, "MISSION_BOARD.md"), probeBoard)
	tm := open(t, root)
	all, err := tm.Board(nil, false)
	if err != nil {
		t.Fatal(err)
	}
	// Only M-5 is COMPLETE in every token. INCOMPLETE, mixed rows and a
	// lowercase "complete" stay.
	if got := boardIDs(all); got != "M-1,M-2,M-3,M-4,M-6,M-7,M-8,M-9" {
		t.Errorf("active = %s", got)
	}
	sam := mustSeat(t, tm, "Sam")
	rows, _ := tm.Board(&sam, false)
	if got := boardIDs(rows); got != "M-2,M-3,M-4,M-6,M-9" {
		t.Errorf("Sam rows = %s (Sam-Bot and Samuel must not match)", got)
	}
	rows, _ = tm.Board(&sam, true)
	if got := boardIDs(rows); got != "M-2,M-3,M-4,M-5,M-6,M-9" {
		t.Errorf("Sam rows, all = %s", got)
	}
}

func TestMCP2_StatusSplitInFlightAndTier(t *testing.T) {
	if got := strings.Join(StatusTokens(" ACTIVE /COMPLETE;REVIEW,\tBLOCKED  "), "|"); got != "ACTIVE|COMPLETE|REVIEW|BLOCKED" {
		t.Errorf("tokens = %s", got)
	}
	cases := []struct {
		status, priority string
		complete, flight bool
		tier             string
	}{
		{"ACTIVE", "HIGH", false, true, "CRITICAL"},
		{"COMPLETE", "P0", true, false, "CRITICAL"},
		{"COMPLETE/COMPLETE", "CRITICAL", true, false, "CRITICAL"},
		{"ACTIVE / COMPLETE", "P1", false, true, "STANDARD"},
		{"INCOMPLETE", "MEDIUM", false, false, "STANDARD"},
		{"PENDING", " standard ", false, true, "STANDARD"},
		{"QUEUED; REVIEW", "LOW", false, true, "LOW"},
		{"", "", false, false, "LOW"},
		{"active", "P2", false, false, "LOW"},
	}
	for _, c := range cases {
		r := BoardRow{"Status": c.status, "Priority": c.priority}
		if r.Complete() != c.complete || r.InFlight() != c.flight || r.Tier() != c.tier {
			t.Errorf("%q/%q: complete=%v inflight=%v tier=%s", c.status, c.priority, r.Complete(), r.InFlight(), r.Tier())
		}
	}
}

// ---- MCP-3: inbox status segment -------------------------------------

// TestMCP3_InboxStatusA8 pins amendment A-8 (replaces 3.3): the first
// segment whose first token is READ or UNREAD decides; otherwise unread.
func TestMCP3_InboxStatusA8(t *testing.T) {
	cases := []struct{ header, want string }{
		{"## 2026-10-01 — READ — Spec review", "READ"},                         // status mid-header
		{"## 2026-10-02 — From T-Bot — READ", "READ"},                          // status at the end
		{"## [UNREAD] 2026-10-03 — From Nash — merge note", "UNREAD"},          // bracketed lead
		{"## [READ] 2026-10-03 — From Nash", "READ"},                           // bracketed lead
		{"## READ 2026-09-14 23:20 — From Vaughn — gate results", "READ"},      // READ <date>
		{"## 2026-10-04 — From Pierce — READ (closed by Nash)", "READ"},        // READ (closed by ...)
		{"## UNREAD — 2026-10-05 — From Ledger — budget", "UNREAD"},            // leading status
		{"## 2026-10-01 — From T-Bot (READ the spec) — subject", "UNREAD"},     // decoy
		{"## 2026-10-04 — From T-Bot — READ-ONLY audit of the repo", "UNREAD"}, // decoy
		{"## 2026-10-04 — From Nash — please READ before merge", "UNREAD"},     // not first token
		{"## 2026-10-01 — From T-Bot (READ the spec) — UNREAD", "UNREAD"},
		{"## 2026-10-06 — UNREAD — From Vaughn — READ later", "UNREAD"}, // first status wins
		{"## 2026-10-06 — READ — re: UNREAD backlog", "READ"},
		{"## 2026-10-05 - From Nash - READ", "READ"},      // hyphen separator
		{"## 2026-10-06 — From Vaughn —  READ  ", "READ"}, // padded
		{"## 2026-10-07 — From Vaughn — read", "UNREAD"},  // exact match only
		{"## 2026-10-07 — From Vaughn — READ?", "UNREAD"},
		{"## 2026-10-03 — From T-Bot", "UNREAD"}, // untagged
		{"## READ", "READ"},
		{"##  — ", "UNREAD"},
		{"", "UNREAD"},
	}
	for _, c := range cases {
		if got := EntryStatus(c.header); got != c.want {
			t.Errorf("EntryStatus(%q) = %s, want %s", c.header, got, c.want)
		}
		if EntryRead(c.header) != (c.want == "READ") {
			t.Errorf("EntryRead(%q) disagrees with EntryStatus", c.header)
		}
	}
	// The same rule through Inbox, on a real file.
	dir := t.TempDir()
	seat := filepath.Join(dir, "Sam - QA")
	w(t, filepath.Join(seat, "BOOT.md"), "You are **Sam**\n")
	var b strings.Builder
	want := 0
	for _, c := range cases[:len(cases)-2] {
		b.WriteString(c.header + "\nbody\n\n")
		if c.want == "UNREAD" {
			want++
		}
	}
	w(t, filepath.Join(seat, "INBOX.md"), b.String())
	tm := open(t, dir)
	got, err := tm.Inbox(mustSeat(t, tm, "Sam"), true)
	if err != nil {
		t.Fatal(err)
	}
	if len(got) != want {
		t.Errorf("Inbox unread = %d, want %d", len(got), want)
	}
}

// TestMCP3_SharedInboxFixture runs the A-8 rule over the fixture TARS
// shares (A-8, formerly GAP-27). The fixture states its own expected count.
func TestMCP3_SharedInboxFixture(t *testing.T) {
	root := filepath.Join("..", "testdata", "inbox-rule")
	raw, err := os.ReadFile(filepath.Join(root, "Sam - QA", "INBOX.md"))
	if err != nil {
		t.Fatal(err)
	}
	var want int
	if _, err := fmt.Sscanf(strings.TrimSpace(strings.SplitN(string(raw), "\n", 2)[0]), "<!-- expected unread: %d -->", &want); err != nil || want == 0 {
		t.Fatalf("fixture header unreadable: %v", err)
	}
	tm := open(t, root)
	got, err := tm.Inbox(mustSeat(t, tm, "Sam"), true)
	if err != nil {
		t.Fatal(err)
	}
	if len(got) != want {
		t.Errorf("unread = %d, want %d", len(got), want)
	}
	all, _ := tm.Inbox(mustSeat(t, tm, "Sam"), false)
	if len(all) != 17 {
		t.Errorf("entries = %d, want 17 (the fenced template is not an entry)", len(all))
	}
	for _, e := range all {
		if e.Unread != strings.HasPrefix(e.Body, "unread:") {
			t.Errorf("unread=%v but the body says otherwise: %q", e.Unread, e.Header)
		}
	}
}

// ---- MCP-4: links out of the root ------------------------------------

// Probe: a linked folder inside the team root leads outside, and BOOT.md
// imports through it.
func TestMCP4_LinkedImportOutsideRootRefused(t *testing.T) {
	base := t.TempDir()
	root := filepath.Join(base, "team")
	outside := filepath.Join(base, "outside")
	w(t, filepath.Join(outside, "secret.md"), "SECRET OUTSIDE ROOT")
	w(t, filepath.Join(root, "Sam - QA", "BOOT.md"), "# BOOT\n@../Notes/link/secret.md\n@../Inside/shared.md\n")
	w(t, filepath.Join(root, "Real", "shared.md"), "SHARED INSIDE ROOT")
	if err := os.MkdirAll(filepath.Join(root, "Notes"), 0o755); err != nil {
		t.Fatal(err)
	}
	link(t, filepath.Join(root, "Notes", "link"), outside)
	link(t, filepath.Join(root, "Inside"), filepath.Join(root, "Real"))
	tm := open(t, root)
	boot, err := tm.Boot(mustSeat(t, tm, "Sam"))
	if err != nil {
		t.Fatal(err)
	}
	if strings.Contains(boot, "SECRET OUTSIDE ROOT") {
		t.Fatal("a linked import escaped the team root")
	}
	if !strings.Contains(boot, "[import ../Notes/link/secret.md not loaded: outside the team root]") {
		t.Errorf("escape not reported:\n%s", boot)
	}
	if !strings.Contains(boot, "SHARED INSIDE ROOT") {
		t.Errorf("a link that stays inside the root must still load:\n%s", boot)
	}
}

// Probe: a seat folder that is itself a link to a folder outside the root.
func TestMCP4_LinkedSeatFolderRefused(t *testing.T) {
	base := t.TempDir()
	root := filepath.Join(base, "team")
	outside := filepath.Join(base, "elsewhere")
	w(t, filepath.Join(outside, "BOOT.md"), "# planted boot")
	w(t, filepath.Join(outside, "INBOX.md"), "## x — From Y — UNREAD\nprivate inbox outside root\n")
	w(t, filepath.Join(root, "Sam - QA", "BOOT.md"), "# b")
	link(t, filepath.Join(root, "Ghost - Seat"), outside)
	tm := open(t, root)
	seats, err := tm.Seats()
	if err != nil {
		t.Fatal(err)
	}
	for _, s := range seats {
		if s.Name == "Ghost" {
			t.Fatalf("a linked seat folder outside the root was listed: %+v", seats)
		}
	}
	if _, err := tm.Seat("Ghost"); !errors.Is(err, ErrUnknownSeat) {
		t.Errorf("Seat(Ghost) err = %v, want ErrUnknownSeat", err)
	}
	// Even a hand-built Seat value cannot read through the link.
	ghost := Seat{Name: "Ghost", Folder: "Ghost - Seat"}
	if _, err := tm.Inbox(ghost, false); !errors.Is(err, ErrOutsideRoot) {
		t.Errorf("Inbox through the link: err = %v, want ErrOutsideRoot", err)
	}
	if _, err := tm.Boot(ghost); !errors.Is(err, ErrOutsideRoot) {
		t.Errorf("Boot through the link: err = %v, want ErrOutsideRoot", err)
	}
}

// A seat's .auto-memory folder linked outside the root: the legacy handoff
// copy is refused, not read.
func TestMCP4_LinkedHandoffFolderRefused(t *testing.T) {
	base := t.TempDir()
	root := filepath.Join(base, "team")
	outside := filepath.Join(base, "mem")
	w(t, filepath.Join(outside, "HANDOFF.md"), "WRITTEN: 2099-01-01\nPLANTED\n")
	w(t, filepath.Join(root, "Sam - QA", "BOOT.md"), "# b")
	link(t, filepath.Join(root, "Sam - QA", ".auto-memory"), outside)
	tm := open(t, root)
	h, err := tm.Handoff(mustSeat(t, tm, "Sam"))
	if !errors.Is(err, ErrOutsideRoot) || h != nil {
		t.Fatalf("handoff through a link: %+v %v", h, err)
	}
	if strings.Contains(err.Error(), base) || strings.Contains(err.Error(), filepath.ToSlash(base)) {
		t.Errorf("error leaks an absolute path: %v", err)
	}
}

// ---- MCP-5 and MCP-10: amplification and caps --------------------------

// Probe: a 180-byte BOOT.md that imports itself eight times.
func TestMCP5_SelfImportFanoutBounded(t *testing.T) {
	root := t.TempDir()
	body := "# BOOT " + strings.Repeat("x", 100) + "\n" + strings.Repeat("@BOOT.md\n", 8)
	if len(body) != 180 {
		t.Fatalf("fixture is %d bytes, want 180", len(body))
	}
	w(t, filepath.Join(root, "Sam - QA", "BOOT.md"), body)
	tm := open(t, root)
	boot, err := tm.Boot(mustSeat(t, tm, "Sam"))
	if err != nil {
		t.Fatal(err)
	}
	if len(boot) > 4<<10 {
		t.Fatalf("boot grew to %d bytes from a %d-byte source", len(boot), len(body))
	}
	if strings.Count(boot, "already imported above") != 8 {
		t.Errorf("self-imports not refused:\n%s", boot)
	}
}

// A cycle across files terminates, and a diamond loads its shared file once.
func TestMCP5_CycleAndDiamond(t *testing.T) {
	root := t.TempDir()
	w(t, filepath.Join(root, "Sam - QA", "BOOT.md"), "boot\n@../a.md\n@../b.md\n")
	w(t, filepath.Join(root, "a.md"), "AAA\n@c.md\n@b.md\n")
	w(t, filepath.Join(root, "b.md"), "BBB\n@c.md\n@a.md\n")
	w(t, filepath.Join(root, "c.md"), "CCC\n@a.md\n")
	tm := open(t, root)
	boot, err := tm.Boot(mustSeat(t, tm, "Sam"))
	if err != nil {
		t.Fatal(err)
	}
	for _, m := range []string{"AAA", "BBB", "CCC"} {
		if strings.Count(boot, m) != 1 {
			t.Errorf("%s inlined %d times, want 1:\n%s", m, strings.Count(boot, m), boot)
		}
	}
}

// Invariant over generated import graphs (CONTRACT 0.3): whatever the
// graph, expansion terminates, inlines each file at most once, never nests
// deeper than MaxImportDepth and stays within MaxOutputBytes.
func TestMCP5_RandomImportGraphsInvariant(t *testing.T) {
	rng := rand.New(rand.NewSource(20261004))
	for g := 0; g < 60; g++ {
		root := t.TempDir()
		n := 2 + rng.Intn(12)
		name := func(i int) string { return fmt.Sprintf("f%02d.md", i) }
		for i := 0; i < n; i++ {
			var b strings.Builder
			fmt.Fprintf(&b, "MARK-%02d\n", i)
			for k := rng.Intn(10); k > 0; k-- {
				switch rng.Intn(6) {
				case 0:
					b.WriteString("@BOOT.md\n")
				case 1:
					b.WriteString("@../SamQA/BOOT.md\n")
				default:
					fmt.Fprintf(&b, "@%s\n", name(rng.Intn(n)))
				}
			}
			w(t, filepath.Join(root, "lib", name(i)), b.String())
		}
		boot := "You are **Sam**\nBOOT-MARK\n"
		for k := 1 + rng.Intn(5); k > 0; k-- {
			boot += fmt.Sprintf("@../lib/%s\n", name(rng.Intn(n)))
		}
		w(t, filepath.Join(root, "SamQA", "BOOT.md"), boot)
		tm := open(t, root)
		out, err := tm.Boot(mustSeat(t, tm, "Sam"))
		if err != nil {
			t.Fatalf("graph %d: %v", g, err)
		}
		if len(out) > MaxOutputBytes {
			t.Fatalf("graph %d: output %d bytes", g, len(out))
		}
		for i := 0; i < n; i++ {
			if c := strings.Count(out, fmt.Sprintf("MARK-%02d\n", i)); c > 1 {
				t.Fatalf("graph %d: file %d inlined %d times", g, i, c)
			}
		}
		if strings.Count(out, "BOOT-MARK") != 1 {
			t.Fatalf("graph %d: BOOT.md inlined into itself", g)
		}
		depth, max := 0, 0
		for _, line := range strings.Split(out, "\n") {
			if strings.HasPrefix(line, "<!-- imported from ") {
				depth++
			} else if strings.HasPrefix(line, "<!-- end ") {
				depth--
			}
			if depth > max {
				max = depth
			}
		}
		if max > MaxImportDepth {
			t.Fatalf("graph %d: nested %d deep", g, max)
		}
	}
}

// Three distinct 1 MiB imports overflow the 2 MiB output cap.
func TestMCP5_OutputCapAcrossDistinctImports(t *testing.T) {
	root := t.TempDir()
	chunk := strings.Repeat(strings.Repeat("y", 1023)+"\n", 1024) // exactly 1 MiB
	for _, n := range []string{"one", "two", "three"} {
		w(t, filepath.Join(root, n+".md"), chunk)
	}
	w(t, filepath.Join(root, "Sam - QA", "BOOT.md"), "boot\n@../one.md\n@../two.md\n@../three.md\n")
	tm := open(t, root)
	boot, err := tm.Boot(mustSeat(t, tm, "Sam"))
	if err != nil {
		t.Fatal(err)
	}
	if len(boot) > MaxOutputBytes {
		t.Errorf("boot is %d bytes, cap %d", len(boot), MaxOutputBytes)
	}
	if !strings.HasSuffix(boot, TruncMarker) {
		t.Errorf("boot does not end in the truncation marker: %q", boot[len(boot)-60:])
	}
}

func TestMCP10_FileReadCapped(t *testing.T) {
	root := t.TempDir()
	// 1.5 MiB of two-byte characters, after one byte so the 1 MiB cut
	// lands mid-character.
	big := strings.Repeat("é", (3<<20)/4)
	w(t, filepath.Join(root, "Sam - QA", "BOOT.md"), "x"+big)
	w(t, filepath.Join(root, "Sam - QA", "INBOX.md"), "## 2026-10-04 — From Nash\n"+big)
	tm := open(t, root)
	s := mustSeat(t, tm, "Sam")
	boot, err := tm.Boot(s)
	if err != nil {
		t.Fatal(err)
	}
	if len(boot) > MaxFileBytes+1+len(TruncMarker) || !strings.HasSuffix(boot, "\n"+TruncMarker) {
		t.Errorf("BOOT.md not capped: %d bytes", len(boot))
	}
	if len(boot) < MaxFileBytes-4 {
		t.Errorf("cap cut too much: %d bytes", len(boot))
	}
	if !utf8.ValidString(boot) {
		t.Error("cap split a character")
	}
	entries, err := tm.Inbox(s, false)
	if err != nil || len(entries) != 1 || !strings.HasSuffix(entries[0].Body, TruncMarker) {
		t.Errorf("INBOX.md not capped: %d entries, err %v", len(entries), err)
	}
}

func TestMCP10_CapHelper(t *testing.T) {
	if Cap("short", 100) != "short" {
		t.Error("Cap changed a short string")
	}
	got := Cap(strings.Repeat("a", 500), 100)
	if len(got) > 100 || !strings.HasSuffix(got, "\n"+TruncMarker) {
		t.Errorf("Cap = %q", got)
	}
	if got := Cap(strings.Repeat("a", 50), 10); got != "\n"+TruncMarker {
		t.Errorf("Cap below the marker size = %q", got)
	}
}

// ---- MCP-8: duplicate short names ------------------------------------

func TestMCP8_DuplicateShortNameIsAnError(t *testing.T) {
	root := t.TempDir()
	w(t, filepath.Join(root, "Sam - QA", "BOOT.md"), "# qa")
	w(t, filepath.Join(root, "Sam - Dev", "BOOT.md"), "# dev")
	w(t, filepath.Join(root, "Alex - Boss", "BOOT.md"), "# boss")
	tm := open(t, root)
	_, err := tm.Seat("sam")
	if !errors.Is(err, ErrAmbiguousSeat) {
		t.Fatalf("Seat(sam) err = %v, want ErrAmbiguousSeat", err)
	}
	for _, f := range []string{`"Sam - QA"`, `"Sam - Dev"`} {
		if !strings.Contains(err.Error(), f) {
			t.Errorf("error does not name %s: %v", f, err)
		}
	}
	if s, err := tm.Seat("sam - dev"); err != nil || s.Folder != "Sam - Dev" {
		t.Errorf("full folder name must still resolve: %+v %v", s, err)
	}
	for i := 0; i < 20; i++ {
		seats, _ := tm.Seats()
		var got []string
		for _, s := range seats {
			got = append(got, s.Folder)
		}
		if strings.Join(got, ",") != "Alex - Boss,Sam - Dev,Sam - QA" {
			t.Fatalf("unstable order: %v", got)
		}
	}
}

// ---- MCP-9: no absolute host paths -------------------------------------

func TestMCP9_NoAbsolutePathsInBootOrErrors(t *testing.T) {
	base := t.TempDir()
	root := filepath.Join(base, "team")
	w(t, filepath.Join(root, "Sam - QA", "BOOT.md"), "# b\n@../missing.md\n@../dir.md\n@../../outside.md\n")
	if err := os.MkdirAll(filepath.Join(root, "dir.md"), 0o755); err != nil {
		t.Fatal(err)
	}
	w(t, filepath.Join(base, "outside.md"), "x")
	tm := open(t, root)
	leaks := func(s string) bool {
		for _, p := range []string{base, filepath.ToSlash(base), tm.Root, tm.real, filepath.ToSlash(tm.real)} {
			if strings.Contains(s, p) {
				return true
			}
		}
		return false
	}
	boot, err := tm.Boot(mustSeat(t, tm, "Sam"))
	if err != nil {
		t.Fatal(err)
	}
	if leaks(boot) {
		t.Errorf("boot leaks an absolute path:\n%s", boot)
	}
	if !strings.Contains(boot, "[import ../missing.md not loaded: file not found]") {
		t.Errorf("missing import not reported:\n%s", boot)
	}
	// Every error the package composes for a missing or odd seat file.
	ghost := Seat{Name: "Ghost", Folder: "Ghost - Seat"}
	for _, call := range []func() error{
		func() error { _, err := tm.Boot(ghost); return err },
		func() error { _, err := tm.Seats(); return err },
	} {
		if err := call(); err != nil && leaks(err.Error()) {
			t.Errorf("error leaks an absolute path: %v", err)
		}
	}
	if _, err := tm.Boot(ghost); err == nil || !strings.Contains(err.Error(), RootToken) {
		t.Errorf("missing BOOT.md error should name %s: %v", RootToken, err)
	}
	if got := tm.Redact("at " + tm.Root + " and " + filepath.ToSlash(tm.Root)); got != "at "+RootToken+" and "+RootToken {
		t.Errorf("Redact = %q", got)
	}
}

// ---- MCP-13: seat name from BOOT.md ------------------------------------

func TestMCP13_SeatNameFromBootLine(t *testing.T) {
	root := t.TempDir()
	w(t, filepath.Join(root, "QA Tester", "BOOT.md"), "# BOOT\n\nYou are **Sam**, the QA seat.\n")
	w(t, filepath.Join(root, "Nash - Developer", "BOOT.md"), "You are **Nash**, codename **WRENCH**.\n")
	w(t, filepath.Join(root, "Plain", "BOOT.md"), "no identity line\n")
	w(t, filepath.Join(root, "Dana - Ops", "BOOT.md"), "no identity line\n")
	w(t, filepath.Join(root, "Evil - Seat", "BOOT.md"), "You are **../_Family**\n")
	tm := open(t, root)
	seats, err := tm.Seats()
	if err != nil {
		t.Fatal(err)
	}
	var got []string
	for _, s := range seats {
		got = append(got, s.Name+"|"+s.Role+"|"+s.Folder)
	}
	want := "Dana|Ops|Dana - Ops,Evil|Seat|Evil - Seat,Nash|Developer|Nash - Developer,Plain||Plain,Sam|QA Tester|QA Tester"
	if strings.Join(got, ",") != want {
		t.Errorf("seats =\n%s\nwant\n%s", strings.Join(got, ","), want)
	}
	if s, err := tm.Seat("sam"); err != nil || s.Folder != "QA Tester" {
		t.Errorf("Seat(sam) = %+v %v", s, err)
	}
}

// ---- MCP-12: no log-only probe remains ---------------------------------

// TestMCP12_NoLogOnlyTests parses every test file in the module and fails
// on any Test function that logs but never reports a failure itself or
// through a helper that takes t.
func TestMCP12_NoLogOnlyTests(t *testing.T) {
	var files []string
	for _, dir := range []string{".", "..", filepath.Join("..", "firmware")} {
		m, err := filepath.Glob(filepath.Join(dir, "*_test.go"))
		if err != nil {
			t.Fatal(err)
		}
		files = append(files, m...)
	}
	if len(files) < 4 {
		t.Fatalf("found only %d test files", len(files))
	}
	fset := token.NewFileSet()
	checked := 0
	for _, f := range files {
		file, err := parser.ParseFile(fset, f, nil, 0)
		if err != nil {
			t.Fatal(err)
		}
		for _, d := range file.Decls {
			fn, ok := d.(*ast.FuncDecl)
			if !ok || !strings.HasPrefix(fn.Name.Name, "Test") || fn.Body == nil {
				continue
			}
			checked++
			logs, asserts := false, false
			ast.Inspect(fn.Body, func(n ast.Node) bool {
				call, ok := n.(*ast.CallExpr)
				if !ok {
					return true
				}
				if sel, ok := call.Fun.(*ast.SelectorExpr); ok {
					if id, ok := sel.X.(*ast.Ident); ok && id.Name == "t" {
						switch sel.Sel.Name {
						case "Log", "Logf":
							logs = true
						case "Error", "Errorf", "Fatal", "Fatalf", "Fail", "FailNow", "Run":
							asserts = true
						}
					}
				}
				for _, a := range call.Args {
					if id, ok := a.(*ast.Ident); ok && id.Name == "t" {
						asserts = true // a helper that takes t reports through it
					}
				}
				return true
			})
			if logs && !asserts {
				t.Errorf("%s: %s logs but never asserts", filepath.Base(f), fn.Name.Name)
			}
			if !asserts {
				t.Errorf("%s: %s has no assertion", filepath.Base(f), fn.Name.Name)
			}
		}
	}
	if checked < 20 {
		t.Errorf("checked only %d tests", checked)
	}
}

// A link loop is refused, never followed forever.
func TestMCP4_LinkLoopRefused(t *testing.T) {
	root := t.TempDir()
	w(t, filepath.Join(root, "Sam - QA", "BOOT.md"), "# b\n@../loop/a/x.md\n")
	link(t, filepath.Join(root, "loop"), filepath.Join(root, "loop2"))
	link(t, filepath.Join(root, "loop2"), filepath.Join(root, "loop"))
	tm := open(t, root)
	boot, err := tm.Boot(mustSeat(t, tm, "Sam"))
	if err != nil {
		t.Fatal(err)
	}
	if !strings.Contains(boot, "[import ../loop/a/x.md not loaded: ") || strings.Contains(boot, root) {
		t.Errorf("loop import:\n%s", boot)
	}
	seats, err := tm.Seats()
	if err != nil || len(seats) != 1 {
		t.Errorf("seats = %v %v", seats, err)
	}
}

func TestMCP4_WithinAndOpen(t *testing.T) {
	root := t.TempDir()
	if within(root, "relative") {
		t.Error("within accepted a relative path against an absolute root")
	}
	if !within(root, root) || within(root, filepath.Dir(root)) || !within(root, filepath.Join(root, "a", "b")) {
		t.Error("within basic cases")
	}
	if within(root, root+"x") {
		t.Error("within accepted a sibling sharing the prefix")
	}
	file := filepath.Join(root, "f.md")
	w(t, file, "x")
	if _, err := Open(file); err == nil || !strings.Contains(err.Error(), "not a folder") {
		t.Errorf("Open(file) err = %v", err)
	}
	gone := filepath.Join(root, "gone")
	w(t, filepath.Join(gone, "Sam - QA", "BOOT.md"), "# b")
	tm := open(t, gone)
	if err := os.RemoveAll(gone); err != nil {
		t.Fatal(err)
	}
	if _, err := tm.Seats(); err == nil || strings.Contains(err.Error(), gone) {
		t.Errorf("Seats on a vanished root: %v", err)
	}
	if _, err := tm.Seat("Sam"); err == nil {
		t.Error("Seat on a vanished root: want error")
	}
}

func TestMCP9_RedactErr(t *testing.T) {
	tm := open(t, t.TempDir())
	if tm.redactErr(nil) != nil {
		t.Error("nil error changed")
	}
	plain := errors.New("plain")
	if tm.redactErr(plain) != plain {
		t.Error("an error with no path was rewritten")
	}
	wrapped := fmt.Errorf("reading %s: %w", tm.Root, os.ErrPermission)
	got := tm.redactErr(wrapped)
	if strings.Contains(got.Error(), tm.Root) || !strings.Contains(got.Error(), RootToken) || !errors.Is(got, os.ErrPermission) {
		t.Errorf("wrapped: %v", got)
	}
	// macOS shape: the resolved root contains the given one.
	mac := &Team{Root: "/var/folders/x/team", real: "/private/var/folders/x/team"}
	if got := mac.Redact("/private/var/folders/x/team/a and /var/folders/x/team/b"); got != RootToken+"/a and "+RootToken+"/b" {
		t.Errorf("macOS redact = %q", got)
	}
	rev := &Team{Root: "/private/var/folders/x/team", real: "/var/folders/x/team"}
	if got := rev.Redact("/private/var/folders/x/team/a"); got != RootToken+"/a" {
		t.Errorf("reverse redact = %q", got)
	}
	_, perr := os.ReadFile(filepath.Join(tm.Root, "nope.md"))
	got = tm.redactErr(perr)
	if strings.Contains(got.Error(), tm.Root) || !errors.Is(got, os.ErrNotExist) {
		t.Errorf("path error: %v", got)
	}
}

// walkLinks runs on every OS in this test (realPath uses it only on
// Windows), so both resolvers are proven against the same links: a linked
// folder, a link to a link, and a loop.
func TestMCP4_WalkLinksResolvesLikeTheOS(t *testing.T) {
	base := t.TempDir()
	target := filepath.Join(base, "target")
	w(t, filepath.Join(target, "f.md"), "x")
	link(t, filepath.Join(base, "l1"), target)
	link(t, filepath.Join(base, "l2"), filepath.Join(base, "l1"))
	want, err := realPath(filepath.Join(target, "f.md"))
	if err != nil {
		t.Fatal(err)
	}
	for _, p := range []string{"l1", "l2"} {
		hops := 0
		got, err := walkLinks(filepath.Join(base, p, "f.md"), &hops)
		if err != nil || got != want {
			t.Errorf("walkLinks via %s = %q %v, want %q", p, got, err, want)
		}
		if viaOS, err := realPath(filepath.Join(base, p, "f.md")); err != nil || viaOS != want {
			t.Errorf("realPath via %s = %q %v", p, viaOS, err)
		}
	}
	link(t, filepath.Join(base, "a"), filepath.Join(base, "b"))
	link(t, filepath.Join(base, "b"), filepath.Join(base, "a"))
	hops := 0
	if _, err := walkLinks(filepath.Join(base, "a", "f.md"), &hops); err == nil {
		t.Error("walkLinks followed a loop without error")
	}
	hops = 0
	if _, err := walkLinks(filepath.Join(base, "missing", "f.md"), &hops); !errors.Is(err, os.ErrNotExist) {
		t.Errorf("missing path: %v", err)
	}
}

// A link-like component whose target cannot be read is refused, never
// walked through as a plain file (A-5). A regular file makes os.Readlink
// fail on every OS, which is the same failure an undecodable reparse point
// produces.
func TestMCP4_UnreadableLinkFailsClosed(t *testing.T) {
	dir := t.TempDir()
	plain := filepath.Join(dir, "plain.md")
	w(t, plain, "x")
	if _, err := linkTarget(plain); !errors.Is(err, errUnreadableLink) {
		t.Errorf("linkTarget(regular file) err = %v, want errUnreadableLink", err)
	}
	link(t, filepath.Join(dir, "l"), dir)
	if got, err := linkTarget(filepath.Join(dir, "l")); err != nil || got == "" {
		t.Errorf("linkTarget(real link) = %q %v", got, err)
	}
	for _, c := range []struct {
		mode fs.FileMode
		want bool
	}{{fs.ModeSymlink, true}, {fs.ModeIrregular, true}, {fs.ModeDir, false}, {0, false}} {
		if isLinkLike(c.mode) != c.want {
			t.Errorf("isLinkLike(%v) = %v", c.mode, !c.want)
		}
	}
	// Real undecodable reparse points, wherever the host has them: Windows
	// app execution aliases are irregular and os.Readlink cannot read them.
	aliases, _ := filepath.Glob(filepath.Join(os.Getenv("LOCALAPPDATA"), "Microsoft", "WindowsApps", "*.exe"))
	for _, a := range aliases {
		info, err := os.Lstat(a)
		if err != nil || !isLinkLike(info.Mode()) {
			continue
		}
		if _, err := os.Readlink(a); err == nil {
			continue
		}
		hops := 0
		if got, err := walkLinks(a, &hops); !errors.Is(err, errUnreadableLink) {
			t.Errorf("walkLinks(%s) = %q %v, want refusal", filepath.Base(a), got, err)
		}
	}
}
