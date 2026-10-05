package firmware

import (
	"crypto/sha256"
	"os"
	"path/filepath"
	"sort"
	"strings"
	"testing"
	"testing/fstest"
)

// The plugin root, relative to this package.
const pluginRoot = "../.."

func readNorm(t *testing.T, p string) string {
	t.Helper()
	b, err := os.ReadFile(p)
	if err != nil {
		t.Fatalf("source %s unreadable: %v", p, err)
	}
	return strings.ReplaceAll(string(b), "\r\n", "\n")
}

func sourceRefs(t *testing.T) []string {
	t.Helper()
	refs, err := filepath.Glob(filepath.Join(pluginRoot, "reference", "*.md"))
	if err != nil || len(refs) == 0 {
		t.Fatalf("no reference/*.md beside this module (err %v): the drift test cannot run", err)
	}
	var names []string
	for _, r := range refs {
		names = append(names, filepath.Base(r))
	}
	sort.Strings(names)
	return names
}

// The drift test never skips: a missing source is a failure.
func TestEmbeddedCopiesMatchSources(t *testing.T) {
	src := readNorm(t, filepath.Join(pluginRoot, "hooks", "kernel.md"))
	emb, err := files.ReadFile("kernel.md")
	if err != nil {
		t.Fatal("kernel.md not embedded:", err)
	}
	if strings.ReplaceAll(string(emb), "\r\n", "\n") != src {
		t.Error("firmware/kernel.md has drifted from hooks/kernel.md; run mcp/build.sh copy")
	}
	want := sourceRefs(t)
	for _, name := range want {
		src := readNorm(t, filepath.Join(pluginRoot, "reference", name))
		emb, err := files.ReadFile("reference/" + name)
		if err != nil {
			t.Errorf("reference/%s has no embedded copy; run mcp/build.sh copy", name)
			continue
		}
		if strings.ReplaceAll(string(emb), "\r\n", "\n") != src {
			t.Errorf("firmware/reference/%s has drifted; run mcp/build.sh copy", name)
		}
	}
	got, _ := filepathGlobEmbedded()
	if strings.Join(got, ",") != strings.Join(want, ",") {
		t.Errorf("embedded reference files %v differ from the source set %v (stale copy?); run mcp/build.sh copy", got, want)
	}
}

func filepathGlobEmbedded() ([]string, error) {
	ents, err := files.ReadDir("reference")
	if err != nil {
		return nil, err
	}
	var out []string
	for _, e := range ents {
		out = append(out, e.Name())
	}
	sort.Strings(out)
	return out, nil
}

// Text is the 7.5 concatenation of the files on disk.
func TestTextIsTheFixedConcatenation(t *testing.T) {
	var b strings.Builder
	add := func(rel, p string) {
		body := readNorm(t, p)
		if !strings.HasSuffix(body, "\n") {
			body += "\n"
		}
		b.WriteString("=== " + rel + "\n" + body)
	}
	add("hooks/kernel.md", filepath.Join(pluginRoot, "hooks", "kernel.md"))
	for _, name := range sourceRefs(t) {
		add("reference/"+name, filepath.Join(pluginRoot, "reference", name))
	}
	if Text != b.String() {
		t.Fatal("Text is not the 7.5 concatenation of hooks/kernel.md and reference/*.md")
	}
	if !strings.HasPrefix(Text, "=== hooks/kernel.md\n") {
		t.Error("Text must start with the kernel")
	}
	sum := sha256.Sum256([]byte(Text))
	if len(sum) != 32 {
		t.Error("sha256 of Text")
	}
}

func TestOneSectionPerFile(t *testing.T) {
	secs := Sections()
	if want := 1 + len(sourceRefs(t)); len(secs) != want {
		t.Fatalf("len(Sections()) = %d, want 1 + count(reference/*.md) = %d", len(secs), want)
	}
	if secs[0].Title != "KERNEL" || secs[0].File != "hooks/kernel.md" {
		t.Errorf("first section = %q (%s), want KERNEL", secs[0].Title, secs[0].File)
	}
	for i, s := range secs[1:] {
		if !strings.HasPrefix(s.File, "reference/") {
			t.Errorf("section %d file %q", i+1, s.File)
		}
		if !strings.HasPrefix(s.Body, "# "+s.Title+"\n") {
			t.Errorf("section %q: title is not the file's H1", s.Title)
		}
	}
	for _, s := range secs {
		if !strings.Contains(Text, "=== "+s.File+"\n"+s.Body) {
			t.Errorf("section %s is not in Text verbatim", s.File)
		}
	}
}

// A heading inside a fenced block, including a 4-backtick fence that holds a
// 3-backtick fence, never starts a section: the unit is a file.
func TestFencedHeadingStaysInItsSection(t *testing.T) {
	ref := "# Topic\n\n<!-- aliases: OLD TITLE -->\n\n" +
		"````\n```\n## NOT A SECTION\n```\n## STILL INSIDE\n````\n\n## REAL SUBHEADING\n\ntext\n"
	fsys := fstest.MapFS{
		"kernel.md":          {Data: []byte("# K\n\n**Index.** x\n\nEND OF KERNEL v5\n")},
		"reference/topic.md": {Data: []byte(ref)},
	}
	text, secs := build(fsys)
	if len(secs) != 2 {
		t.Fatalf("got %d sections, want 2", len(secs))
	}
	if secs[1].Body != ref {
		t.Error("the fenced headings were split out of their file's section")
	}
	for _, q := range []string{"NOT A SECTION", "STILL INSIDE", "REAL SUBHEADING"} {
		if _, ok := find(secs, q); ok {
			t.Errorf("Find(%q) matched a heading inside a file", q)
		}
	}
	if s, ok := find(secs, "old title"); !ok || s.File != "reference/topic.md" {
		t.Errorf("alias lookup failed: %q %v", s.File, ok)
	}
	if !strings.HasPrefix(text, "=== hooks/kernel.md\n# K\n") {
		t.Error("kernel not first in the concatenation")
	}
}

func TestFindOrder(t *testing.T) {
	all := []Section{
		{Title: "KERNEL", File: "hooks/kernel.md"},
		{Title: "Board Things", File: "reference/a.md", Aliases: []string{"TARS LEGACY"}},
		{Title: "Tars", File: "reference/b.md"},
		{Title: "Something tars", File: "reference/tars.md"},
	}
	cases := []struct{ q, want string }{
		{"tars", "reference/b.md"},        // exact title beats stem
		{"TARS LEGACY", "reference/a.md"}, // alias
		{"kernel", "hooks/kernel.md"},     // exact title
		{"a", "reference/a.md"},           // stem beats substring
		{"things", "reference/a.md"},      // substring of a title
	}
	for _, c := range cases {
		s, ok := find(all, c.q)
		if !ok || s.File != c.want {
			t.Errorf("find(%q) = %q %v, want %q", c.q, s.File, ok, c.want)
		}
	}
	if s, ok := find(all[1:], "tars"); !ok || s.File != "reference/b.md" {
		t.Errorf("find(tars) = %q", s.File)
	}
	if s, ok := find([]Section{all[1], all[3]}, "tars"); !ok || s.File != "reference/tars.md" {
		t.Errorf("stem lookup = %q %v", s.File, ok)
	}
	for _, q := range []string{"", "   ", "no such section"} {
		if _, ok := Find(q); ok {
			t.Errorf("Find(%q) matched", q)
		}
	}
}

// Every old section title the ledger records as MOVED still finds its file.
func TestEveryMovedTitleFinds(t *testing.T) {
	led := readNorm(t, filepath.Join(pluginRoot, "docs", "v5", "firmware-ledger.tsv"))
	n := 0
	for _, line := range strings.Split(led, "\n") {
		f := strings.Split(line, "\t")
		if len(f) < 5 || f[0] != "S" || f[2] != "MOVED" {
			continue
		}
		n++
		s, ok := Find(f[4])
		if !ok {
			t.Errorf("Find(%q) failed", f[4])
			continue
		}
		if s.File != f[3] {
			t.Errorf("Find(%q) = %s, ledger says %s", f[4], s.File, f[3])
		}
	}
	if n == 0 {
		t.Fatal("no MOVED S rows in the ledger")
	}
}

func TestKernelFirstAndTarsReachable(t *testing.T) {
	if s, ok := Find("kernel"); !ok || !strings.Contains(s.Body, "END OF KERNEL v5") {
		t.Error("Find(kernel) does not return the kernel")
	}
	if s, ok := Find("tars"); !ok || s.File != "reference/tars.md" {
		t.Errorf("Find(tars) = %q %v", s.File, ok)
	}
}
