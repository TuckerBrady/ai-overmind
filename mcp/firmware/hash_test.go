package firmware

import (
	"crypto/sha256"
	"encoding/hex"
	"os"
	"path/filepath"
	"regexp"
	"testing"
)

func writeTree(t *testing.T, files map[string]string) string {
	t.Helper()
	root := t.TempDir()
	for rel, body := range files {
		p := filepath.Join(root, filepath.FromSlash(rel))
		if err := os.MkdirAll(filepath.Dir(p), 0o755); err != nil {
			t.Fatal(err)
		}
		if err := os.WriteFile(p, []byte(body), 0o644); err != nil {
			t.Fatal(err)
		}
	}
	return root
}

func sha(s string) string {
	sum := sha256.Sum256([]byte(s))
	return hex.EncodeToString(sum[:])
}

// TestHashDirMatchesEmbedded proves the server's embedded firmware is the
// plugin firmware in this checkout (CONTRACT 3.6). It needs the v5 layout
// (hooks/kernel.md plus reference/*.md, L1) and has no skip.
func TestHashDirMatchesEmbedded(t *testing.T) {
	got, err := HashDir("../..")
	if err != nil {
		t.Fatalf("HashDir(../..): %v", err)
	}
	if got != Hash() {
		t.Fatalf("HashDir(../..) = %s, Hash() = %s; rebuild the embedded copies (mcp/build.sh)", got[:12], Hash()[:12])
	}
}

func TestHashIsSha256OfText(t *testing.T) {
	if Hash() != sha(Text) {
		t.Fatal("Hash() is not the sha256 of Text")
	}
	if !regexp.MustCompile(`^[0-9a-f]{64}$`).MatchString(Hash()) {
		t.Fatalf("Hash() = %q, want 64 lowercase hex", Hash())
	}
}

// TestMCP6_HashDirConcatenation pins the 7.5 byte layout: kernel first,
// references in byte order of path (uppercase before lowercase), CRLF
// folded, a missing final newline added, non-.md files and subfolders left
// out.
func TestMCP6_HashDirConcatenation(t *testing.T) {
	root := writeTree(t, map[string]string{
		"hooks/kernel.md":        "kernel\r\nEND OF KERNEL v5\r\n",
		"reference/b.md":         "bee",
		"reference/a.md":         "# A\n",
		"reference/Z.md":         "zed\r\n",
		"reference/notes.txt":    "not firmware",
		"reference/sub/deep.md":  "not top level",
		"hooks/firmware.md":      "legacy, ignored",
		"reference/sub.md/x.txt": "a folder named like a file",
	})
	want := "=== hooks/kernel.md\nkernel\nEND OF KERNEL v5\n" +
		"=== reference/Z.md\nzed\n" +
		"=== reference/a.md\n# A\n" +
		"=== reference/b.md\nbee\n"
	got, err := HashDir(root)
	if err != nil {
		t.Fatal(err)
	}
	if got != sha(want) {
		text, _ := concatDir(root)
		t.Fatalf("hash mismatch\n got text %q\nwant text %q", text, want)
	}
}

func TestMCP6_HashDirKernelOnlyAndMissingKernel(t *testing.T) {
	root := writeTree(t, map[string]string{"hooks/kernel.md": ""})
	got, err := HashDir(root)
	if err != nil {
		t.Fatal(err)
	}
	if got != sha("=== hooks/kernel.md\n\n") {
		t.Errorf("empty kernel, no reference dir: %s", got)
	}

	missing := writeTree(t, map[string]string{"reference/a.md": "a"})
	_, err = HashDir(missing)
	if err == nil {
		t.Fatal("missing kernel: want error")
	}
	if regexp.MustCompile(`[A-Za-z]:\\|` + regexp.QuoteMeta(missing)).MatchString(err.Error()) {
		t.Errorf("error leaks an absolute path: %v", err)
	}
}

func TestMCP6_HashDirDetectsAnyChange(t *testing.T) {
	base := map[string]string{"hooks/kernel.md": "k\n", "reference/a.md": "a\n"}
	h0, _ := HashDir(writeTree(t, base))
	for name, files := range map[string]map[string]string{
		"kernel edit":       {"hooks/kernel.md": "k!\n", "reference/a.md": "a\n"},
		"reference edit":    {"hooks/kernel.md": "k\n", "reference/a.md": "a!\n"},
		"reference added":   {"hooks/kernel.md": "k\n", "reference/a.md": "a\n", "reference/b.md": ""},
		"reference renamed": {"hooks/kernel.md": "k\n", "reference/c.md": "a\n"},
	} {
		h, err := HashDir(writeTree(t, files))
		if err != nil {
			t.Fatal(err)
		}
		if h == h0 {
			t.Errorf("%s: hash unchanged", name)
		}
	}
	same, _ := HashDir(writeTree(t, map[string]string{"hooks/kernel.md": "k\r\n", "reference/a.md": "a"}))
	if same != h0 {
		t.Error("CRLF and a missing final newline must not change the hash")
	}
}
