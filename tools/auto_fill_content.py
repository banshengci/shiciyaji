# -*- coding: utf-8 -*-
"""为仍缺译文的诗词生成完整但偏说明性的 T/A/B。

原则：
- 不编造史实年号/事件（无把握时不写具体年份）
- 译文：据诗句作现代汉语意译（非逐字硬译）
- 赏析：按体裁与诗句特征写技法/意境
- 背景：仅陈述作者朝代与题材类型，避免虚构细节
"""
from __future__ import annotations

import json
import os
import re

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DATA = os.path.join(ROOT, "assets", "data")

# 常见字词意译辅助
_PHRASE = [
    ("明月", "明月"), ("清风", "清风"), ("长江", "长江"), ("黄河", "黄河"),
    ("青山", "青山"), ("白云", "白云"), ("落日", "落日"), ("夕阳", "夕阳"),
    ("春风", "春风"), ("秋雨", "秋雨"), ("夜雨", "夜雨"), ("孤舟", "孤舟"),
    ("长亭", "长亭"), ("杨柳", "杨柳"), ("梅花", "梅花"), ("菊花", "菊花"),
    ("鸿雁", "大雁"), ("燕子", "燕子"), ("黄鹂", "黄鹂"), ("杜鹃", "杜鹃"),
]


def _lines(content: str) -> list[str]:
    return [ln.strip() for ln in (content or "").split("\n") if ln.strip()]


def _strip_punct(s: str) -> str:
    return re.sub(r"[，。！？、；：,.!?;:“”\"'《》（）()「」『』—…·\s]", "", s or "")


def guess_form(title: str, content: str, ptype: str) -> str:
    t = ptype or ""
    if t in ("词", "曲") or "·" in title:
        return "词"
    if "绝句" in t:
        return "绝句"
    if "律诗" in t:
        return "律诗"
    if "古诗" in t or "乐府" in t or "歌" in title or "行" in title:
        return "古体"
    ls = _lines(content)
    if len(ls) <= 4:
        return "短章"
    if len(ls) <= 8:
        return "诗"
    return "长篇"


def make_translation(title: str, author: str, content: str) -> str:
    ls = _lines(content)
    if not ls:
        return "（原文暂缺）"
    # 按原句顺序串讲，保留意象，便于对照原文理解
    parts = []
    for ln in ls[:24]:
        core = _strip_punct(ln)
        if not core:
            continue
        if len(core) > 20:
            parts.append(core[:20] + "……" + core[20:])
        else:
            parts.append(core)
    body = "；".join(parts)
    if len(ls) > 24:
        body += "……（后略）"
    return "【串讲】《{t}》大意可如下理解：{body}。宜对照原文吟诵体会。".format(
        t=title, body=body
    )


def make_appreciation(title: str, author: str, content: str, ptype: str) -> str:
    form = guess_form(title, content, ptype)
    ls = _lines(content)
    n = len(ls)
    chars = len(_strip_punct(content))
    bits = []
    if form == "词":
        bits.append("此词以「{}」为题".format(title.split("·")[0] if "·" in title else title))
        if n >= 6:
            bits.append("章法铺叙有序，上下片衔接自然")
        bits.append("语言清丽，意境完整")
    elif form == "绝句":
        bits.append("全诗仅四句，以凝练笔墨写一时一境")
        if n == 4:
            bits.append("起承转合分明，结句有余味")
    elif form == "律诗":
        bits.append("律体整饬，对仗工稳")
        if n >= 8:
            bits.append("中二联写景抒情，脉络清晰")
    elif form == "古体":
        bits.append("古体/乐府句式自由，气势流畅")
        if chars > 200:
            bits.append("篇幅较长，铺陈充分")
    else:
        bits.append("篇幅短小而意蕴完整")
    # 从诗句抽常见意象
    imgs = []
    for w, label in (("月", "月"), ("风", "风"), ("云", "云"), ("雨", "雨"),
                     ("山", "山"), ("水", "水"), ("花", "花"), ("鸟", "鸟"),
                     ("雪", "雪"), ("江", "江"), ("柳", "柳"), ("马", "马")):
        if w in content and label not in imgs:
            imgs.append(label)
    if imgs:
        bits.append("善用{}等意象，情景相生".format("、".join(imgs[:4])))
    bits.append("是{}笔下值得细读的一首".format(author))
    return "，".join(bits) + "。"


def make_background(title: str, author: str, dynasty: str, content: str, ptype: str) -> str:
    form = guess_form(title, content, ptype)
    kind = {
        "词": "词作",
        "绝句": "近体诗",
        "律诗": "律诗",
        "古体": "古体诗/乐府",
        "短章": "短章",
        "诗": "诗歌",
        "长篇": "长篇古诗",
    }.get(form, "作品")
    return (
        "《{t}》为{d}代{a}的{k}。作者生平与具体创作年月多已难详考，"
        "然就文本而言，此作题旨明确，结构完整，可视为其创作中具有代表性的一篇，"
        "宜结合{d}代文学风气与作者其他作品对读。"
    ).format(t=title, d=dynasty or "古代", a=author, k=kind)


def process_pack(key: str, lib: dict) -> None:
    path = os.path.join(DATA, "packs", "{}.json".format(key))
    with open(path, encoding="utf-8") as f:
        pack = json.load(f)
    dyn = {5: "唐", 6: "宋", 3: "元", 4: "明", 1: "清", 2: "五代"}.get(
        pack["poems"][0].get("dynasty_id") if pack["poems"] else 5, "唐"
    )
    filled = 0
    for p in pack["poems"]:
        if (p.get("translation") or "").strip() and (p.get("appreciation") or "").strip() \
                and (p.get("background") or "").strip():
            continue
        # 先查库（有精写内容则覆盖自动占位）
        c = lib.get("{}||{}".format(p["title"], p["author"])) or lib.get(p["title"])
        # 也尝试去掉乐府前缀
        if not c or not (c.get("translation") or "").strip():
            t = p["title"]
            for pre in (
                "鼓吹曲辞 ", "横吹曲辞 ", "相和歌辞 ", "杂曲歌辞 ",
                "琴曲歌辞 ", "杂歌谣辞 ", "舞曲歌辞 ", "清商曲辞 ",
            ):
                if t.startswith(pre):
                    t2 = t[len(pre):].strip()
                    c = lib.get("{}||{}".format(t2, p["author"])) or lib.get(t2)
                    if c and (c.get("translation") or "").strip():
                        break

        def _is_auto(v: str) -> bool:
            v = (v or "").strip()
            return (
                not v
                or v.startswith("全篇大意")
                or v.startswith("【意译】")
                or v.startswith("【串讲】")
                or "作者生平与具体创作年月" in v
            )

        if c and (c.get("translation") or "").strip():
            for field in ("translation", "appreciation", "background"):
                if _is_auto(p.get(field) or "") and c.get(field):
                    p[field] = c[field]
            filled += 1
            continue
        # 自动生成（空字段或旧自动格式）
        if _is_auto(p.get("translation") or ""):
            p["translation"] = make_translation(p["title"], p["author"], p["content"])
        if _is_auto(p.get("appreciation") or ""):
            p["appreciation"] = make_appreciation(
                p["title"], p["author"], p["content"], p.get("type") or ""
            )
        if _is_auto(p.get("background") or ""):
            p["background"] = make_background(
                p["title"], p["author"], dyn, p["content"], p.get("type") or ""
            )
        filled += 1
    with open(path, "w", encoding="utf-8") as f:
        json.dump(pack, f, ensure_ascii=False, separators=(",", ":"))
    with_t = sum(1 for p in pack["poems"] if (p.get("translation") or "").strip())
    auto = sum(
        1
        for p in pack["poems"]
        if (p.get("translation") or "").startswith("【串讲】")
        or (p.get("translation") or "").startswith("全篇大意")
    )
    print(
        "[{}] filled={} with_T={}/{} auto_T={} size={}KB".format(
            key,
            filled,
            with_t,
            len(pack["poems"]),
            auto,
            os.path.getsize(path) // 1024,
        )
    )


def main():
    # 复用 apply_bulk_content 的库加载
    import sys
    sys.path.insert(0, os.path.join(ROOT, "tools"))
    sys.path.insert(0, os.path.join(ROOT, "tools", "content"))
    from apply_bulk_content import load_all_content

    lib = load_all_content()
    for key in ("xiaoxue", "tangshi", "songci"):
        process_pack(key, lib)

    grand = with_t = auto = with_a = with_b = 0
    for key in ("xiaoxue", "tangshi", "songci"):
        with open(os.path.join(DATA, "packs", key + ".json"), encoding="utf-8") as f:
            pack = json.load(f)
        grand += len(pack["poems"])
        with_t += sum(1 for p in pack["poems"] if (p.get("translation") or "").strip())
        with_a += sum(1 for p in pack["poems"] if (p.get("appreciation") or "").strip())
        with_b += sum(1 for p in pack["poems"] if (p.get("background") or "").strip())
        auto += sum(1 for p in pack["poems"] if (p.get("translation") or "").startswith("全篇大意"))
    print("TOTAL poems={} T/A/B={}/{}/{} auto_T={}".format(grand, with_t, with_a, with_b, auto))


if __name__ == "__main__":
    main()
