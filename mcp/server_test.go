package main

import (
	"bytes"
	"context"
	"os"
	"os/exec"
	"path/filepath"
	"regexp"
	"runtime"
	"sort"
	"strings"
	"testing"
	"time"

	"github.com/TuckerBrady/ai-overmind/mcp/firmware"
	"github.com/TuckerBrady/ai-overmind/mcp/team"
	"github.com/modelcontextprotocol/go-sdk/mcp"
)

var fixtureRoot = filepath.Join("testdata", "team")

var wantTools = []string{"board", "boot", "firmware", "handoff", "inbox", "roster"}

func connect(t *testing.T, defaultSeat string) *mcp.ClientSession {
	t.Helper()
	tm, err := team.Open(fixtureRoot)
	if err != nil {
		t.Fatal(err)
	}
	srv, err := newServer(tm, config{version: "test", defaultSeat: defaultSeat})
	if err != nil {
		t.Fatal(err)
	}
	ct, st := mcp.NewInMemoryTransports()
	ctx := context.Background()
	if _, err := srv.Connect(ctx, st, nil); err != nil {
		t.Fatal(err)
	}
	cs, err := mcp.NewClient(&mcp.Implementation{Name: "test"}, nil).Connect(ctx, ct, nil)
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { cs.Close() })
	return cs
}

func call(t *testing.T, cs *mcp.ClientSession, name string, args map[string]any) (string, bool) {
	t.Helper()
	res, err := cs.CallTool(context.Background(), &mcp.CallToolParams{Name: name, Arguments: args})
	if err != nil {
		t.Fatalf("%s: %v", name, err)
	}
	var b strings.Builder
	for _, c := range res.Content {
		if tc, ok := c.(*mcp.TextContent); ok {
			b.WriteString(tc.Text)
		}
	}
	return b.String(), res.IsError
}

func toolNames(t *testing.T, cs *mcp.ClientSession) []string {
	t.Helper()
	res, err := cs.ListTools(context.Background(), nil)
	if err != nil {
		t.Fatal(err)
	}
	var names []string
	for _, tl := range res.Tools {
		names = append(names, tl.Name)
	}
	sort.Strings(names)
	return names
}

func TestInstructionsNameEverySeatAndSayBootFirst(t *testing.T) {
	ir := connect(t, "").InitializeResult()
	for _, want := range []string{"call boot", "Otherwise leave these tools alone", "Alex-Bot", "Sam"} {
		if !strings.Contains(ir.Instructions, want) {
			t.Errorf("instructions missing %q: %s", want, ir.Instructions)
		}
	}
	withSeat := connect(t, "Sam").InitializeResult().Instructions
	if !strings.Contains(withSeat, `call boot with seat "Sam"`) {
		t.Errorf("default-seat instructions: %s", withSeat)
	}
}

func TestListsSixTools(t *testing.T) {
	got := strings.Join(toolNames(t, connect(t, "")), ",")
	if got != strings.Join(wantTools, ",") {
		t.Errorf("tools = %s", got)
	}
}

func TestBootToolAppendsRuntimeNote(t *testing.T) {
	cs := connect(t, "")
	text, isErr := call(t, cs, "boot", map[string]any{"seat": "Alex-Bot"})
	if isErr {
		t.Fatal(text)
	}
	for _, want := range []string{"You are **Alex-Bot**", "Alex prefers answers first", "TARS: UNAVAILABLE (MCP client - no hooks)"} {
		if !strings.Contains(text, want) {
			t.Errorf("boot missing %q", want)
		}
	}
}

func TestBootUsesDefaultSeat(t *testing.T) {
	text, isErr := call(t, connect(t, "Sam"), "boot", nil)
	if isErr || !strings.Contains(text, "You are **Sam**") {
		t.Errorf("default seat boot: %v %s", isErr, text)
	}
}

func TestToolsRefuseBadSeats(t *testing.T) {
	cs := connect(t, "")
	for _, tool := range []string{"boot", "handoff", "inbox", "board"} {
		text, isErr := call(t, cs, tool, map[string]any{"seat": "../_Family"})
		if !isErr || !strings.Contains(text, "unknown seat") {
			t.Errorf("%s accepted a path: %s", tool, text)
		}
	}
	// With no default seat, an empty seat is refused too.
	if _, isErr := call(t, cs, "boot", nil); !isErr {
		t.Error("boot with no seat and no default: want error")
	}
}

func TestReadTools(t *testing.T) {
	cs := connect(t, "Alex-Bot")
	cases := []struct {
		tool string
		args map[string]any
		want []string
		not  []string
	}{
		{"roster", nil, []string{`"name": "Alex-Bot"`, `"role": "QA Tester"`}, []string{"_Family"}},
		{"board", map[string]any{"seat": "Sam"}, []string{"M-001", "M-002"}, []string{"M-003", "M-004"}},
		{"board", map[string]any{"all": true}, []string{"M-003"}, []string{"M-000"}},
		{"handoff", nil, []string{"Ship the report", `"copies_differ": true`}, nil},
		{"handoff", map[string]any{"seat": "Sam"}, []string{"No handoff staged for Sam."}, nil},
		{"inbox", map[string]any{"unread_only": true}, []string{"flaky test", "Untagged"}, []string{"Old note"}},
		{"firmware", nil, []string{"- TARS — THE TURN HOOK"}, nil},
		{"firmware", map[string]any{"section": "tars"}, []string{"## TARS — THE TURN HOOK"}, []string{"## FEATURE 1"}},
	}
	for _, c := range cases {
		text, isErr := call(t, cs, c.tool, c.args)
		if isErr {
			t.Errorf("%s %v: error %s", c.tool, c.args, text)
			continue
		}
		for _, w := range c.want {
			if !strings.Contains(text, w) {
				t.Errorf("%s %v: missing %q", c.tool, c.args, w)
			}
		}
		for _, n := range c.not {
			if strings.Contains(text, n) {
				t.Errorf("%s %v: should not contain %q", c.tool, c.args, n)
			}
		}
	}
	if text, isErr := call(t, cs, "firmware", map[string]any{"section": "nonsense"}); !isErr {
		t.Errorf("unknown firmware section accepted: %s", text)
	}
}

func TestBootResourceAndPrompt(t *testing.T) {
	cs := connect(t, "")
	ctx := context.Background()
	res, err := cs.ReadResource(ctx, &mcp.ReadResourceParams{URI: "overmind://seat/Alex-Bot/boot"})
	if err != nil || !strings.Contains(res.Contents[0].Text, "You are **Alex-Bot**") {
		t.Errorf("resource: %v", err)
	}
	if _, err := cs.ReadResource(ctx, &mcp.ReadResourceParams{URI: "overmind://seat/..%2F_Family/boot"}); err == nil {
		t.Error("resource accepted an escaped path")
	}
	p, err := cs.GetPrompt(ctx, &mcp.GetPromptParams{Name: "boot", Arguments: map[string]string{"seat": "Sam"}})
	if err != nil {
		t.Fatal(err)
	}
	if tc, ok := p.Messages[0].Content.(*mcp.TextContent); !ok || !strings.Contains(tc.Text, "You are now booted as Sam") {
		t.Errorf("prompt text: %+v", p.Messages[0].Content)
	}
}

// TestBinaryOverStdio builds the real binary and drives it the way an MCP
// client does: spawn, handshake over stdio, list tools, call boot.
func TestBinaryOverStdio(t *testing.T) {
	if testing.Short() {
		t.Skip("builds a binary")
	}
	bin := filepath.Join(t.TempDir(), "overmind-mcp")
	if runtime.GOOS == "windows" {
		bin += ".exe"
	}
	if out, err := exec.Command("go", "build", "-o", bin, ".").CombinedOutput(); err != nil {
		t.Fatalf("build: %v\n%s", err, out)
	}
	root, _ := filepath.Abs(fixtureRoot)
	ctx := context.Background()
	cs, err := mcp.NewClient(&mcp.Implementation{Name: "e2e"}, nil).
		Connect(ctx, &mcp.CommandTransport{Command: exec.Command(bin, "--root", root, "--seat", "Alex-Bot")}, nil)
	if err != nil {
		t.Fatal(err)
	}
	defer cs.Close()
	if got := strings.Join(toolNames(t, cs), ","); got != strings.Join(wantTools, ",") {
		t.Errorf("tools over stdio = %s", got)
	}
	text, isErr := call(t, cs, "boot", nil)
	if isErr || !strings.Contains(text, "You are **Alex-Bot**") {
		t.Errorf("boot over stdio: %v %s", isErr, text)
	}
}

func TestBinaryRefusesBadRoot(t *testing.T) {
	if testing.Short() {
		t.Skip("builds a binary")
	}
	out, err := exec.Command("go", "run", ".", "--root", filepath.Join(t.TempDir(), "missing")).CombinedOutput()
	if err == nil || !strings.Contains(string(out), "team root") {
		t.Errorf("bad root: err=%v out=%s", err, out)
	}
}

// ---- OPS-030 L5: MCP-5..10 and 13 through the tools a client calls, and
// the run() entry point main uses. ----------------------------------------

var engineLine = regexp.MustCompile(`^Engine: overmind-mcp [^ ,]+, firmware sha256 [0-9a-f]{12}\.$`)
var warningLine = regexp.MustCompile(`^WARNING: installed plugin firmware sha256 [0-9a-f]{12} differs from this server's [0-9a-f]{12}\. Rebuild or update overmind-mcp\.$`)

func writeFile(t *testing.T, p, s string) {
	t.Helper()
	if err := os.MkdirAll(filepath.Dir(p), 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(p, []byte(s), 0o644); err != nil {
		t.Fatal(err)
	}
}

// connectTo serves an arbitrary team root with an arbitrary config.
func connectTo(t *testing.T, root string, cfg config) *mcp.ClientSession {
	t.Helper()
	tm, err := team.Open(root)
	if err != nil {
		t.Fatal(err)
	}
	srv, err := newServer(tm, cfg)
	if err != nil {
		t.Fatal(err)
	}
	ct, st := mcp.NewInMemoryTransports()
	ctx := context.Background()
	if _, err := srv.Connect(ctx, st, nil); err != nil {
		t.Fatal(err)
	}
	cs, err := mcp.NewClient(&mcp.Implementation{Name: "test"}, nil).Connect(ctx, ct, nil)
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { cs.Close() })
	return cs
}

func lines(s string) []string { return strings.Split(strings.TrimRight(s, "\n"), "\n") }

func tail(s string, n int) []string {
	ls := lines(s)
	if len(ls) < n {
		return ls
	}
	return ls[len(ls)-n:]
}

// modifiedPluginTree is a v5-shaped plugin folder whose firmware differs
// from the embedded copy.
func modifiedPluginTree(t *testing.T) string {
	t.Helper()
	root := t.TempDir()
	writeFile(t, filepath.Join(root, "hooks", "kernel.md"), "**Identity.** a modified kernel\nEND OF KERNEL v5\n")
	writeFile(t, filepath.Join(root, "reference", "tars.md"), "# TARS\n")
	return root
}

// ---- MCP-6: firmware identity at boot ----------------------------------

func TestMCP6_BootEndsWithEngineLine(t *testing.T) {
	text, isErr := call(t, connect(t, ""), "boot", map[string]any{"seat": "Alex-Bot"})
	if isErr {
		t.Fatal(text)
	}
	last := tail(text, 1)[0]
	if !engineLine.MatchString(last) {
		t.Fatalf("last line = %q", last)
	}
	if want := "Engine: overmind-mcp test, firmware sha256 " + firmware.Hash()[:12] + "."; last != want {
		t.Errorf("last line = %q, want %q", last, want)
	}
	if strings.Contains(text, "WARNING:") {
		t.Error("WARNING without a plugin root")
	}
	if !strings.Contains(text, "Call firmware with no section for\n  the topic index") {
		t.Error("runtime note does not point at the topic index")
	}
}

func TestMCP6_ModifiedPluginTreeWarns(t *testing.T) {
	plugin := modifiedPluginTree(t)
	theirs, err := firmware.HashDir(plugin)
	if err != nil {
		t.Fatal(err)
	}
	text, _ := call(t, connectTo(t, fixtureRoot, config{version: "5.0.0", pluginRoot: plugin}), "boot", map[string]any{"seat": "Sam"})
	tl := tail(text, 2)
	if len(tl) < 2 || !warningLine.MatchString(tl[0]) || !engineLine.MatchString(tl[1]) {
		t.Fatalf("tail = %q", tl)
	}
	want := "WARNING: installed plugin firmware sha256 " + theirs[:12] + " differs from this server's " + firmware.Hash()[:12] + ". Rebuild or update overmind-mcp."
	if tl[0] != want {
		t.Errorf("warning = %q, want %q", tl[0], want)
	}
	if strings.Contains(text, plugin) || strings.Contains(text, filepath.ToSlash(plugin)) {
		t.Error("boot text leaks the plugin path")
	}
}

func TestMCP6_UnreadablePluginRootDoesNotWarn(t *testing.T) {
	text, _ := call(t, connectTo(t, fixtureRoot, config{version: "x", pluginRoot: t.TempDir()}), "boot", map[string]any{"seat": "Sam"})
	if strings.Contains(text, "WARNING:") || !engineLine.MatchString(tail(text, 1)[0]) {
		t.Errorf("tail = %q", tail(text, 2))
	}
}

// OVERMIND_PLUGIN_ROOT reaches the boot through run(), the real entry point.
func TestMCP6_PluginRootFromEnvironment(t *testing.T) {
	t.Setenv("OVERMIND_PLUGIN_ROOT", modifiedPluginTree(t))
	root, _ := filepath.Abs(fixtureRoot)
	cs := runInMemory(t, []string{"--root", root, "--seat", "Sam"})
	text, isErr := call(t, cs, "boot", nil)
	tl := tail(text, 2)
	if isErr || len(tl) < 2 || !warningLine.MatchString(tl[0]) || !engineLine.MatchString(tl[1]) {
		t.Errorf("tail = %q", tl)
	}
}

// ---- MCP-7: every firmware topic is reachable by its listed title ------

func TestMCP7_FirmwareTopicsReachableByTitle(t *testing.T) {
	cs := connect(t, "")
	index, isErr := call(t, cs, "firmware", nil)
	if isErr {
		t.Fatal(index)
	}
	secs := firmware.Sections()
	ls := lines(index)
	if !strings.Contains(ls[0], "topic index") || len(ls)-1 != len(secs) {
		t.Fatalf("index has %d entries for %d topics: %q", len(ls)-1, len(secs), ls[0])
	}
	// Rebuild the 7.5 concatenation from what the tool returned: each
	// topic's "=== <relpath>" header, then its body. It must equal the
	// embedded firmware byte for byte, so no text is unreachable.
	var rebuilt strings.Builder
	for i, l := range ls[1:] {
		title := strings.TrimPrefix(l, "- ")
		if title != secs[i].Title {
			t.Errorf("index entry %d = %q, want %q", i, title, secs[i].Title)
		}
		var got string
		for _, q := range []string{title, strings.ToLower(title)} {
			body, isErr := call(t, cs, "firmware", map[string]any{"section": q})
			if isErr || body != secs[i].Body {
				t.Errorf("firmware(%q) did not return its own topic", q)
			}
			got = body
		}
		rebuilt.WriteString("=== " + secs[i].File + "\n" + got)
	}
	if rebuilt.String() != firmware.Text {
		t.Error("the topics the tool returns do not rebuild the whole firmware")
	}
}

// ---- MCP-5 and MCP-10: caps hold through the tools ---------------------

func TestMCP5_BootToolOutputCapped(t *testing.T) {
	root := t.TempDir()
	chunk := strings.Repeat(strings.Repeat("y", 1023)+"\n", 1024)
	for _, n := range []string{"one", "two", "three"} {
		writeFile(t, filepath.Join(root, n+".md"), chunk)
	}
	writeFile(t, filepath.Join(root, "Sam - QA", "BOOT.md"), "You are **Sam**\n@../one.md\n@../two.md\n@../three.md\n")
	text, isErr := call(t, connectTo(t, root, config{version: "t"}), "boot", map[string]any{"seat": "Sam"})
	if isErr {
		t.Fatal(text)
	}
	if len(text) > team.MaxOutputBytes {
		t.Errorf("boot tool output %d bytes > %d", len(text), team.MaxOutputBytes)
	}
	if !strings.Contains(text, team.TruncMarker+"\n\n---\n\n## RUNTIME NOTE") {
		t.Error("truncation marker missing before the runtime note")
	}
	if !engineLine.MatchString(tail(text, 1)[0]) {
		t.Error("Engine line lost to truncation")
	}
}

func TestMCP10_ToolResultsCapped(t *testing.T) {
	big := strings.Repeat("z", team.MaxOutputBytes*2)
	got := textResult(big).Content[0].(*mcp.TextContent).Text
	if len(got) > team.MaxOutputBytes || !strings.HasSuffix(got, team.TruncMarker) {
		t.Errorf("textResult not capped: %d bytes", len(got))
	}
	// A quote-heavy inbox doubles in JSON and must still come back capped.
	root := t.TempDir()
	writeFile(t, filepath.Join(root, "Sam - QA", "BOOT.md"), "# b")
	writeFile(t, filepath.Join(root, "Sam - QA", "INBOX.md"), "## 2026-10-04 — From Nash\n"+strings.Repeat(`"`, team.MaxFileBytes))
	text, isErr := call(t, connectTo(t, root, config{version: "t"}), "inbox", map[string]any{"seat": "Sam"})
	if isErr || len(text) > team.MaxOutputBytes || !strings.HasSuffix(text, team.TruncMarker) {
		t.Errorf("inbox tool output %d bytes, err=%v", len(text), isErr)
	}
}

// ---- MCP-8: duplicate short names --------------------------------------

func TestMCP8_AmbiguousSeatErrorsNameBothFolders(t *testing.T) {
	root := t.TempDir()
	writeFile(t, filepath.Join(root, "Sam - QA", "BOOT.md"), "# qa")
	writeFile(t, filepath.Join(root, "Sam - Dev", "BOOT.md"), "# dev")
	text, isErr := call(t, connectTo(t, root, config{version: "t"}), "boot", map[string]any{"seat": "Sam"})
	if !isErr || !strings.Contains(text, `"Sam - Dev"`) || !strings.Contains(text, `"Sam - QA"`) {
		t.Errorf("boot(Sam): %v %s", isErr, text)
	}
	err := run(context.Background(), []string{"--root", root, "--seat", "sam"}, &bytes.Buffer{}, nil)
	if err == nil || !strings.Contains(err.Error(), "Sam - Dev") || !strings.Contains(err.Error(), "Sam - QA") {
		t.Errorf("run --seat sam: %v", err)
	}
}

// ---- MCP-9: no absolute host path in tool output ---------------------

func TestMCP9_NoAbsolutePathInToolOutput(t *testing.T) {
	abs, err := filepath.Abs("testdata")
	if err != nil {
		t.Fatal(err)
	}
	cs := connect(t, "Alex-Bot")
	for _, c := range []struct {
		tool string
		args map[string]any
	}{
		{"boot", nil}, {"roster", nil}, {"board", nil}, {"handoff", nil}, {"inbox", nil},
		{"boot", map[string]any{"seat": "Nobody"}}, {"firmware", map[string]any{"section": "nonsense"}},
	} {
		text, _ := call(t, cs, c.tool, c.args)
		if strings.Contains(text, abs) || strings.Contains(text, filepath.ToSlash(abs)) {
			t.Errorf("%s %v leaks %s", c.tool, c.args, abs)
		}
	}
	// A read error names the file under <team-root>, not the host path.
	root := t.TempDir()
	writeFile(t, filepath.Join(root, "Sam - QA", "BOOT.md"), "# b\n@../gone.md\n")
	if err := os.MkdirAll(filepath.Join(root, "Sam - QA", "INBOX.md"), 0o755); err != nil {
		t.Fatal(err)
	}
	cs2 := connectTo(t, root, config{version: "t"})
	text, isErr := call(t, cs2, "inbox", map[string]any{"seat": "Sam"})
	if !isErr || strings.Contains(text, root) || strings.Contains(text, filepath.ToSlash(root)) || !strings.Contains(text, team.RootToken) {
		t.Errorf("inbox read error: %v %q", isErr, text)
	}
	text, _ = call(t, cs2, "boot", map[string]any{"seat": "Sam"})
	if strings.Contains(text, root) || !strings.Contains(text, "[import ../gone.md not loaded: file not found]") {
		t.Errorf("boot: %q", text)
	}
}

// ---- MCP-13: role-only folders -----------------------------------------

func TestMCP13_RoleOnlyFolderResolvesThroughTools(t *testing.T) {
	root := t.TempDir()
	writeFile(t, filepath.Join(root, "QA Tester", "BOOT.md"), "# BOOT\nYou are **Sam**, QA.\n")
	writeFile(t, filepath.Join(root, "MISSION_BOARD.md"), "## Active\n| ID | Owner | Assignee | Status |\n|---|---|---|---|\n| M-1 | Alex | Sam | ACTIVE |\n")
	cs := connectTo(t, root, config{version: "t", defaultSeat: "Sam"})
	if text, isErr := call(t, cs, "boot", nil); isErr || !strings.Contains(text, "You are **Sam**") {
		t.Errorf("boot: %v %s", isErr, text)
	}
	if text, isErr := call(t, cs, "board", map[string]any{"seat": "Sam"}); isErr || !strings.Contains(text, "M-1") {
		t.Errorf("board(Sam): %v %s", isErr, text)
	}
	if text, _ := call(t, cs, "roster", nil); !strings.Contains(text, `"name": "Sam"`) || !strings.Contains(text, `"folder": "QA Tester"`) {
		t.Errorf("roster: %s", text)
	}
}

// ---- run(): the entry point main uses ------------------------------------

func runInMemory(t *testing.T, args []string) *mcp.ClientSession {
	t.Helper()
	ct, st := mcp.NewInMemoryTransports()
	ctx, cancel := context.WithCancel(context.Background())
	done := make(chan error, 1)
	go func() { done <- run(ctx, args, &bytes.Buffer{}, st) }()
	cs, err := mcp.NewClient(&mcp.Implementation{Name: "test"}, nil).Connect(ctx, ct, nil)
	if err != nil {
		cancel()
		t.Fatal(err)
	}
	t.Cleanup(func() {
		cs.Close()
		cancel()
		select {
		case <-done:
		case <-time.After(5 * time.Second):
			t.Error("run did not return after the client closed")
		}
	})
	return cs
}

func TestRunEntryPoint(t *testing.T) {
	var out bytes.Buffer
	if err := run(context.Background(), []string{"--version"}, &out, nil); err != nil || out.String() != "overmind-mcp dev\n" {
		t.Errorf("--version: %q %v", out.String(), err)
	}
	if err := run(context.Background(), []string{"-h"}, &out, nil); err != nil {
		t.Errorf("-h: %v", err)
	}
	if err := run(context.Background(), []string{"--no-such-flag"}, &out, nil); err == nil {
		t.Error("unknown flag accepted")
	}
	t.Setenv("OVERMIND_ROOT", "")
	t.Setenv("OVERMIND_SEAT", "")
	t.Setenv("OVERMIND_PLUGIN_ROOT", "")
	if err := run(context.Background(), nil, &out, nil); err == nil || !strings.Contains(err.Error(), "no team root") {
		t.Errorf("no root: %v", err)
	}
	root, _ := filepath.Abs(fixtureRoot)
	if err := run(context.Background(), []string{"--root", root, "--seat", "Nobody"}, &out, nil); err == nil || !strings.Contains(err.Error(), "unknown seat") {
		t.Errorf("bad seat: %v", err)
	}
	t.Setenv("OVERMIND_ROOT", root)
	cs := runInMemory(t, nil)
	if got := strings.Join(toolNames(t, cs), ","); got != strings.Join(wantTools, ",") {
		t.Errorf("tools = %s", got)
	}
	if text, isErr := call(t, cs, "boot", map[string]any{"seat": "Sam"}); isErr || !strings.Contains(text, "Engine: overmind-mcp dev, firmware sha256 ") {
		t.Errorf("boot via run: %v", isErr)
	}
}

func TestPromptAndResourceCarryEngineLine(t *testing.T) {
	cs := connect(t, "")
	ctx := context.Background()
	res, err := cs.ReadResource(ctx, &mcp.ReadResourceParams{URI: "overmind://seat/Sam/boot"})
	if err != nil {
		t.Fatal(err)
	}
	if last := tail(res.Contents[0].Text, 1)[0]; !engineLine.MatchString(last) {
		t.Errorf("resource tail = %q", last)
	}
	if _, err := cs.GetPrompt(ctx, &mcp.GetPromptParams{Name: "boot", Arguments: map[string]string{"seat": "../x"}}); err == nil {
		t.Error("prompt accepted a path")
	}
	p, err := cs.GetPrompt(ctx, &mcp.GetPromptParams{Name: "boot", Arguments: map[string]string{"seat": "Sam"}})
	if err != nil {
		t.Fatal(err)
	}
	if tc := p.Messages[0].Content.(*mcp.TextContent); !strings.Contains(tc.Text, "Engine: overmind-mcp test") {
		t.Error("prompt boot lacks the Engine line")
	}
}
