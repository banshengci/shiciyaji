# -*- coding: utf-8 -*-
"""把内容知识库合并应用到 assets/data/packs/*.json。

用法：
    python tools/apply_bulk_content.py
"""
from __future__ import annotations

import json
import os
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
TOOLS = os.path.join(ROOT, "tools")
DATA = os.path.join(ROOT, "assets", "data")
sys.path.insert(0, TOOLS)
sys.path.insert(0, os.path.join(TOOLS, "content"))


def load_all_content() -> dict:
    lib: dict = {}

    def merge(d: dict):
        for k, v in (d or {}).items():
            if "||" in k:
                base = k
            else:
                base = k
            entry = lib.setdefault(base, {})
            for field in ("translation", "appreciation", "background"):
                if v.get(field) and not entry.get(field):
                    entry[field] = v[field]
            # 也存无作者的 title 键，便于标题匹配
            title = v.get("title") or (k.split("||")[0] if "||" in k else k)
            t_entry = lib.setdefault(title, {})
            for field in ("translation", "appreciation", "background"):
                if v.get(field) and not t_entry.get(field):
                    t_entry[field] = v[field]

    # 1) 批量库
    try:
        from poem_content_bulk_1 import POEM_CONTENT as B1
        merge(B1)
        print("bulk_1", len(B1))
    except Exception as e:
        print("bulk_1 fail", e)
    try:
        import poem_content_bulk_2  # noqa: F401
        import poem_content_bulk_3  # noqa: F401
        import poem_content_bulk_4  # noqa: F401
        import poem_content_bulk_5  # noqa: F401
        from poem_content_bulk_1 import POEM_CONTENT as BALL
        merge(BALL)
        print("bulk_1+2+3+4+5", len(BALL))
    except Exception as e:
        print("bulk fail", e)

    # 2) fill_poem_content
    try:
        from fill_poem_content import CONTENT as FILL
        for title, c in FILL.items():
            if "||" in title:
                continue
            merge({title: c})
        print("fill_poem_content", len(FILL))
    except Exception as e:
        print("fill fail", e)

    # 3) A/B 赏析背景
    try:
        from content.poem_content_a import POEM_CONTENT_A
        from content.poem_content_b import POEM_CONTENT_B
        for src in (POEM_CONTENT_A, POEM_CONTENT_B):
            merge(src)
        print("A+B", len(POEM_CONTENT_A) + len(POEM_CONTENT_B))
    except Exception as e:
        print("A+B fail", e)

    # 4) 预置 poems.json
    with open(os.path.join(DATA, "poems.json"), encoding="utf-8") as f:
        pre = json.load(f)
    auth = {a["id"]: a["name"] for a in pre["authors"]}
    for p in pre["poems"]:
        name = auth.get(p.get("author_id"), "")
        merge({p["title"]: p})
        if name:
            merge({"{}||{}".format(p["title"], name): p})
    print("poems.json", len(pre["poems"]))

    # 5) 精选 pack_*.json
    for key in ("tangshi", "songci", "xiaoxue"):
        path = os.path.join(DATA, "pack_{}.json".format(key))
        if not os.path.exists(path):
            continue
        with open(path, encoding="utf-8") as f:
            d = json.load(f)
        a2 = {a["id"]: a["name"] for a in d.get("authors", [])}
        for p in d.get("poems", []):
            name = a2.get(p.get("author_id"), "")
            merge({p["title"]: p})
            if name:
                merge({"{}||{}".format(p["title"], name): p})
        print("pack_" + key, len(d.get("poems", [])))

    print("merged lib keys", len(lib))
    return lib


def apply_to_packs(lib: dict) -> None:
    total_filled = 0
    for key in ("xiaoxue", "tangshi", "songci"):
        path = os.path.join(DATA, "packs", "{}.json".format(key))
        with open(path, encoding="utf-8") as f:
            pack = json.load(f)
        def _is_auto(v: str) -> bool:
            v = (v or "").strip()
            if not v:
                return True
            if v.startswith("全篇大意") or v.startswith("【意译】") or v.startswith("【串讲】"):
                return True
            if "作者生平与具体创作年月" in v:
                return True
            return False

        prefixes = (
            "鼓吹曲辞 ",
            "横吹曲辞 ",
            "相和歌辞 ",
            "杂曲歌辞 ",
            "琴曲歌辞 ",
            "杂歌谣辞 ",
            "舞曲歌辞 ",
            "清商曲辞 ",
            "近代曲辞 ",
            "郊庙歌辞 ",
            "燕射歌辞 ",
        )

        def _lookup(title: str, author: str):
            c = lib.get("{}||{}".format(title, author)) or lib.get(title)
            if c and (c.get("translation") or "").strip():
                return c
            t = title
            for pre in prefixes:
                if t.startswith(pre):
                    t2 = t[len(pre):].strip()
                    c = lib.get("{}||{}".format(t2, author)) or lib.get(t2)
                    if c and (c.get("translation") or "").strip():
                        return c
            # 词牌：取 · 前部分
            if "·" in title:
                t2 = title.split("·")[0].strip()
                c = lib.get("{}||{}".format(t2, author)) or lib.get(t2)
                if c and (c.get("translation") or "").strip():
                    return c
            return None

        filled = 0
        for p in pack["poems"]:
            c = _lookup(p["title"], p["author"])
            if not c:
                continue
            changed = False
            for field in ("translation", "appreciation", "background"):
                cur = (p.get(field) or "").strip()
                new = (c.get(field) or "").strip()
                if not new:
                    continue
                if _is_auto(cur):
                    p[field] = new
                    changed = True
            if changed:
                filled += 1
        # 压缩写回
        with open(path, "w", encoding="utf-8") as f:
            json.dump(pack, f, ensure_ascii=False, separators=(",", ":"))
        with_t = sum(1 for p in pack["poems"] if p.get("translation"))
        print(
            "[{}] filled={} with_T={}/{} size={}KB".format(
                key,
                filled,
                with_t,
                len(pack["poems"]),
                os.path.getsize(path) // 1024,
            )
        )
        total_filled += filled
    print("total newly filled", total_filled)


def main():
    lib = load_all_content()
    apply_to_packs(lib)
    # 统计
    grand = 0
    with_t = 0
    for key in ("xiaoxue", "tangshi", "songci"):
        with open(os.path.join(DATA, "packs", key + ".json"), encoding="utf-8") as f:
            pack = json.load(f)
        grand += len(pack["poems"])
        with_t += sum(1 for p in pack["poems"] if p.get("translation"))
    print("TOTAL poems={} with_translation={} ({:.0f}%)".format(
        grand, with_t, 100 * with_t / max(grand, 1)))


if __name__ == "__main__":
    main()
