# -*- coding: utf-8 -*-
"""按作者批次应用精写内容到 packs。

用法：
    python tools/apply_precise_batch.py <author_name>
    python tools/apply_precise_batch.py --list-authors
    python tools/apply_precise_batch.py --stats
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


def load_precise_lib() -> dict:
    from poem_content_bulk_1 import POEM_CONTENT
    # 触发 bulk_2/3/4 注册
    import poem_content_bulk_2  # noqa: F401
    import poem_content_bulk_3  # noqa: F401
    import poem_content_bulk_4  # noqa: F401
    import poem_content_bulk_5  # noqa: F401
    import poem_content_bulk_5_variants  # noqa: F401
    import poem_content_bulk_6  # noqa: F401
    import poem_content_bulk_7  # noqa: F401
    import poem_content_bulk_8  # noqa: F401
    import poem_content_bulk_9  # noqa: F401
    import poem_content_bulk_10  # noqa: F401
    import poem_content_bulk_10b  # noqa: F401
    import poem_content_bulk_11  # noqa: F401
    import poem_content_bulk_11b  # noqa: F401
    import poem_content_bulk_12  # noqa: F401
    import poem_content_bulk_12b  # noqa: F401
    import poem_content_bulk_13  # noqa: F401
    import poem_content_bulk_13b  # noqa: F401
    import poem_content_bulk_14  # noqa: F401
    import poem_content_bulk_14b  # noqa: F401
    import poem_content_bulk_15  # noqa: F401
    import poem_content_bulk_16  # noqa: F401
    import poem_content_bulk_17  # noqa: F401
    import poem_content_bulk_18  # noqa: F401
    import poem_content_bulk_19  # noqa: F401
    import poem_content_bulk_20  # noqa: F401
    import poem_content_bulk_21  # noqa: F401
    import poem_content_bulk_22  # noqa: F401
    import poem_content_bulk_23  # noqa: F401
    import poem_content_bulk_24  # noqa: F401
    import poem_content_bulk_25  # noqa: F401
    return POEM_CONTENT


def is_auto(v: str) -> bool:
    v = (v or "").strip()
    return (
        not v
        or v.startswith("【串讲】")
        or v.startswith("全篇大意")
        or v.startswith("【意译】")
        or "作者生平与具体创作年月" in v
    )


def apply_author(author: str) -> None:
    lib = load_precise_lib()
    total = 0
    for key in ("xiaoxue", "tangshi", "songci"):
        path = os.path.join(DATA, "packs", key + ".json")
        with open(path, encoding="utf-8") as f:
            pack = json.load(f)
        n = 0
        for p in pack["poems"]:
            if p["author"] != author:
                continue
            c = lib.get("{}||{}".format(p["title"], author)) or lib.get(p["title"])
            if not c or is_auto(c.get("translation") or ""):
                continue
            changed = False
            for field in ("translation", "appreciation", "background"):
                new = (c.get(field) or "").strip()
                if new and is_auto(p.get(field) or ""):
                    p[field] = new
                    changed = True
            if changed:
                n += 1
        if n:
            with open(path, "w", encoding="utf-8") as f:
                json.dump(pack, f, ensure_ascii=False, separators=(",", ":"))
        auto_left = sum(
            1
            for p in pack["poems"]
            if p["author"] == author
            and is_auto(p.get("translation") or "")
        )
        print("[{}] {} 精写应用 {}，该作者仍待精写 {}".format(key, author, n, auto_left))
        total += n
    print("合计应用", total)


def stats() -> None:
    auto_by = {}
    for key in ("xiaoxue", "tangshi", "songci"):
        with open(os.path.join(DATA, "packs", key + ".json"), encoding="utf-8") as f:
            pack = json.load(f)
        for p in pack["poems"]:
            if is_auto(p.get("translation") or ""):
                auto_by[p["author"]] = auto_by.get(p["author"], 0) + 1
    total = sum(auto_by.values())
    print("待精写合计", total, "作者", len(auto_by))
    for a, n in sorted(auto_by.items(), key=lambda x: -x[1])[:30]:
        print("  {} {}".format(a, n))


def main():
    if len(sys.argv) < 2:
        print(__doc__)
        stats()
        return
    if sys.argv[1] == "--stats":
        stats()
        return
    apply_author(sys.argv[1])


if __name__ == "__main__":
    main()
