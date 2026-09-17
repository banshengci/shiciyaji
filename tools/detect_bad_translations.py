# -*- coding: utf-8 -*-
"""严格坏译文检测 v2：只抓真正「译文=原文/仅截取原文/串包」的硬伤。

判据（可复现）：
1. empty / whitespace
2. short: 去标点后 < 15 字
3. copy_exact: 译文去标点后几乎等于原文
4. copy_lines: 译文由原文连续诗句组成（覆盖原文连续片段 >= 0.7）
5. high_char_overlap: 字符 Jaccard > 0.78 且现代汉语功能词很少

不把「好译文与原文字面重叠」误伤进来（名篇白话译文常含原词）。
"""
from __future__ import annotations

import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
PACKS = ROOT / "assets" / "data" / "packs"
OUT = ROOT / "tools" / "suspect_translations.json"

PUNCT = re.compile(r"[，。！？、；：,.!?;:\s「」『』（）()《》〈〉—…“”\"'’]")
# 现代汉语常见虚词/代词，好译文里应有一定密度
MODERN_FUNCS = [
    "的", "了", "着", "过", "吗", "呢", "把", "被", "这", "那",
    "一个", "可以", "已经", "没有", "就是", "什么", "怎么",
    "因为", "所以", "但是", "如果", "我们", "自己", "时候",
]


def strip_punct(s: str) -> str:
    return PUNCT.sub("", s or "")


def modern_func_density(t: str) -> float:
    body = strip_punct(t)
    if not body:
        return 0.0
    hits = sum(body.count(w) for w in MODERN_FUNCS)
    # 按「词次/字数」粗算
    return hits / len(body)


def longest_common_substring_ratio(a: str, b: str) -> float:
    """b 能在 a 中找到的最长公共子串 / len(b)。用于「译文是否原文连续片段」。"""
    sa, sb = strip_punct(a), strip_punct(b)
    if not sa or not sb:
        return 0.0
    # 对短文本 O(n*m) 可接受
    m, n = len(sa), len(sb)
    dp = [0] * (n + 1)
    best = 0
    for i in range(1, m + 1):
        prev = 0
        for j in range(1, n + 1):
            cur = dp[j]
            if sa[i - 1] == sb[j - 1]:
                dp[j] = prev + 1
                if dp[j] > best:
                    best = dp[j]
            else:
                dp[j] = 0
            prev = cur
    return best / n


def char_jaccard(a: str, b: str) -> float:
    sa, sb = set(strip_punct(a)), set(strip_punct(b))
    if not sa or not sb:
        return 0.0
    return len(sa & sb) / len(sa | sb)


def load_packs() -> list[dict]:
    out: list[dict] = []
    for name in ("tangshi.json", "songci.json", "xiaoxue.json"):
        data = json.loads((PACKS / name).read_text(encoding="utf-8"))
        poems = data if isinstance(data, list) else data.get("poems", data.get("items", []))
        for p in poems:
            q = dict(p)
            q["_pack"] = name
            out.append(q)
    return out


def classify(poem: dict) -> list[str]:
    content = poem.get("content") or ""
    trans = (poem.get("translation") or "").strip()
    reasons: list[str] = []
    if not trans:
        return ["empty"]
    body = strip_punct(trans)
    if len(body) < 15:
        reasons.append("short")
    jac = char_jaccard(content, trans)
    lcs = longest_common_substring_ratio(content, trans)
    dens = modern_func_density(trans)
    # 译文几乎就是原文
    if jac >= 0.90 or (lcs >= 0.70 and dens < 0.02):
        reasons.append("copy_of_original")
    elif jac >= 0.78 and dens < 0.015:
        reasons.append("high_overlap_low_modern")
    elif lcs >= 0.55 and dens < 0.015:
        reasons.append("copy_lines")
    return reasons


def main() -> None:
    poems = load_packs()
    suspects = []
    counts: dict[str, int] = {}
    for p in poems:
        reasons = classify(p)
        if not reasons:
            continue
        for r in reasons:
            counts[r] = counts.get(r, 0) + 1
        suspects.append(
            {
                "pack": p["_pack"],
                "id": p.get("id"),
                "title": p.get("title"),
                "author": p.get("author"),
                "reasons": reasons,
                "translation_preview": (p.get("translation") or "")[:140],
                "content_preview": (p.get("content") or "")[:80],
            }
        )
    print(f"total poems: {len(poems)}")
    print(f"suspect: {len(suspects)}")
    print("reason counts:", json.dumps(counts, ensure_ascii=False, indent=2))
    by_pack: dict[str, int] = {}
    for s in suspects:
        by_pack[s["pack"]] = by_pack.get(s["pack"], 0) + 1
    print("by pack:", by_pack)
    print("\n--- samples ---")
    for s in suspects[:12]:
        print(s["id"], s["title"], s["author"], s["reasons"])
        print("  T:", s["translation_preview"][:80].replace("\n", " "))
        print("  C:", s["content_preview"][:60].replace("\n", " "))
    OUT.write_text(json.dumps(suspects, ensure_ascii=False, indent=2), encoding="utf-8")
    print(f"\nwrote {OUT} ({len(suspects)})")


if __name__ == "__main__":
    main()
