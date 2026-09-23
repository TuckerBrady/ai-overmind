package firmware

import (
	"os"
	"strings"
	"testing"
)

func TestEmbeddedCopyMatchesPluginFirmware(t *testing.T) {
	src, err := os.ReadFile("../../hooks/firmware.md")
	if err != nil {
		t.Skip("plugin firmware not beside this module:", err)
	}
	if string(src) != Text {
		t.Fatal("firmware/firmware.md has drifted from hooks/firmware.md; run build.sh (or go generate ./...)")
	}
}

func TestSectionsSplitOnlyTopLevelHeadings(t *testing.T) {
	titles := map[string]bool{}
	var total int
	for _, s := range Sections() {
		titles[s.Title] = true
		total += len(s.Body)
	}
	for _, want := range []string{"PREAMBLE", "TARS — THE TURN HOOK", "FEATURE 2 — DISPATCH", "YOUR VOICE"} {
		if !titles[want] {
			t.Errorf("missing section %q", want)
		}
	}
	// Headings inside fenced templates must not become sections.
	for _, bad := range []string{"MISSION", "DONE WHEN — RUBRIC", "Initiative setting: [N]%"} {
		if titles[bad] {
			t.Errorf("template heading %q was split out as a section", bad)
		}
	}
	if total < len(strings.ReplaceAll(Text, "\r\n", "\n")) {
		t.Error("sections dropped text")
	}
}

func TestFind(t *testing.T) {
	if s, ok := Find("tars"); !ok || s.Title != "TARS — THE TURN HOOK" {
		t.Errorf("Find(tars) = %q %v", s.Title, ok)
	}
	if _, ok := Find("no such section"); ok {
		t.Error("Find matched nonsense")
	}
	if _, ok := Find(""); ok {
		t.Error("Find matched empty query")
	}
}
