#!/usr/bin/env python3
"""Waldlust(D35 — 명세 부록 A-25): 정식 빌드의 제3자 라이선스 고지 THIRD_PARTY_NOTICES-<플랫폼>.txt 를 만든다.

사용(소스 루트에서 — 빌드 스크립트가 부른다):
  python3 res/wald-build/collect-notices.py --platform macos --out <파일> \\
      [--flutter-notices <NOTICES.Z 또는 .apk>] [--vcpkg-share <vcpkg>/installed/<트리플렛>/share]... \\
      [--cargo-about <cargo-about 실행 파일>] [--release <표시용 이름>]

모으는 것:
  1. 손으로 적는 부록 — res/wald-build/notices-extra.txt 의 그 플랫폼 묶음(Lucide·Feather·IJG·FFmpeg·Sciter 등)
  2. 네이티브 라이브러리 — vcpkg installed/<트리플렛>/share/<포트>/copyright(빌드 도구 포트는 뺀다)
  3. Flutter·Dart 패키지 — 빌드 산출물의 flutter_assets/NOTICES.Z(Flutter 가 만든 목록)
  4. Rust 크레이트 — cargo-about generate(res/wald-build/about.toml·about.hbs)
그 플랫폼에 필요한 출처가 비면 실패한다(빈 고지를 배포하지 않게). 32비트 Windows(Sciter)는 Flutter 가 없다.
"""
import argparse
import os
import subprocess
import sys
import zipfile
import zlib

HERE = os.path.dirname(os.path.abspath(__file__))
PLATFORMS = ("macos", "android", "ios", "windows-x64", "windows-x86")
NEEDS_FLUTTER = ("macos", "android", "ios", "windows-x64")
# vcpkg 가 설치하지만 결과물에 들어가지 않는 빌드 도구 포트
VCPKG_HOST_PORTS = {"vcpkg", "pkgconf", "aclocal"}
RULE = "=" * 100


def die(msg):
    print("FAIL: " + msg, file=sys.stderr)
    sys.exit(1)


def extra_sections(platform):
    """notices-extra.txt 에서 'all' 과 이 플랫폼 묶음을 순서대로 이어 붙인다."""
    out, take, started = [], False, False
    with open(os.path.join(HERE, "notices-extra.txt"), encoding="utf-8") as f:
        for line in f:
            if line.startswith("## platforms:"):
                names = line.split(":", 1)[1].split()
                take = "all" in names or platform in names
                started = True
                continue
            if not started:
                continue  # 맨 앞 주석
            if take:
                out.append(line.rstrip("\n"))
    text = "\n".join(out).strip()
    if not text:
        die("notices-extra.txt 에 이 플랫폼 묶음이 없다")
    return text


def vcpkg_notices(shares):
    parts = []
    for share in shares:
        if not os.path.isdir(share):
            die(f"vcpkg share 폴더가 없다: {share}")
        for port in sorted(os.listdir(share)):
            if port in VCPKG_HOST_PORTS or port.startswith("vcpkg-"):
                continue
            path = os.path.join(share, port, "copyright")
            if not os.path.isfile(path):
                continue
            with open(path, encoding="utf-8", errors="replace") as f:
                body = f.read().strip()
            parts.append(f"{'-' * 100}\n{port}\n\n{body}")
    if not parts:
        die("vcpkg copyright 파일을 하나도 찾지 못했다")
    return len(parts), "\n\n".join(parts)


def flutter_notices(path):
    if path.endswith(".apk"):
        with zipfile.ZipFile(path) as z:
            data = z.read("assets/flutter_assets/NOTICES.Z")
    else:
        with open(path, "rb") as f:
            data = f.read()
    # Flutter 는 zlib(또는 gzip)으로 압축해 둔다 — wbits 47 = 둘 다 자동 판별
    text = zlib.decompress(data, 47).decode("utf-8").strip()
    if len(text) < 1000:
        die("Flutter NOTICES 가 너무 짧다")
    return text


def rust_notices(cargo_about, root):
    cmd = [cargo_about, "generate", "-c", os.path.join(HERE, "about.toml"), os.path.join(HERE, "about.hbs")]
    r = subprocess.run(cmd, cwd=root, capture_output=True, text=True, encoding="utf-8")
    if r.returncode != 0:
        sys.stderr.write(r.stderr[-4000:])
        die("cargo-about 실패")
    text = r.stdout.strip()
    if "Used by:" not in text:
        die("cargo-about 결과에 크레이트가 없다")
    return text


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--platform", required=True, choices=PLATFORMS)
    ap.add_argument("--out", required=True)
    ap.add_argument("--flutter-notices")
    ap.add_argument("--vcpkg-share", action="append", default=[])
    ap.add_argument("--cargo-about", default="cargo-about")
    ap.add_argument("--release", default="")
    a = ap.parse_args()
    root = os.path.dirname(os.path.dirname(HERE))

    if a.platform in NEEDS_FLUTTER and not a.flutter_notices:
        die(f"{a.platform} 는 --flutter-notices 가 필요하다")
    if not a.vcpkg_share:
        die("--vcpkg-share 가 필요하다")

    extra = extra_sections(a.platform)
    n_ports, native = vcpkg_notices(a.vcpkg_share)
    flutter = flutter_notices(a.flutter_notices) if a.flutter_notices else None
    rust = rust_notices(a.cargo_about, root)

    sections = [("Additional notices", extra), (f"Native libraries (vcpkg) — {n_ports} ports", native)]
    if flutter:
        sections.append(("Flutter engine and Dart packages (Flutter NOTICES)", flutter))
    sections.append(("Rust crates (cargo-about)", rust))

    head = [
        f"Waldlust Remote — third-party notices ({a.platform})",
        f"Release: {a.release}" if a.release else None,
        "",
        "This program is a modified version of RustDesk, licensed under the GNU AGPL-3.0 — see NOTICE and LICENCE.",
        "Open source notices and source code for every release: https://remote.waldpay.co.kr/oss",
        "",
        "Contents",
    ]
    head = [h for h in head if h is not None]
    head += [f"  {i}. {t}" for i, (t, _) in enumerate(sections, 1)]
    body = [f"\n\n{RULE}\n{i}. {t}\n{RULE}\n\n{text}" for i, (t, text) in enumerate(sections, 1)]
    os.makedirs(os.path.dirname(os.path.abspath(a.out)), exist_ok=True)
    with open(a.out, "w", encoding="utf-8", newline="\n") as f:
        f.write("\n".join(head) + "".join(body) + "\n")
    print(f"notices: {a.out} ({os.path.getsize(a.out)} bytes; vcpkg {n_ports}, flutter {'yes' if flutter else 'no'}, rust yes)")


if __name__ == "__main__":
    main()
