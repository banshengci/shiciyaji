# -*- coding: utf-8 -*-
"""
生成「诗词雅集」5 张商店宣传海报（1080x1920，9:16 竖屏）。
宣纸白底 + 朱砂雅字印章 + 真实诗词数据，新中式品牌调性统一。
输出到 build/store_screenshots/。
"""
import json, os
from PIL import Image, ImageDraw, ImageFont

ROOT = r"D:/xinxiangmu/shici_yaji"
FONT = r"C:/Windows/Fonts/simkai.ttf"
OUT = os.path.join(ROOT, "build", "store_screenshots")

W, H = 1080, 1920
PAPER = (0xF5, 0xF0, 0xE8)
DAI = (0x1A, 0x2A, 0x3A)
SEAL = (0xC4, 0x1A, 0x1A)
QING = (0x6B, 0x72, 0x80)
WHITE = (255, 255, 255)
LINE = (0xDD, 0xD3, 0xC0)
CARD_BG = (0xFB, 0xF7, 0xEE)
MOUNT = (0xE5, 0xDC, 0xC8)

CN_NUM = "零一二三四五六七八九十"


def fnt(px):
    return ImageFont.truetype(FONT, px)


def load_data():
    with open(os.path.join(ROOT, "assets/data/poems.json"), encoding="utf-8") as f:
        d = json.load(f)
    poems = d.get("poems", [])
    authors = {a["id"]: a["name"] for a in d.get("authors", [])}
    dyns = {dd["id"]: dd["name"] for dd in d.get("dynasties", [])}
    return poems, authors, dyns


def find(poems, title):
    for p in poems:
        if p.get("title") == title:
            return p
    return None


def draw_seal(d, cx, cy, r, ch="雅", fill=PAPER, bg=SEAL):
    d.ellipse([cx - r, cy - r, cx + r, cy + r], fill=bg)
    fn = fnt(int(r * 1.05))
    bbox = d.textbbox((0, 0), ch, font=fn)
    tw = bbox[2] - bbox[0]
    th = bbox[3] - bbox[1]
    d.text((cx - tw / 2 - bbox[0], cy - th / 2 - bbox[1]), ch, font=fn, fill=fill)


def header(d, subtitle):
    """顶部品牌区：左朱砂印章 + 标题 + 副标题 + 分隔线。"""
    draw_seal(d, 130, 145, 62)
    d.text((250, 95), "诗词雅集", font=fnt(78), fill=DAI)
    d.text((252, 190), subtitle, font=fnt(28), fill=QING)
    d.line([(90, 280), (W - 90, 280)], fill=LINE, width=2)
    # 标题右侧小印章
    draw_seal(d, W - 130, 145, 36)


def footer(d, slogan):
    """底部文案 + 平台 tag + 山纹装饰。"""
    # 底部山纹
    for off, hh in [(0.05, 70), (0.22, 100), (0.42, 80), (0.62, 110), (0.82, 90)]:
        pts = [(int(W * off), H - 360),
               (int(W * (off + 0.13)), H - 360 - hh),
               (int(W * (off + 0.26)), H - 360)]
        d.polygon(pts, fill=MOUNT)
    d.line([(90, H - 320), (W - 90, H - 320)], fill=LINE, width=2)
    d.text((W / 2, H - 270), slogan, font=fnt(46), fill=DAI, anchor="mm")
    d.text((W / 2, H - 210), "古典诗词 · 雅集共赏", font=fnt(30), fill=QING, anchor="mm")
    d.text((W / 2, H - 140), "Android  ·  iOS  ·  Windows",
           font=fnt(28), fill=SEAL, anchor="mm")


def card(d, x, y, w, h, fill=CARD_BG, radius=28):
    d.rounded_rectangle([x, y, x + w, y + h], radius=radius, fill=fill,
                        outline=(0xE0, 0xD5, 0xBF), width=2)


def draw_multiline(d, x, y, lines, font, fill, line_gap=14, max_w=None):
    """逐行绘制，超宽自动截断。"""
    cy = y
    for line in lines:
        s = line
        if max_w:
            while s and d.textlength(s, font=font) > max_w:
                s = s[:-1]
            if s != line and len(s) > 1:
                s = s[:-1] + "…"
        d.text((x, cy), s, font=font, fill=fill)
        cy += font.size + line_gap
    return cy


def trunc(d, s, font, max_w):
    while d.textlength(s, font=font) > max_w:
        s = s[:-1]
    if len(s) > 1:
        s = s[:-1] + "…"
    return s


# ---------- 海报 1：品牌主视觉 ----------
def poster_1(p):
    img = Image.new("RGB", (W, H), PAPER)
    d = ImageDraw.Draw(img)
    header(d, "品牌 · 经典传承")

    # 主题序号
    d.text((90, 320), "壹", font=fnt(56), fill=SEAL)
    d.text((90, 400), "千年雅韵，一卷开启", font=fnt(54), fill=DAI)

    # 大卡片：今日推荐
    card(d, 90, 520, W - 180, 540)
    d.text((130, 560), "今 · 日 · 推 · 荐", font=fnt(30), fill=QING)
    d.text((130, 620), p["title"], font=fnt(78), fill=DAI)
    d.text((130, 720), f"{dyn_name(p)} · {author_name(p)}", font=fnt(32), fill=QING)

    # 原文（取前两句）
    lines = p.get("content", "").split("\n")[:2]
    draw_multiline(d, 130, 800, lines, fnt(50), DAI, line_gap=22, max_w=W - 260)

    # 小装饰印章
    draw_seal(d, W - 180, 980, 44)

    # 价值卡片
    card(d, 90, 1100, W - 180, 460)
    d.text((130, 1140), "为热爱诗词的你而生", font=fnt(40), fill=DAI)
    feats = [
        "· 70 首经典 · 唐诗宋词精选",
        "· 艾宾浩斯 · 科学复习曲线",
        "· 沉浸阅读 · TTS 朗读",
        "· 深色模式 · 离线可用",
    ]
    draw_multiline(d, 140, 1220, feats, fnt(34), DAI, line_gap=58, max_w=W - 260)

    footer(d, "诗意人生，由此启程")
    return img


# ---------- 海报 2：诗词库 ----------
def poster_2(p1, p2, p3, p4, p5):
    img = Image.new("RGB", (W, H), PAPER)
    d = ImageDraw.Draw(img)
    header(d, "诗词库 · 经典收录")

    d.text((90, 320), "贰", font=fnt(56), fill=SEAL)
    d.text((90, 400), "唐诗宋词，灿若星河", font=fnt(54), fill=DAI)

    # 列表卡片
    card(d, 90, 520, W - 180, 1140)
    items = [
        ("静夜思", "唐 · 李白", "床前明月光，疑是地上霜。"),
        ("春晓", "唐 · 孟浩然", "春眠不觉晓，处处闻啼鸟。"),
        ("登鹳雀楼", "唐 · 王之涣", "白日依山尽，黄河入海流。"),
        ("望庐山瀑布", "唐 · 李白", "日照香炉生紫烟，遥看瀑布挂前川。"),
        ("早发白帝城", "唐 · 李白", "朝辞白帝彩云间，千里江陵一日还。"),
    ]
    cy = 580
    for i, (title, meta, line) in enumerate(items):
        # 序号小印章
        draw_seal(d, 160, cy + 30, 26, ch=CN_NUM[i + 1], bg=SEAL, fill=PAPER)
        d.text((210, cy), title, font=fnt(46), fill=DAI)
        d.text((W - 130, cy + 10), meta, font=fnt(28), fill=QING, anchor="ra")
        d.text((210, cy + 70),
               trunc(d, line + "……", fnt(30), W - 360),
               font=fnt(30), fill=QING)
        cy += 110

    # 顶部统计徽章
    badge_x, badge_y = W - 250, 400
    d.rounded_rectangle([badge_x, badge_y, badge_x + 160, badge_y + 90],
                        radius=18, fill=SEAL)
    d.text((badge_x + 80, badge_y + 20), "70 首", font=fnt(46), fill=PAPER, anchor="mm")
    d.text((badge_x + 80, badge_y + 62), "经典收录", font=fnt(20), fill=PAPER, anchor="mm")

    footer(d, "一诗一世界，一句一悠然")
    return img


# ---------- 海报 3：艾宾浩斯复习 ----------
def poster_3():
    img = Image.new("RGB", (W, H), PAPER)
    d = ImageDraw.Draw(img)
    header(d, "复习 · 科学记忆")

    d.text((90, 320), "叁", font=fnt(56), fill=SEAL)
    d.text((90, 400), "艾宾浩斯，记忆有道", font=fnt(54), fill=DAI)

    # 进度环卡片
    card(d, 90, 520, W - 180, 360)
    # 圆环
    cx, cy, r = 300, 700, 110
    d.ellipse([cx - r, cy - r, cx + r, cy + r], outline=LINE, width=22)
    # 弧（70% 进度）
    d.arc([cx - r, cy - r, cx + r, cy + r], -90, -90 + int(360 * 0.7),
          fill=SEAL, width=22)
    d.text((cx, cy - 10), "70%", font=fnt(58), fill=DAI, anchor="mm")
    d.text((cx, cy + 40), "今日复习", font=fnt(26), fill=QING, anchor="mm")

    # 右侧数据
    d.text((480, 610), "已掌握", font=fnt(28), fill=QING)
    d.text((480, 650), "12 首", font=fnt(48), fill=DAI)
    d.text((480, 720), "待复习", font=fnt(28), fill=QING)
    d.text((480, 760), "3 首", font=fnt(48), fill=SEAL)

    # 间隔列表
    card(d, 90, 920, W - 180, 600)
    d.text((130, 960), "间隔重复 · 黄金曲线", font=fnt(36), fill=DAI)
    intervals = [("第 1 天", "初次学习"), ("第 2 天", "首次复习"),
                 ("第 4 天", "再次复习"), ("第 7 天", "巩固复习"),
                 ("第 15 天", "长期记忆")]
    yy = 1040
    for i, (day, label) in enumerate(intervals):
        # 圆点
        d.ellipse([130, yy + 10, 158, yy + 38], fill=SEAL)
        d.text((190, yy), day, font=fnt(32), fill=DAI)
        d.text((W - 130, yy + 4), label, font=fnt(28), fill=QING, anchor="ra")
        yy += 90

    footer(d, "温故知新，日有所长")
    return img


# ---------- 海报 4：收藏与成就 ----------
def poster_4():
    img = Image.new("RGB", (W, H), PAPER)
    d = ImageDraw.Draw(img)
    header(d, "收藏 · 成就")

    d.text((90, 320), "肆", font=fnt(56), fill=SEAL)
    d.text((90, 400), "珍藏所爱，解锁成就", font=fnt(54), fill=DAI)

    # 收藏卡片
    card(d, 90, 520, W - 180, 660)
    d.text((130, 560), "我的收藏", font=fnt(36), fill=DAI)
    favs = [
        ("静夜思", "唐 · 李白"),
        ("春晓", "唐 · 孟浩然"),
        ("登鹳雀楼", "唐 · 王之涣"),
    ]
    yy = 640
    for title, meta in favs:
        # 心形（用 ellipse + triangle 简化）
        d.ellipse([125, yy + 5, 155, yy + 35], fill=SEAL)
        d.ellipse([150, yy + 5, 180, yy + 35], fill=SEAL)
        d.polygon([(120, yy + 25), (185, yy + 25), (152, yy + 70)], fill=SEAL)
        d.text((210, yy), title, font=fnt(38), fill=DAI)
        d.text((W - 130, yy + 4), meta, font=fnt(26), fill=QING, anchor="ra")
        yy += 110

    # 成就卡片
    card(d, 90, 1220, W - 180, 360)
    d.text((130, 1260), "已解锁成就", font=fnt(36), fill=DAI)

    achvs = [("初学者", SEAL), ("笔记达人", SEAL), ("持之以恒", SEAL)]
    for i, (name, c) in enumerate(achvs):
        ax = 150 + i * 290
        d.rounded_rectangle([ax, 1340, ax + 220, 1500], radius=18,
                            outline=c, width=3, fill=CARD_BG)
        draw_seal(d, ax + 110, 1390, 36, bg=c, fill=PAPER)
        d.text((ax + 110, 1470), name, font=fnt(28), fill=DAI, anchor="mm")

    footer(d, "每一次翻阅，皆有回响")
    return img


# ---------- 海报 5：沉浸阅读 ----------
def poster_5(p):
    img = Image.new("RGB", (W, H), PAPER)
    d = ImageDraw.Draw(img)
    header(d, "阅读 · 沉浸")

    d.text((90, 320), "伍", font=fnt(56), fill=SEAL)
    d.text((90, 400), "沉浸阅读，诗意栖居", font=fnt(54), fill=DAI)

    # 详情卡片（大）
    card(d, 90, 520, W - 180, 1240)
    # 标题栏
    d.text((130, 560), p["title"], font=fnt(72), fill=DAI)
    d.text((130, 650), f"{dyn_name(p)} · {author_name(p)}", font=fnt(30), fill=QING)
    d.line([(130, 710), (W - 130, 710)], fill=LINE, width=2)

    # 原文（每句一行）
    d.text((130, 740), "【原文】", font=fnt(28), fill=SEAL)
    lines = p.get("content", "").split("\n")
    draw_multiline(d, 130, 790, lines[:6], fnt(38), DAI,
                   line_gap=18, max_w=W - 260)

    # 译文
    trans = (p.get("translation") or "").strip()
    if trans:
        d.text((130, 1110), "【译文】", font=fnt(28), fill=SEAL)
        draw_multiline(d, 130, 1155, [trans], fnt(30), QING,
                       line_gap=14, max_w=W - 260)

    # 功能徽章
    feats = ["深色模式", "TTS 朗读", "离线可用"]
    fx = W - 470
    for f in feats:
        d.rounded_rectangle([fx, 1620, fx + 140, 1680], radius=20,
                            outline=SEAL, width=2)
        d.text((fx + 70, 1650), f, font=fnt(24), fill=SEAL, anchor="mm")
        fx += 150

    footer(d, "读你千遍，亦不厌倦")
    return img


def dyn_name(p):
    return p.get("dynasty_name") or ""


def author_name(p):
    return p.get("author_name") or ""


def enrich(p, dyns, authors):
    if not p:
        return None
    p = dict(p)
    p["dynasty_name"] = dyns.get(p.get("dynasty_id"), "")
    p["author_name"] = authors.get(p.get("author_id"), "")
    return p


def main():
    os.makedirs(OUT, exist_ok=True)
    poems_raw, dyns, authors = load_data()

    p_jys = enrich(find(poems_raw, "静夜思"), dyns, authors)
    p_cx = enrich(find(poems_raw, "春晓"), dyns, authors)
    p_dgl = enrich(find(poems_raw, "登鹳雀楼"), dyns, authors)
    p_wl = enrich(find(poems_raw, "望庐山瀑布"), dyns, authors)
    p_zf = enrich(find(poems_raw, "早发白帝城"), dyns, authors)

    def save(img, name):
        path = os.path.join(OUT, name)
        img.save(path, "PNG", optimize=True)
        print("  ->", os.path.relpath(path, ROOT))

    print("[Store Screenshots]")
    save(poster_1(p_jys), "01_brand.png")
    save(poster_2(p_cx, p_dgl, p_wl, p_jys, p_zf), "02_library.png")
    save(poster_3(), "03_review.png")
    save(poster_4(), "04_favorites_achievements.png")
    save(poster_5(p_jys), "05_immersion.png")
    print("DONE")


if __name__ == "__main__":
    main()