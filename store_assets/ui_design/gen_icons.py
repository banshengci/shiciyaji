# -*- coding: utf-8 -*-
"""生成诗词雅集三端图标包：Android / iOS / Windows。
图标：黛蓝圆角方 + 书卷图形 + 朱砂红「诗」印章。中文用系统字体，保证 CJK 正确渲染。
"""
import os, math, json, struct
from PIL import Image, ImageDraw, ImageFont

BASE = os.path.dirname(os.path.abspath(__file__))
OUT  = os.path.join(BASE, "icons")
ASSETS = os.path.join(BASE, "assets")

# 品牌色
DAILAN  = (26, 42, 58, 255)      # #1A2A3A
XUANZHI = (245, 240, 232, 255)   # #F5F0E8
ZHUSHA  = (196, 26, 26, 255)     # #C41A1A

# 中文字体（Windows 自带）
FONT_CANDIDATES = [
    "C:/Windows/Fonts/msyh.ttc",
    "C:/Windows/Fonts/simhei.ttf",
    "C:/Windows/Fonts/simsun.ttc",
]
FONT_PATH = next((f for f in FONT_CANDIDATES if os.path.exists(f)), None)
if not FONT_PATH:
    raise SystemExit("未找到系统中文字体")

def font(size, bold=False):
    try:
        return ImageFont.truetype(FONT_PATH, size, index=1 if (bold and FONT_PATH.endswith('.ttc')) else 0)
    except Exception:
        return ImageFont.truetype(FONT_PATH, size)

def rounded_rect(d, box, r, fill=None, outline=None, width=1):
    d.rounded_rectangle(box, radius=r, fill=fill, outline=outline, width=width)

def draw_book(d, S, color, fill):
    """绘制书卷图形（与 SVG 比例一致，使用贝塞尔采样）。"""
    cx, cy = S/2, S/2
    w = S * 0.31          # 页半宽
    h = S * 0.165         # 页半高
    top, bot = cy - h, cy + h
    lw = w
    def cubic(p0, p1, p2, p3, n=24):
        pts = []
        for i in range(n+1):
            t = i/n; u = 1-t
            x = u*u*u*p0[0] + 3*u*u*t*p1[0] + 3*u*t*t*p2[0] + t*t*t*p3[0]
            y = u*u*u*p0[1] + 3*u*u*t*p1[1] + 3*u*t*t*p2[1] + t*t*t*p3[1]
            pts.append((x, y))
        return pts
    # 左页：上缘曲线外凸，下缘曲线外凸
    left = cubic((cx, top), (cx-lw*0.8, top-h*0.15), (cx-lw*1.05, top-h*0.05), (cx-lw, top+h*0.12))
    left += [(cx-lw, bot-h*0.12)]
    left += cubic((cx-lw, bot-h*0.12), (cx-lw*1.05, bot-h*0.05), (cx-lw*0.8, bot+h*0.15), (cx, bot))
    # 右页
    right = cubic((cx, top), (cx+lw*0.8, top-h*0.15), (cx+lw*1.05, top-h*0.05), (cx+lw, top+h*0.12))
    right += [(cx+lw, bot-h*0.12)]
    right += cubic((cx+lw, bot-h*0.12), (cx+lw*1.05, bot-h*0.05), (cx+lw*0.8, bot+h*0.15), (cx, bot))
    if fill:
        d.polygon(left, fill=fill)
        d.polygon(right, fill=fill)
    if color:
        lw_stroke = max(2, int(S*0.028))
        d.line(left, fill=color, width=lw_stroke, joint="curve")
        d.line(right, fill=color, width=lw_stroke, joint="curve")
        # 书脊
        d.line([(cx, top), (cx, bot)], fill=color, width=max(2, int(S*0.018)))
        # 页面横线
        ls = max(1, int(S*0.014))
        for dy in (-h*0.28, h*0.18):
            d.line([(cx-lw*0.82, cy+dy-h*0.06), (cx-lw*0.18, cy+dy-h*0.14)], fill=color, width=ls)
            d.line([(cx+lw*0.18, cy+dy-h*0.14), (cx+lw*0.82, cy+dy-h*0.06)], fill=color, width=ls)

def draw_icon(S, mode="full"):
    """mode: full(带背景，用于 iOS/Windows/Android legacy) | fg(透明，仅图形) | bg(纯色块)。"""
    # full / bg：整图铺满黛蓝（应用商店/平台切片要求实色方图）
    img = Image.new("RGBA", (S, S), DAILAN if mode in ("full","bg") else (0,0,0,0))
    d = ImageDraw.Draw(img)
    if mode in ("full", "bg"):
        rounded_rect(d, [0,0,S,S], int(S*0.218), outline=(79,111,143,70), width=max(1,int(S*0.006)))
    if mode in ("full", "fg"):
        # 内描边 苍青 细线
        if mode == "full":
            rounded_rect(d, [S*0.043, S*0.043, S*0.957, S*0.957], int(S*0.188),
                         outline=(79,111,143,90), width=max(1,int(S*0.006)))
        draw_book(d, S, XUANZHI, (245,240,232,22))
        # 朱砂红印章 + 诗
        ss = S*0.105
        sx = S - S*0.10 - ss
        sy = S - S*0.10 - ss
        rounded_rect(d, [sx, sy, sx+ss, sy+ss], int(ss*0.18), fill=ZHUSHA)
        f = font(int(ss*0.7))
        d.text((sx+ss/2, sy+ss/2), "诗", font=f, fill=XUANZHI, anchor="mm")
    return img

def save(img, path):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    img.save(path, "PNG")
    print("  ->", os.path.relpath(path, BASE))

# ---------------- Android ----------------
def gen_android():
    print("[Android]")
    a = os.path.join(OUT, "android")
    densities = {"mdpi":48, "hdpi":72, "xhdpi":96, "xxhdpi":144, "xxxhdpi":192}
    for dn, sz in densities.items():
        full = draw_icon(sz, "full")
        save(full, os.path.join(a, "res", f"mipmap-{dn}", "ic_launcher.png"))
        save(full, os.path.join(a, "res", f"mipmap-{dn}", "ic_launcher_round.png"))
    # 自适应图标 108
    save(draw_icon(108, "foreground"), os.path.join(a, "res", "mipmap-anydpi-v26", "ic_launcher_foreground.png"))
    save(draw_icon(108, "background"), os.path.join(a, "res", "mipmap-anydpi-v26", "ic_launcher_background.png"))
    # 应用商店 512
    save(draw_icon(512, "full"), os.path.join(a, "play_store", "feature_graphic_icon_512.png"))
    # 复制矢量前景/背景层（已有 SVG）
    import shutil
    for f in ("icon_fg.svg", "icon_bg.svg", "icon_launcher.svg"):
        src = os.path.join(ASSETS, f)
        if os.path.exists(src):
            shutil.copy(src, os.path.join(a, f))
    # 自适应图标 XML
    with open(os.path.join(a, "res", "mipmap-anydpi-v26", "ic_launcher.xml"), "w", encoding="utf-8") as fp:
        fp.write('''<?xml version="1.0" encoding="utf-8"?>
<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">
    <background android:drawable="@mipmap/ic_launcher_background"/>
    <foreground android:drawable="@mipmap/ic_launcher_foreground"/>
</adaptive-icon>
''')
    with open(os.path.join(a, "res", "mipmap-anydpi-v26", "ic_launcher_round.xml"), "w", encoding="utf-8") as fp:
        fp.write('''<?xml version="1.0" encoding="utf-8"?>
<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">
    <background android:drawable="@mipmap/ic_launcher_background"/>
    <foreground android:drawable="@mipmap/ic_launcher_foreground"/>
</adaptive-icon>
''')

# ---------------- iOS ----------------
def gen_ios():
    print("[iOS]")
    i = os.path.join(OUT, "ios", "AppIcon.appiconset")
    sizes = [20,29,40,58,60,76,80,87,120,152,167,180,1024]
    for sz in sizes:
        save(draw_icon(sz, "full"), os.path.join(i, f"appicon_{sz}x{sz}.png"))
    images = [
        {"idiom":"iphone", "size":"20x20", "scale":"2x", "filename":"appicon_40x40.png"},
        {"idiom":"iphone", "size":"20x20", "scale":"3x", "filename":"appicon_60x60.png"},
        {"idiom":"ipad", "size":"20x20", "scale":"1x", "filename":"appicon_20x20.png"},
        {"idiom":"ipad", "size":"20x20", "scale":"2x", "filename":"appicon_40x40.png"},
        {"idiom":"iphone", "size":"29x29", "scale":"1x", "filename":"appicon_29x29.png"},
        {"idiom":"iphone", "size":"29x29", "scale":"2x", "filename":"appicon_58x58.png"},
        {"idiom":"iphone", "size":"29x29", "scale":"3x", "filename":"appicon_87x87.png"},
        {"idiom":"ipad", "size":"29x29", "scale":"1x", "filename":"appicon_29x29.png"},
        {"idiom":"ipad", "size":"29x29", "scale":"2x", "filename":"appicon_58x58.png"},
        {"idiom":"iphone", "size":"40x40", "scale":"2x", "filename":"appicon_80x80.png"},
        {"idiom":"iphone", "size":"40x40", "scale":"3x", "filename":"appicon_120x120.png"},
        {"idiom":"ipad", "size":"40x40", "scale":"1x", "filename":"appicon_40x40.png"},
        {"idiom":"ipad", "size":"40x40", "scale":"2x", "filename":"appicon_80x80.png"},
        {"idiom":"iphone", "size":"60x60", "scale":"2x", "filename":"appicon_120x120.png"},
        {"idiom":"iphone", "size":"60x60", "scale":"3x", "filename":"appicon_180x180.png"},
        {"idiom":"ipad", "size":"76x76", "scale":"1x", "filename":"appicon_76x76.png"},
        {"idiom":"ipad", "size":"76x76", "scale":"2x", "filename":"appicon_152x152.png"},
        {"idiom":"ipad", "size":"83.5x83.5", "scale":"2x", "filename":"appicon_167x167.png"},
        {"idiom":"ios-marketing", "size":"1024x1024", "scale":"1x", "filename":"appicon_1024x1024.png"}
    ]
    contents = {"images":images, "info":{"version":1,"author":"xinxiangmu"}}
    with open(os.path.join(i, "Contents.json"), "w", encoding="utf-8") as fp:
        json.dump(contents, fp, ensure_ascii=False, indent=2)
    print("  -> AppIcon.appiconset/Contents.json")

# ---------------- Windows (UWP / WinUI) ----------------
def gen_windows():
    print("[Windows]")
    w = os.path.join(OUT, "windows")
    # 目标尺寸（UWP 常见）
    base = {
        "Square44x44Logo": 44, "Square71x71Logo": 71, "Square89x89Logo": 89,
        "Square107x107Logo": 107, "Square142x142Logo": 142, "Square150x150Logo": 150,
        "Square284x284Logo": 284, "Square310x310Logo": 310,
        "StoreLogo": 50, "Wide310x150Logo": None,  # 宽图单独处理
        "BadgeLogo": 24,
    }
    for name, sz in base.items():
        if sz is None: continue
        save(draw_icon(sz, "full"), os.path.join(w, f"{name}.png"))
    # 宽图 310x150
    wide = Image.new("RGBA", (310,150), (0,0,0,0))
    dw = ImageDraw.Draw(wide)
    rounded_rect(dw, [0,0,310,150], 30, fill=DAILAN)
    # 居中放置图标（按高度缩放）
    sub = draw_icon(150, "full")
    wide.paste(sub, (80, 0), sub)
    save(wide, os.path.join(w, "Wide310x150Logo.png"))
    # 启动图 620x300
    sp = Image.new("RGBA", (620,300), (0,0,0,0))
    dsp = ImageDraw.Draw(sp)
    rounded_rect(dsp, [0,0,620,300], 40, fill=DAILAN)
    sub2 = draw_icon(180, "full")
    sp.paste(sub2, (220, 60), sub2)
    df = font(28); dsp.text((310,262), "品读千年文脉，传承诗词之美", font=df, fill=XUANZHI, anchor="mm")
    save(sp, os.path.join(w, "SplashScreen.png"))
    # .ico 多尺寸（Win32 桌面）→ 纯 Python 写入 ICO 目录结构
    ico_sizes = [16,32,48,256]
    tmp_paths = []
    for s in ico_sizes:
        tp = os.path.join(w, f"_ico_{s}.png")
        draw_icon(s, "full").save(tp, "PNG")
        tmp_paths.append(tp)
    ico_path = os.path.join(w, "appicon.ico")

    def png_size(path):
        with open(path, 'rb') as f:
            d = f.read(24)
            return struct.unpack('>II', d[16:24])

    def make_ico(pngs, out):
        entries = []
        offset = 6 + 16 * len(pngs)
        data = b''
        for p in pngs:
            with open(p, 'rb') as f:
                blob = f.read()
            w, h = png_size(p)
            w = 0 if w >= 256 else w
            h = 0 if h >= 256 else h
            entries.append(struct.pack('<BBBBHHII', w, h, 0, 0, 1, 32, len(blob), offset))
            data += blob
            offset += len(blob)
        with open(out, 'wb') as f:
            f.write(struct.pack('<HHH', 0, 1, len(pngs)))
            for e in entries:
                f.write(e)
            f.write(data)

    make_ico(tmp_paths, ico_path)
    for p in tmp_paths:
        try:
            os.remove(p)
        except OSError:
            pass
    print("  ->", os.path.relpath(ico_path, BASE))

if __name__ == "__main__":
    gen_android()
    gen_ios()
    gen_windows()
    print("\n字体:", FONT_PATH)
    print("全部图标生成完成。")
