"""Build the release zips in dist/:

  <Addon>-<version>.zip                    CurseForge / any platform: only the addon folder at
                                           the top level, as CurseForge requires
  <Addon>-<version>-Windows-installer.zip  for sharing by hand: the addon folder plus the
                                           double-click installer and README.txt

The addon is the folder next to tools/ that holds a TOC of its own name.
"""
import os
import re
import time
import zipfile

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DIST = os.path.join(ROOT, "dist")
SKIP = {".DS_Store", "Thumbs.db"}


def addon():
    """The addon folder's name, its TOC text and its version."""
    for name in sorted(os.listdir(ROOT)):
        toc = os.path.join(ROOT, name, name + ".toc")
        if os.path.isfile(toc):
            text = open(toc, encoding="utf-8").read()
            return name, text, re.search(r"^## Version: *(\S+)", text, re.M).group(1)
    raise SystemExit("no <Addon>/<Addon>.toc next to tools/")


def title(toc):
    m = re.search(r"^## Title: *(.+?)\s*$", toc, re.M)
    return m.group(1) if m else None


def add_addon_folder(z, name, stamp):
    base = os.path.join(ROOT, name)
    for folder, dirs, files in os.walk(base):
        dirs[:] = sorted(d for d in dirs if not d.startswith("."))
        rel = os.path.relpath(folder, ROOT).replace(os.sep, "/")
        entry = zipfile.ZipInfo(rel + "/", stamp)
        entry.external_attr = (0o40755 << 16) | 0x10   # directory entry
        z.writestr(entry, b"")
        for f in sorted(files):
            if f not in SKIP and not f.startswith("."):
                z.write(os.path.join(folder, f), f"{rel}/{f}")


def main():
    name, toc, version = addon()
    os.makedirs(DIST, exist_ok=True)
    stamp = time.localtime()[:6]

    curse = os.path.join(DIST, f"{name}-{version}.zip")
    with zipfile.ZipFile(curse, "w", zipfile.ZIP_DEFLATED) as z:
        add_addon_folder(z, name, stamp)

    windows = os.path.join(DIST, f"{name}-{version}-Windows-installer.zip")
    with zipfile.ZipFile(windows, "w", zipfile.ZIP_DEFLATED) as z:
        add_addon_folder(z, name, stamp)
        bat = f"Install-{name}.bat"
        # the installer has to keep Windows line endings
        data = open(os.path.join(ROOT, bat), "rb").read().replace(b"\r\n", b"\n").replace(b"\n", b"\r\n")
        z.writestr(zipfile.ZipInfo(bat, stamp), data, zipfile.ZIP_DEFLATED)
        readme = open(os.path.join(ROOT, "README.txt"), encoding="utf-8").read().split("\n")
        # its first line always names the version being shipped
        readme[0] = f"{title(toc) or name} {version}"
        z.writestr(zipfile.ZipInfo("README.txt", stamp), "\r\n".join(l.rstrip("\r") for l in readme).encode("utf-8"),
                   zipfile.ZIP_DEFLATED)

    print(curse)
    print(windows)


if __name__ == "__main__":
    main()
