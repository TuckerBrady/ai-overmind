package team

import (
	"errors"
	"io/fs"
	"os"
	"path/filepath"
	"runtime"
	"strings"
)

// maxLinkHops bounds link following, so a link loop fails instead of
// spinning.
const maxLinkHops = 255

var (
	errLinkLoop       = errors.New("too many levels of links")
	errUnreadableLink = errors.New("a link or reparse point whose target cannot be read")
)

// realPath resolves every symlink in an absolute path (CONTRACT 3.4).
//
// On Windows it also resolves junctions. Since Go 1.23, filepath.EvalSymlinks
// treats a junction as an irregular file: a junction as the last component
// comes back unresolved, which would pass a containment check while leading
// anywhere on disk. So on Windows each component is resolved by hand, and
// any component that os.Readlink can read (symlink or junction) is followed.
// A reparse point it cannot read is refused (fail closed).
func realPath(path string) (string, error) {
	if runtime.GOOS != "windows" {
		return filepath.EvalSymlinks(path)
	}
	hops := 0
	return walkLinks(path, &hops)
}

func walkLinks(path string, hops *int) (string, error) {
	path = filepath.Clean(path)
	vol := filepath.VolumeName(path)
	sep := string(filepath.Separator)
	cur := vol + sep
	for _, part := range strings.Split(strings.Trim(path[len(vol):], sep), sep) {
		next := filepath.Join(cur, part)
		info, err := os.Lstat(next)
		if err != nil {
			return "", err
		}
		if isLinkLike(info.Mode()) {
			target, err := linkTarget(next)
			if err != nil {
				return "", err
			}
			if *hops++; *hops > maxLinkHops {
				return "", &fs.PathError{Op: "resolve", Path: next, Err: errLinkLoop}
			}
			if !filepath.IsAbs(target) {
				target = filepath.Join(cur, target)
			}
			resolved, err := walkLinks(target, hops)
			if err != nil {
				return "", err
			}
			cur = resolved
			continue
		}
		cur = next
	}
	return cur, nil
}

// isLinkLike reports a component that may lead somewhere else: a symlink,
// or (on Windows) a junction or other reparse point, which Go reports as
// irregular.
func isLinkLike(mode fs.FileMode) bool { return mode&(fs.ModeSymlink|fs.ModeIrregular) != 0 }

// linkTarget reads a link-like component's target. A reparse point that
// os.Readlink cannot decode (an app execution alias, a cloud placeholder, a
// tag Go does not know) is refused, never treated as a plain file: its
// destination is unknown, so containment cannot be proven (A-5).
func linkTarget(path string) (string, error) {
	target, err := os.Readlink(path)
	if err != nil || target == "" {
		return "", &fs.PathError{Op: "resolve", Path: path, Err: errUnreadableLink}
	}
	return target, nil
}
