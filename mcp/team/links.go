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

var errLinkLoop = errors.New("too many levels of links")

// realPath resolves every symlink in an absolute path (CONTRACT 3.4).
//
// On Windows it also resolves junctions. Since Go 1.23, filepath.EvalSymlinks
// treats a junction as an irregular file: a junction as the last component
// comes back unresolved, which would pass a containment check while leading
// anywhere on disk. So on Windows each component is resolved by hand, and
// any component that os.Readlink can read (symlink or junction) is followed.
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
		if info.Mode()&(fs.ModeSymlink|fs.ModeIrregular) != 0 {
			if target, err := os.Readlink(next); err == nil {
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
		}
		cur = next
	}
	return cur, nil
}
