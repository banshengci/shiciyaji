# -*- coding: utf-8 -*-
"""
生成「诗词雅集」新中式 App 图标。
视觉：黛蓝圆角方底 + 朱砂红圆形印章 + 楷体「雅」字（宣纸白）。
按目标尺寸矢量重绘（非缩放），保证小尺寸清晰。
输出：Android mipmap、Windows runner/resources、iOS AppIcon.appiconset、Play Store 512。
"""
import os
from PIL import Image, ImageDraw, ImageFont

ROOT = r"D:/xinxiangmu/shici_yaji"
FONT = r"C:/Windows/Fonts/simkai.ttf"

BG = (0x1A, 0x2A, 0x3A, 255)      # 黛蓝
SEAL = (0xC4, 0x1A, 0x1A, 255)    # 朱砂红
PAPER = (0xF5, 0xF0, 0xE8, 255)   # 宣纸白
SUB = (0xCF, 0xC9, 0xBE, 255)     # 宣纸白（暗）副文字


def font(px):
    return ImageFont.truetype(FONT, px)


def draw_centered_text(d, box, text, fnt, fill):
    """在 box=(x0,y0,x1,y1) 内居中绘制 text。"""
    bbox = d.textbbox((0, 0), text, font=fnt)
    tw = bbox[2] - bbox[0]
    th = bbox[3] - bbox[1]
    x = (box[0] + box[2]) / 2 - tw / 2 - bbox[0]
    y = (box[1] + box[3]) / 2 - th / 2 - bbox[1]
    d.text((x, y), text, font=fnt, fill=fill)


def make_square(size, radius_ratio=0.18):
    """方形（圆角）图标母图，按需绘制。"""
    img = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    r = max(1, int(size * radius_ratio))
    d.rounded_rectangle([0, 0, size - 1, size - 1], radius=r, fill=BG)
    # 朱砂印章圆
    seal_r = int(size * 0.33)
    cx = cy = size // 2
    d.ellipse([cx - seal_r, cy - seal_r, cx + seal_r, cy + seal_r], fill=SEAL)
    # 极淡内描边，提升印章质感
    ring = max(1, int(size * 0.010))
    d.ellipse([cx - seal_r + ring, cy - seal_r + ring,
               cx + seal_r - ring, cy + seal_r - ring],
              outline=(PAPER[0], PAPER[1], PAPER[2], 45), width=ring)
    # 「雅」字
    draw_centered_text(d, [cx - seal_r, cy - seal_r, cx + seal_r, cy + seal_r],
                       "雅", font(int(size * 0.52)), PAPER)
    return img


def make_banner(w, h):
    """横幅（SplashScreen / Wide 磁贴）：黛蓝底 + 左印章 + 右文字。"""
    img = Image.new("RGBA", (w, h), BG)
    d = ImageDraw.Draw(img)
    seal = int(h * 0.60)
    sx = int(h * 0.24)
    sy = (h - seal) // 2
    d.ellipse([sx, sy, sx + seal, sy + seal], fill=SEAL)
    draw_centered_text(d, [sx, sy, sx + seal, sy + seal], "雅",
                       font(int(seal * 0.82)), PAPER)
    tx = sx + seal + int(w * 0.05)
    draw_centered_text(d, [tx, int(h * 0.12), w - int(w * 0.04), int(h * 0.58)],
                       "诗词雅集", font(int(h * 0.40)), PAPER)
    draw_centered_text(d, [tx, int(h * 0.60), w - int(w * 0.04), int(h * 0.92)],
                       "古典诗词 · 雅集共赏", font(int(h * 0.15)), SUB)
    return img


def save_png(img, path):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    img.save(path, "PNG")
    print("  ->", os.path.relpath(path, ROOT))


# ---------- Android ----------
def gen_android():
    print("[Android]")
    res = os.path.join(ROOT, "android", "app", "src", "main", "res")
    densities = {
        "mipmap-mdpi": 48,
        "mipmap-hdpi": 72,
        "mipmap-xhdpi": 96,
        "mipmap-xxhdpi": 144,
        "mipmap-xxxhdpi": 192,
    }
    for dname, px in densities.items():
        im = make_square(px)
        save_png(im, os.path.join(res, dname, "ic_launcher.png"))
        save_png(im, os.path.join(res, dname, "ic_launcher_round.png"))
    # Play Store 512
    save_png(make_square(512), os.path.join(ROOT, "assets", "store", "icon-playstore-512.png"))


# ---------- Windows ----------
def gen_windows():
    print("[Windows]")
    res = os.path.join(ROOT, "windows", "runner", "resources")
    squares = {
        "Square44x44Logo.png": 44,
        "Square71x71Logo.png": 71,
        "Square89x89Logo.png": 89,
        "Square107x107Logo.png": 107,
        "Square142x142Logo.png": 142,
        "Square150x150Logo.png": 150,
        "Square284x284Logo.png": 284,
        "Square310x310Logo.png": 310,
        "StoreLogo.png": 50,
        "BadgeLogo.png": 24,
    }
    for fname, px in squares.items():
        save_png(make_square(px), os.path.join(res, fname))
    # ico（多尺寸合一）
    ico_sizes = [16, 24, 32, 48, 64, 128, 256]
    imgs = [make_square(s) for s in ico_sizes]
    os.makedirs(res, exist_ok=True)
    imgs[0].save(os.path.join(res, "app_icon.ico"),
                 sizes=[(s, s) for s in ico_sizes])
    print("  ->", "windows/runner/resources/app_icon.ico")
    # 横幅
    save_png(make_banner(620, 300), os.path.join(res, "SplashScreen.png"))
    save_png(make_banner(310, 150), os.path.join(res, "Wide310x150Logo.png"))


# ---------- iOS ----------
IOS_ICONS = [
    ("Icon-20x20@1x.png", 20),
    ("Icon-20x20@2x.png", 40),
    ("Icon-20x20@3x.png", 60),
    ("Icon-29x29@1x.png", 29),
    ("Icon-29x29@2x.png", 58),
    ("Icon-29x29@3x.png", 87),
    ("Icon-40x40@1x.png", 40),
    ("Icon-40x40@2x.png", 80),
    ("Icon-40x40@3x.png", 120),
    ("Icon-60x60@2x.png", 120),
    ("Icon-60x60@3x.png", 180),
    ("Icon-76x76@1x.png", 76),
    ("Icon-76x76@2x.png", 152),
    ("Icon-83.5x83.5@2x.png", 167),
    ("Icon-1024x1024@1x.png", 1024),
]


def gen_ios():
    print("[iOS]")
    d = os.path.join(ROOT, "ios", "Runner", "Assets.xcassets", "AppIcon.appiconset")
    os.makedirs(d, exist_ok=True)
    images = []
    for fname, px in IOS_ICONS:
        save_png(make_square(px), os.path.join(d, fname))
        # 解析 idiom/size/scale
        base = fname.replace("Icon-", "").replace(".png", "")
        if "@" in base:
            sizepart, scalepart = base.split("@")
            scale = scalepart.replace("x", "")
            size = sizepart.replace("x", "x")
        else:
            size = base.replace("x", "x")
            scale = "1x"
        w, h = size.split("x")
        images.append({
            "idiom": "universal",
            "platform": "ios",
            "size": f"{w}x{h}",
            "scale": scale,
            "filename": fname,
        })
    contents = {
        "images": images,
        "info": {"author": "xcode", "version": 1},
    }
    import json
    with open(os.path.join(d, "Contents.json"), "w", encoding="utf-8") as f:
        json.dump(contents, f, indent=2, ensure_ascii=False)
    print("  ->", "ios/Runner/Assets.xcassets/AppIcon.appiconset/Contents.json")


if __name__ == "__main__":
    gen_android()
    gen_windows()
    gen_ios()
    print("DONE")
