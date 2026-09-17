# -*- coding: utf-8 -*-
"""把仍为「原文照抄/截取」的译文清空，避免 App 把原文当译文展示。

宁可显示「暂无译文」，也不展示错误内容。
"""
from __future__ import annotations

import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
PACKS = ROOT / "assets" / "data" / "packs"
SUSPECTS = ROOT / "tools" / "suspect_translations.json"

PUNCT = re.compile(r"[，。！？、；：,.!?;:\s「」『』（）()《》〈〉—…“”\"'’]")
MODERN = ["的", "了", "着", "过", "吗", "呢", "把", "被", "这", "那",
          "一个", "可以", "已经", "没有", "就是", "什么", "怎么", "因为", "所以"]


def strip_punct(s: str) -> str:
    return PUNCT.sub("", s or "")


def char_jaccard(a: str, b: str) -> float:
    sa, sb = set(strip_punct(a)), set(strip_punct(b))
    if not sa or not sb:
        return 0.0
    return len(sa & sb) / len(sa | sb)


def modern_density(t: str) -> float:
    body = strip_punct(t)
    if not body:
        return 0.0
    return sum(body.count(w) for w in MODERN) / len(body)


def is_bad_translation(content: str, trans: str) -> bool:
    if not trans or not trans.strip():
        return False
    body = strip_punct(trans)
    if len(body) < 15:
        return True
    jac = char_jaccard(content, trans)
    dens = modern_density(trans)
    if jac >= 0.90:
        return True
    if jac >= 0.78 and dens < 0.015:
        return True
    # 译文是原文连续片段且几乎没有现代汉语
    if dens < 0.012 and len(body) < len(strip_punct(content)) * 0.6:
        # 再确认是否大量来自原文
        if jac >= 0.5:
            return True
    return False


def main() -> None:
    cleared = 0
    per_pack: dict[str, int] = {}
    for path in sorted(PACKS.glob("*.json")):
        if path.name == "xiaoxue.json":
            # 小学包已手写，仍扫一遍以防漏网
            pass
        data = json.loads(path.read_text(encoding="utf-8"))
        poems = data if isinstance(data, list) else data.get("poems", data.get("items", []))
        n = 0
        for p in poems:
            content = p.get("content") or ""
            trans = (p.get("translation") or "").strip()
            if is_bad_translation(content, trans):
                p["translation"] = ""
                n += 1
        if n:
            path.write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
            per_pack[path.name] = n
            cleared += n
            print(f"cleared {n} in {path.name}")
    print("total cleared", cleared, per_pack)


if __name__ == "__main__":
    main()
