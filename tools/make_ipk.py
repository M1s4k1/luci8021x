#!/usr/bin/env python3
"""Build OpenWrt .ipk packages without the OpenWrt SDK.

Both packages here are pure scripts (PKGARCH=all, no compilation), and an ipk is
nothing more than an ar archive holding:

    debian-binary   "2.0\n"
    control.tar.gz  ./control
    data.tar.gz     the files to install

So we can produce it locally. Tested on macOS with a plain CPython.

Usage:
    python3 tools/make_ipk.py                 # build both packages into ./ipk/
    python3 tools/make_ipk.py --outdir /tmp
"""

import argparse
import gzip
import io
import os
import sys
import tarfile
import time

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def make_targz(gz_members):
    """gz_members: list of (source_path, arcname, mode) -> gzipped tar bytes."""
    raw = io.BytesIO()
    with tarfile.open(fileobj=raw, mode="w", format=tarfile.GNU_FORMAT) as tf:
        for src, arcname, mode in gz_members:
            ti = tf.gettarinfo(src, arcname=arcname)
            ti.uid = ti.gid = 0
            ti.uname = ti.gname = "root"
            ti.mode = mode
            ti.mtime = 0
            with open(src, "rb") as fh:
                tf.addfile(ti, fh)
    out = io.BytesIO()
    with gzip.GzipFile(filename="", mode="wb", fileobj=out, mtime=0) as gz:
        gz.write(raw.getvalue())
    return out.getvalue()


def make_ar(members):
    """members: list of (name, bytes) -> ar archive bytes (GNU flavour)."""
    buf = io.BytesIO()
    buf.write(b"!<arch>\n")
    for name, data in members:
        header = "{:<16}{:<12}{:<6}{:<6}{:<8}{:<10}".format(
            name + "/", "0", "0", "0", "100644", str(len(data))
        ).encode("ascii")
        # name16 + mtime12 + uid6 + gid6 + mode8 + size10 = 58, then fmag "`\n"
        if len(header) != 58:
            raise AssertionError("ar header must be 58 bytes, got %d" % len(header))
        buf.write(header)
        buf.write(b"`\n")
        buf.write(data)
        if len(data) % 2:
            buf.write(b"\n")
    return buf.getvalue()


def control_text(fields, description):
    lines = []
    for key, value in fields:
        if value is None:
            continue
        lines.append("%s: %s" % (key, value))
    lines.append("Description: %s" % description)
    return ("\n".join(lines) + "\n").encode("utf-8")


def build_ipk(pkg, version, arch, depends, description, files, outdir, section="net"):
    missing = [src for src, _, _ in files if not os.path.isfile(src)]
    if missing:
        print("  ! missing source files: %s" % ", ".join(missing), file=sys.stderr)
        return None

    installed_size = max(1, sum(os.path.getsize(s) for s, _, _ in files) // 1024)

    ctrl = control_text(
        [
            ("Package", pkg),
            ("Version", version),
            ("Depends", depends),
            ("Section", section),
            ("Architecture", arch),
            ("Installed-Size", str(installed_size)),
            ("Maintainer", "David Yang <mmyangfl@gmail.com>"),
            ("License", "GPL-2.0-or-later"),
        ],
        description,
    )

    ctl = io.BytesIO()
    with tarfile.open(fileobj=ctl, mode="w", format=tarfile.GNU_FORMAT) as tf:
        ti = tarfile.TarInfo("./control")
        ti.size = len(ctrl)
        ti.mode = 0o644
        ti.mtime = 0
        ti.uid = ti.gid = 0
        ti.uname = ti.gname = "root"
        tf.addfile(ti, io.BytesIO(ctrl))

    ipk = make_ar(
        [
            ("debian-binary", b"2.0\n"),
            ("control.tar.gz", gzip_bytes(ctl.getvalue())),
            ("data.tar.gz", make_targz(files)),
        ]
    )

    os.makedirs(outdir, exist_ok=True)
    path = os.path.join(outdir, "%s_%s_%s.ipk" % (pkg, version, arch))
    with open(path, "wb") as fh:
        fh.write(ipk)
    print("  -> %s (%d bytes)" % (path, len(ipk)))
    return path


def gzip_bytes(data):
    out = io.BytesIO()
    with gzip.GzipFile(filename="", mode="wb", fileobj=out, mtime=0) as gz:
        gz.write(data)
    return out.getvalue()


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--outdir", default=os.path.join(REPO, "ipk"))
    ap.add_argument("--version", default="5", help="version of ieee8021xclient")
    args = ap.parse_args()

    print("Building ipk packages into %s" % args.outdir)

    build_ipk(
        pkg="ieee8021xclient",
        version=args.version,
        arch="all",
        # 上游是 @(PACKAGE_wpa-supplicant||PACKAGE_wpad) 的构建期选择，ipk 里无法表达，
        # 因此这里不强拉依赖：请自行确认设备上已装 wpad 或 wpa-supplicant。
        depends="libc",
        description="Wired 802.1x client config support in /etc/config/network.",
        files=[
            (
                os.path.join(REPO, "net/ieee8021xclient/files/ieee8021xclient.sh"),
                "./lib/netifd/proto/ieee8021xclient.sh",
                0o755,
            )
        ],
        outdir=args.outdir,
    )

    build_ipk(
        pkg="luci-proto-ieee8021xclient",
        version="1",
        arch="all",
        depends="libc, ieee8021xclient",
        description="LuCI support for the wired IEEE 802.1X client protocol.",
        files=[
            (
                os.path.join(
                    REPO,
                    "luci-proto-ieee8021xclient/htdocs/luci-static/resources/protocol/ieee8021xclient.js",
                ),
                "./www/luci-static/resources/protocol/ieee8021xclient.js",
                0o644,
            )
        ],
        outdir=args.outdir,
        section="luci",
    )

    print("\nInstall on the router:")
    print("  scp %s/*.ipk root@router:/tmp/" % args.outdir)
    print("  ssh root@router 'opkg install --no-check-signature /tmp/*.ipk'")
    print("  ssh root@router '/etc/init.d/network restart; rm -f /tmp/luci-indexcache*'")


if __name__ == "__main__":
    main()
