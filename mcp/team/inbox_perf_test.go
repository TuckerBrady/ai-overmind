package team

import (
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"
)

// A-16 (OPS-030 release lane): a 1 MiB inbox parses in under 2 s. Before the
// strings.Builder change each body line copied the whole body so far, which
// took 27 s on a 1.5 MiB inbox.
func TestInboxOneMiBParsesUnderTwoSeconds(t *testing.T) {
	root := t.TempDir()
	seat := filepath.Join(root, "Sam - QA")
	if err := os.MkdirAll(seat, 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(seat, "BOOT.md"), []byte("# BOOT\n"), 0o644); err != nil {
		t.Fatal(err)
	}
	var b strings.Builder
	b.WriteString("## 2026-10-05 — From Nash — UNREAD\n")
	line := "short body line 0123\n"
	for b.Len()+len(line) <= MaxFileBytes {
		b.WriteString(line)
	}
	if err := os.WriteFile(filepath.Join(seat, "INBOX.md"), []byte(b.String()), 0o644); err != nil {
		t.Fatal(err)
	}
	tm, err := Open(root)
	if err != nil {
		t.Fatal(err)
	}
	s, err := tm.Seat("Sam")
	if err != nil {
		t.Fatal(err)
	}
	start := time.Now()
	got, err := tm.Inbox(s, false)
	el := time.Since(start)
	if err != nil {
		t.Fatal(err)
	}
	if len(got) != 1 || len(got[0].Body) < MaxFileBytes-len(line)-64 {
		t.Fatalf("entries=%d body=%d bytes", len(got), len(got[0].Body))
	}
	if el > 2*time.Second {
		t.Errorf("1 MiB inbox took %v, want under 2 s", el)
	}
}
