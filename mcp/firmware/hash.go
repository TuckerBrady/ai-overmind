package firmware

// Firmware identity (CONTRACT 7.5). The hash names the exact firmware a
// server carries, so a boot can say which doctrine it serves and warn when
// the installed plugin carries a different one.

import (
	"crypto/sha256"
	"encoding/hex"
	"fmt"
	"os"
	"path/filepath"
	"sort"
	"strings"
)

// KernelPath and ReferenceDir are the plugin-relative locations of the
// firmware sources, in the slash form the concatenation headers use.
const (
	KernelPath   = "hooks/kernel.md"
	ReferenceDir = "reference"
)

// Hash returns the lowercase sha256 hex of the embedded firmware text.
func Hash() string {
	sum := sha256.Sum256([]byte(Text))
	return hex.EncodeToString(sum[:])
}

// HashDir computes the 7.5 hash over the firmware files on disk under a
// plugin root: hooks/kernel.md, then reference/*.md in byte order of
// relative path. A missing kernel is an error; a missing reference folder
// contributes nothing.
func HashDir(root string) (string, error) {
	text, err := concatDir(root)
	if err != nil {
		return "", err
	}
	sum := sha256.Sum256([]byte(text))
	return hex.EncodeToString(sum[:]), nil
}

// concatDir builds the 7.5 concatenation from the files under root.
func concatDir(root string) (string, error) {
	rels := []string{KernelPath}
	matches, err := filepath.Glob(filepath.Join(root, ReferenceDir, "*.md"))
	if err != nil {
		return "", err
	}
	var refs []string
	for _, m := range matches {
		info, err := os.Stat(m)
		if err != nil || info.IsDir() {
			continue
		}
		refs = append(refs, ReferenceDir+"/"+filepath.Base(m))
	}
	sort.Strings(refs) // byte order of the relative path
	rels = append(rels, refs...)

	var b strings.Builder
	for _, rel := range rels {
		raw, err := os.ReadFile(filepath.Join(root, filepath.FromSlash(rel)))
		if err != nil {
			return "", fmt.Errorf("firmware file %s: %w", rel, unwrapPath(err))
		}
		appendFile(&b, rel, string(raw))
	}
	return b.String(), nil
}

// appendFile writes one 7.5 record: the header line, the content with CRLF
// folded to LF, and a final newline when the content lacks one.
func appendFile(b *strings.Builder, rel, content string) {
	b.WriteString("=== ")
	b.WriteString(rel)
	b.WriteString("\n")
	content = strings.ReplaceAll(content, "\r\n", "\n")
	b.WriteString(content)
	if !strings.HasSuffix(content, "\n") {
		b.WriteString("\n")
	}
}

// unwrapPath drops the absolute path from a file error, so a caller can
// show the error without leaking where the plugin lives.
func unwrapPath(err error) error {
	if pe, ok := err.(*os.PathError); ok {
		return pe.Err
	}
	return err
}
