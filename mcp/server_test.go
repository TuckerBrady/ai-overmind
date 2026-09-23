package main

import (
	"context"
	"os/exec"
	"path/filepath"
	"runtime"
	"sort"
	"strings"
	"testing"

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
	srv, err := newServer(tm, "test", defaultSeat)
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
