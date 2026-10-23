#!/usr/bin/env python3
"""Waldlust 원격지원 앱 아이콘 생성기(DSK-10).

빨간 배경(#D32F2F) 위에 흰 W. 로고를 두고 그 아래에 'remote' 를 쓴다.
48px 이하 크기는 글자가 읽히지 않아 W. 만 그린다. 단, Windows ico 는 작업 표시줄(24~48px)·바탕화면(48px)
아이콘에도 'remote' 가 보이게 16px 만 W. 만 그린다.

W. 는 기존 비트맵 아이콘(검정 배경)에서 잰 꼭짓점으로 다시 그린 벡터다(1024 기준 좌표).
'remote' 글꼴은 Montserrat Bold(SIL OFL 1.1)다. 글꼴 파일은 저장소에 넣지 않는다.
  https://github.com/google/fonts/raw/main/ofl/montserrat/Montserrat%5Bwght%5D.ttf

수신 전용 빌드(DSK-01)는 오른쪽 위에 흰 원 + ↓(받기) 배지를 더한다(32px 이상). --variant incoming 은 배지가
들어가는 파일(Windows ico, Android 런처)만 res/wald-variant/incoming-icons/ 에 같은 상대 경로로 쓰고,
수신 전용 빌드가 빌드 전에 res/wald-variant/apply_icons.py 로 덮어쓴다. 트레이·알림·플로팅 창은 양방향과 같다.
PNG 는 루트 .gitignore 의 *png 에 걸리므로 새로 만든 파일은 git add -f 로 넣는다.

사용(저장소 루트에서, macOS):
  python3 res/wald-icon/gen_icons.py --font <Montserrat[wght].ttf>
  python3 res/wald-icon/gen_icons.py --font <Montserrat[wght].ttf> --variant incoming
  python3 res/wald-icon/gen_icons.py --font <Montserrat[wght].ttf> --ios-only   # iOS AppIcon 만
필요: Pillow, iconutil(macOS 기본 도구, .icns 생성)
"""

import argparse
import json
import os
import shutil
import subprocess
import tempfile

from PIL import Image, ImageDraw, ImageFilter, ImageFont

BG = (0xD3, 0x2F, 0x2F, 255)
FG = (255, 255, 255, 255)
TEXT = "remote"
SMALL_MAX = 48  # 이 크기(px) 이하는 W. 만
ICO_SMALL_MAX = 16  # Windows ico 에서 W. 만 그리는 크기(px) 상한

# W 다각형과 점(1024 캔버스 기준, 기존 아이콘에서 잰 값)
W_POLY = [
    (213.6, 336.4), (335.9, 336.4), (389.0, 541.1), (438.4, 360.1),
    (563.7, 360.1), (610.1, 539.7), (661.3, 336.4), (774.2, 336.4),
    (674.6, 691.0), (553.2, 691.0), (494.3, 492.0), (434.9, 691.0),
    (313.5, 691.0),
]
DOT = (756.5, 621.0, 826.0, 691.0)
LOGO_BOX = (213.6, 336.4, 826.0, 691.0)  # W. 전체
W_BOX = (213.6, 336.4, 774.2, 691.0)  # 점을 뺀 W

# 'remote' 배치(1024 기준): 로고 배율(1.0 = 기존 검정 아이콘의 W. 크기), 글자 너비(W 너비 대비),
# 로고와 글자 사이 간격(로고 높이 대비)
LOGO_SCALE = 1.00
TEXT_WIDTH = 1.40
TEXT_GAP = 0.15
# 로고 묶음의 가로 중심. 기존 아이콘이 W. 를 이 위치에 두었다. 'remote' 도 이 중심에 맞춘다.
CENTER_X = (LOGO_BOX[0] + LOGO_BOX[2]) / 2
CENTER_Y = 512.0

CORNER = 180 / 1024  # 기존 아이콘의 둥근 모서리 반지름(캔버스 대비)
MAC_BODY = 824 / 1024  # macOS 아이콘 격자: 1024 캔버스 안 824 몸체
MAC_CORNER = 185.4 / 824
IOS_ICONSET = "flutter/ios/Runner/Assets.xcassets/AppIcon.appiconset"

SS = 2048  # 그릴 때의 해상도. 원하는 크기로 줄여 안티앨리어싱한다.

# 수신 전용 배지(1024 기준). 배지 둘레 고리와 ↓ 는 바탕으로 뚫는다.
INCOMING_DIR = os.path.join("res", "wald-variant", "incoming-icons")
BADGE_MIN = 32  # 이 크기(px) 이상에만 배지
BADGE = (866, 158, 120, 20)  # 꽉 찬 둥근 사각형: 중심 x·y, 반지름, 고리 폭
BADGE_SHIFT = (-15, 20)  # 배지 자리를 비우려고 W.+'remote' 를 왼쪽 아래로 옮기는 양
# Android 적응형 foreground: 보이는 원(72dp) 안에 배지가 들어가도록 내용을 줄여 내리고, 배지는 W 오른쪽 위에 둔다
# (108dp 캔버스 기준 좌표)
GLYPH_BADGE = (633, 302, 80, 14)
GLYPH_BADGE_SCALE = 0.88
GLYPH_BADGE_SHIFT = (-5, 50)


def _font(path, size):
    font = ImageFont.truetype(path, size)
    font.set_variation_by_name("Bold")
    return font


def _content_ops(font_path, with_text):
    """1024 기준 좌표로 (다각형, 사각형, 글자) 그리기 명령을 만든다."""
    if not with_text:
        return 1.0, (0.0, 0.0), None
    s = LOGO_SCALE
    logo_h = (LOGO_BOX[3] - LOGO_BOX[1]) * s
    w_w = (W_BOX[2] - W_BOX[0]) * s
    ref = _font(font_path, 1000)
    x0, y0, x1, y1 = ref.getbbox(TEXT)
    size = 1000 * (w_w * TEXT_WIDTH) / (x1 - x0)
    text_h = (y1 - y0) * size / 1000
    gap = logo_h * TEXT_GAP
    total_h = logo_h + gap + text_h
    top = CENTER_Y - total_h / 2
    # 로고: 가로 중심 유지, 세로는 묶음의 위쪽
    dx = CENTER_X - CENTER_X * s
    dy = top - LOGO_BOX[1] * s
    text = (size, CENTER_X, top + logo_h + gap)
    return s, (dx, dy), text


def _draw_content(img, font_path, with_text, color, scale=1.0, offset=(0.0, 0.0)):
    """img(정사각형) 위에 로고(와 글자)를 그린다. scale·offset 은 1024 캔버스 기준의 추가 변환."""
    k = img.size[0] / 1024
    s, (dx, dy), text = _content_ops(font_path, with_text)

    def outer(x, y):
        return (x * scale + offset[0]) * k, (y * scale + offset[1]) * k

    def tr(x, y):
        return outer(x * s + dx, y * s + dy)

    d = ImageDraw.Draw(img)
    d.polygon([tr(x, y) for x, y in W_POLY], fill=color)
    d.rectangle([tr(DOT[0], DOT[1]), tr(DOT[2], DOT[3])], fill=color)
    if text:
        # 글자 위치는 이미 1024 기준 최종 좌표다
        size, cx, top = text
        font = _font(font_path, round(size * scale * k))
        x0, y0, x1, y1 = font.getbbox(TEXT)
        tx, ty = outer(cx, top)
        d.text((tx - (x0 + x1) / 2, ty - y0), TEXT, font=font, fill=color)


def _draw_badge(img, cx, cy, r, ring, hole):
    """수신 전용 배지: 흰 원 + ↓. 둘레 고리와 화살표는 hole(바탕색, 적응형 foreground 는 투명)로 칠한다."""
    k = img.size[0] / 1024
    d = ImageDraw.Draw(img)
    for rr, color in ((r + ring, hole), (r, FG)):
        d.ellipse([(cx - rr) * k, (cy - rr) * k, (cx + rr) * k, (cy + rr) * k], fill=color)

    def p(x, y):  # 배지 반지름 단위
        return (cx + x * r) * k, (cy + y * r) * k

    d.rectangle([p(-0.17, -0.58), p(0.17, 0.02)], fill=hole)
    d.polygon([p(-0.50, -0.06), p(0.50, -0.06), p(0, 0.56)], fill=hole)


def _rounded(size, box, radius, color):
    img = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    ImageDraw.Draw(img).rounded_rectangle(box, radius=radius, fill=color)
    return img


def render(px, kind, font_path, with_text=None, badge=False):
    """kind: 'square'(꽉 찬 둥근 사각형) | 'mac'(macOS 격자, 그림자 포함) | 'glyph'(투명 배경, 흰 글자)
          | 'ios'(모서리 없는 꽉 찬 정사각형 — 모서리는 iOS 가 깎는다)
    badge: 수신 전용 배지(square·glyph 만, BADGE_MIN 이상)"""
    if with_text is None:
        with_text = px > SMALL_MAX
    if badge and kind == "mac":
        raise ValueError("macOS 수신 전용 빌드는 없다")
    badge = badge and px >= BADGE_MIN
    n = SS
    if kind == "square":
        img = _rounded(n, (0, 0, n - 1, n - 1), CORNER * n, BG)
        _draw_content(img, font_path, with_text, FG, offset=BADGE_SHIFT if badge else (0.0, 0.0))
        if badge:
            _draw_badge(img, *BADGE, BG)
    elif kind == "mac":
        body = MAC_BODY * n
        m = (n - body) / 2
        box = (m, m, m + body - 1, m + body - 1)
        shadow = _rounded(n, (box[0], box[1] + 0.012 * n, box[2], box[3] + 0.012 * n), MAC_CORNER * body, (0, 0, 0, 90))
        shadow = shadow.filter(ImageFilter.GaussianBlur(0.012 * n))
        img = Image.alpha_composite(shadow, _rounded(n, box, MAC_CORNER * body, BG))
        _draw_content(img, font_path, with_text, FG, scale=MAC_BODY, offset=(512 * (1 - MAC_BODY),) * 2)
    elif kind == "ios":
        img = Image.new("RGBA", (n, n), BG)
        _draw_content(img, font_path, with_text, FG)
    elif kind == "glyph":
        # Android 적응형 foreground: 108dp 중 가운데 72dp 가 보이므로 2/3 로 줄인다.
        img = Image.new("RGBA", (n, n), (0, 0, 0, 0))
        f = 72 / 108 * (GLYPH_BADGE_SCALE if badge else 1)
        sx, sy = GLYPH_BADGE_SHIFT if badge else (0.0, 0.0)
        _draw_content(img, font_path, with_text, FG, scale=f, offset=(512 * (1 - f) + sx, 512 * (1 - f) + sy))
        if badge:
            _draw_badge(img, *GLYPH_BADGE, (0, 0, 0, 0))
    else:
        raise ValueError(kind)
    return img.resize((px, px), Image.LANCZOS)


def render_template(w, h, glyph_h, color=(0, 0, 0, 255)):
    """투명 배경 위 한 색 W.. macOS 메뉴 막대 트레이 템플릿과 Android 알림 아이콘용(알파만 쓰인다)."""
    k = glyph_h / (LOGO_BOX[3] - LOGO_BOX[1])
    f = 8
    img = Image.new("RGBA", (w * f, h * f), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    ox = (w - (LOGO_BOX[2] - LOGO_BOX[0]) * k) / 2 - LOGO_BOX[0] * k
    oy = (h - glyph_h) / 2 - LOGO_BOX[1] * k

    def tr(x, y):
        return (x * k + ox) * f, (y * k + oy) * f

    d.polygon([tr(x, y) for x, y in W_POLY], fill=color)
    d.rectangle([tr(DOT[0], DOT[1]), tr(DOT[2], DOT[3])], fill=color)
    return img.resize((w, h), Image.BOX)  # 작은 한 색 아이콘은 면적 평균으로 줄여 가장자리 번짐을 막는다


def floating_window_xml():
    """Android 플로팅 창(FloatingWindowService 의 R.drawable.floating_window): 빨간 원 + 흰 W.
    업스트림 파일과 같은 320dp·viewport 32 를 쓴다(서비스가 intrinsic 크기로 그려 반으로 자른다)."""
    k = 19.2 / (LOGO_BOX[2] - LOGO_BOX[0])  # W. 폭 = 지름의 60%
    ox = 16 - (LOGO_BOX[0] + LOGO_BOX[2]) / 2 * k
    oy = 16 - (LOGO_BOX[1] + LOGO_BOX[3]) / 2 * k
    p = lambda x, y: f"{x * k + ox:.3f},{y * k + oy:.3f}"
    w = "M" + "L".join(p(x, y) for x, y in W_POLY) + "Z"
    dot = f"M{p(DOT[0], DOT[1])}L{p(DOT[2], DOT[1])}L{p(DOT[2], DOT[3])}L{p(DOT[0], DOT[3])}Z"
    bg = "#%02X%02X%02X" % BG[:3]
    return (
        '<vector xmlns:android="http://schemas.android.com/apk/res/android" android:width="320dp"'
        ' android:height="320dp" android:viewportWidth="32" android:viewportHeight="32">\n'
        f'    <path android:fillColor="{bg}" android:pathData="M16,0A16,16 0,0 1,32 16A16,16 0,0 1,16 32A16,16 0,0 1,0 16A16,16 0,0 1,16 0z"/>\n'
        f'    <path android:fillColor="#FFFFFF" android:pathData="{w}{dot}"/>\n'
        "</vector>\n"
    )


def save_ico(path, font_path, sizes=(16, 24, 32, 48, 64, 128, 256), badge=False):
    imgs = [render(s, "square", font_path, with_text=s > ICO_SMALL_MAX, badge=badge) for s in sizes]
    imgs[-1].save(path, format="ICO", sizes=[(s, s) for s in sizes], append_images=imgs[:-1], bitmap_format="bmp")


def save_icns(path, font_path, kind="mac"):
    entries = [
        ("16x16", 16), ("16x16@2x", 32), ("32x32", 32), ("32x32@2x", 64),
        ("128x128", 128), ("128x128@2x", 256), ("256x256", 256), ("256x256@2x", 512),
        ("512x512", 512), ("512x512@2x", 1024),
    ]
    tmp = tempfile.mkdtemp()
    try:
        iconset = os.path.join(tmp, "AppIcon.iconset")
        os.mkdir(iconset)
        for name, px in entries:
            render(px, kind, font_path).save(os.path.join(iconset, f"icon_{name}.png"))
        subprocess.run(["iconutil", "-c", "icns", iconset, "-o", path], check=True)
    finally:
        shutil.rmtree(tmp)


def save_ios(iconset, font_path):
    """Contents.json 의 크기·파일명 그대로 덮어쓴다. iOS 앱 아이콘은 알파가 없어야 한다."""
    with open(os.path.join(iconset, "Contents.json"), encoding="utf-8") as fp:
        images = json.load(fp)["images"]
    for e in images:
        px = round(float(e["size"].split("x")[0]) * int(e["scale"].rstrip("x")))
        render(px, "ios", font_path).convert("RGB").save(os.path.join(iconset, e["filename"]))


ANDROID_DENSITIES = {"mdpi": 1, "hdpi": 1.5, "xhdpi": 2, "xxhdpi": 3, "xxxhdpi": 4}


def save_incoming(root, font_path):
    """수신 전용 빌드가 덮어쓸 파일만 INCOMING_DIR 아래 같은 상대 경로로 쓴다."""
    def r(*p):
        path = os.path.join(root, INCOMING_DIR, *p)
        os.makedirs(os.path.dirname(path), exist_ok=True)
        return path

    ico = r("flutter/windows/runner/resources/app_icon.ico")
    save_ico(ico, font_path, badge=True)
    shutil.copyfile(ico, r("res/icon.ico"))
    shutil.copyfile(ico, r("flutter/assets/icon.ico"))
    res = "flutter/android/app/src/main/res"
    for dpi, f in ANDROID_DENSITIES.items():
        legacy = render(round(48 * f), "square", font_path, with_text=True, badge=True)
        legacy.save(r(res, f"mipmap-{dpi}", "ic_launcher.png"))
        legacy.save(r(res, f"mipmap-{dpi}", "ic_launcher_round.png"))
        fg = render(round(108 * f), "glyph", font_path, with_text=True, badge=True)
        fg.save(r(res, f"mipmap-{dpi}", "ic_launcher_foreground.png"))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--font", required=True, help="Montserrat[wght].ttf 경로")
    ap.add_argument("--root", default=".", help="저장소 루트")
    ap.add_argument("--mac-kind", default="mac", choices=["mac", "square"])
    ap.add_argument("--variant", default="bidirectional", choices=["bidirectional", "incoming"])
    ap.add_argument("--ios-only", action="store_true", help="iOS AppIcon 만 쓴다")
    a = ap.parse_args()
    if a.variant == "incoming":
        save_incoming(a.root, a.font)
        return
    r = lambda *p: os.path.join(a.root, *p)
    save_ios(r(IOS_ICONSET), a.font)
    if a.ios_only:
        return

    save_icns(r("flutter/macos/Runner/AppIcon.icns"), a.font, a.mac_kind)
    save_ico(r("flutter/windows/runner/resources/app_icon.ico"), a.font)
    shutil.copyfile(r("flutter/windows/runner/resources/app_icon.ico"), r("res/icon.ico"))
    shutil.copyfile(r("flutter/windows/runner/resources/app_icon.ico"), r("flutter/assets/icon.ico"))
    # 트레이(Windows·Linux)·CM 창·탭 아이콘. 16~32px 로 보이므로 W. 만
    render(64, "square", a.font, with_text=False).save(r("flutter/assets/icon.png"))
    render_template(56, 40, 28).save(r("res/mac-tray-dark-x2.png"))

    res = r("flutter/android/app/src/main/res")
    with open(os.path.join(res, "drawable", "floating_window.xml"), "w") as fp:
        fp.write(floating_window_xml())
    for dpi, f in ANDROID_DENSITIES.items():
        d = os.path.join(res, f"mipmap-{dpi}")
        # 런처는 밀도와 상관없이 48dp 로 보이고 'remote' 가 구분점이라 모든 밀도에 글자를 넣는다
        legacy = render(round(48 * f), "square", a.font, with_text=True)
        legacy.save(os.path.join(d, "ic_launcher.png"))
        legacy.save(os.path.join(d, "ic_launcher_round.png"))
        render(round(108 * f), "glyph", a.font, with_text=True).save(os.path.join(d, "ic_launcher_foreground.png"))
        # 알림(상태 표시줄) 아이콘: 24dp 에 흰 W., 좌우 2dp 여백
        px = round(24 * f)
        glyph_h = 20 * f * (LOGO_BOX[3] - LOGO_BOX[1]) / (LOGO_BOX[2] - LOGO_BOX[0])
        stat = render_template(px, px, glyph_h, (255, 255, 255, 255))
        stat.convert("LA").save(os.path.join(d, "ic_stat_logo.png"))


if __name__ == "__main__":
    main()
