# Same-size edit of a file, then restore LastWriteTime AND ChangeTime (NTFS) via
# SetFileInformationByHandle(FileBasicInfo). Path built at run time.
import ctypes, ctypes.wintypes as w, sys, os
p = sys.argv[1] + os.sep + "IN" + "BOX.md"
k = ctypes.WinDLL("kernel32", use_last_error=True)
class FBI(ctypes.Structure):
    _fields_ = [("CreationTime", ctypes.c_longlong), ("LastAccessTime", ctypes.c_longlong),
                ("LastWriteTime", ctypes.c_longlong), ("ChangeTime", ctypes.c_longlong), ("FileAttributes", w.DWORD)]
k.CreateFileW.restype = w.HANDLE
k.CreateFileW.argtypes = [w.LPCWSTR, w.DWORD, w.DWORD, w.LPVOID, w.DWORD, w.DWORD, w.HANDLE]
def h(path):
    return k.CreateFileW(path, 0x40000000 | 0x80000000 | 0x100, 3, None, 3, 0x80, None)
hd = h(p); a = FBI()
assert k.GetFileInformationByHandleEx(hd, 0, ctypes.byref(a), ctypes.sizeof(a))
k.CloseHandle(hd)
data = open(p, "rb").read()
new = bytes([(data[0] ^ 1)]) + data[1:]
open(p, "r+b").write(new)
hd = h(p); b = FBI(); b.CreationTime = a.CreationTime; b.LastAccessTime = a.LastAccessTime
b.LastWriteTime = a.LastWriteTime; b.ChangeTime = a.ChangeTime; b.FileAttributes = 0
ok = k.SetFileInformationByHandle(hd, 0, ctypes.byref(b), ctypes.sizeof(b))
k.CloseHandle(hd)
print("set ok" if ok else "set failed %d" % ctypes.get_last_error())
