# -*- coding: utf-8 -*-
"""（已由 expand_offline_packs.py 取代）重建三个离线包为「内容齐全的名篇精选」。

说明：本脚本只从 pack_*.json 精选库取材，规模较小（约 74/51/19）。
当前默认请使用：

    python tools/expand_offline_packs.py

该脚本会从 chinese-poetry 源数据扩充到约 600/500/150 首，并保留精选译文赏析。
"""
import json
import os
import shutil

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DATA = os.path.join(ROOT, "assets", "data")

# id 区间（与 database_helper.importPack/uninstallPack 的 switch 一致）
RANGES = {
    "xiaoxue": 10000,
    "tangshi": 20000,
    "songci": 30000,
}

PACK_META = {
    "tangshi": {
        "pack_name": "tangshi",
        "description": "唐诗名篇精粹：不与预置重复的经典唐诗，全部含白话译文、赏析与创作背景。",
        "version": "2",
        "source": "chinese-poetry（MIT）· 诗词雅集精编",
    },
    "songci": {
        "pack_name": "songci",
        "description": "宋词名篇精粹：豪放婉约大家经典词作，全部含白话译文、赏析与创作背景。",
        "version": "2",
        "source": "chinese-poetry（MIT）· 诗词雅集精编",
    },
    "xiaoxue": {
        "pack_name": "xiaoxue",
        "description": "小学补充篇目：教材常见而预置未收录的古诗，全部含白话译文、赏析与创作背景。",
        "version": "2",
        "source": "chinese-poetry（MIT）· 诗词雅集精编",
    },
}


def load_prebuilt():
    """预置 poems.json：诗词 (title, author_name) 集合 + authors 名表。"""
    with open(os.path.join(DATA, "poems.json"), encoding="utf-8") as f:
        pre = json.load(f)
    auth = {a["id"]: a["name"] for a in pre["authors"]}
    titles = {(p["title"], auth.get(p["author_id"])) for p in pre["poems"]}
    return titles


def build_one(pack_key, pre_titles):
    """从 pack_{key}.json 生成新 packs/{key}.json，返回 (源数, 输出数, 跳过数)。"""
    src_path = os.path.join(DATA, "pack_{}.json".format(pack_key))
    with open(src_path, encoding="utf-8") as f:
        d = json.load(f)
    auth = {a["id"]: a["name"] for a in d["authors"]}

    out_poems = []
    skip = 0
    for p in d["poems"]:
        author_name = auth.get(p.get("author_id"), "佚名")
        key = (p["title"], author_name)
        if key in pre_titles:
            skip += 1  # 与预置重合：导入会致 DB 重复同名诗，剔除
            continue
        out_poems.append({
            "id": None,  # 占位，下面连续编号
            "title": p["title"],
            "content": p.get("content", ""),
            "author": author_name,
            "dynasty_id": p.get("dynasty_id"),
            "type": p.get("type"),
            "sort_order": len(out_poems) + 1,
            "source": p.get("source", ""),
            "category_ids": p.get("category_ids", []),
            "translation": p.get("translation", ""),
            "appreciation": p.get("appreciation", ""),
            "background": p.get("background", ""),
            "notes": p.get("notes", ""),
        })

    start = RANGES[pack_key]
    for i, pm in enumerate(out_poems):
        pm["id"] = start + i + 1

    meta = dict(PACK_META[pack_key])
    meta["count"] = len(out_poems)
    pack = dict(meta)
    pack["poems"] = out_poems

    # 备份旧档
    bak_dir = os.path.join(ROOT, "build", "packs_backup")
    os.makedirs(bak_dir, exist_ok=True)
    out_path = os.path.join(DATA, "packs", "{}.json".format(pack_key))
    if os.path.exists(out_path):
        shutil.copy2(out_path, os.path.join(bak_dir, "{}.json".format(pack_key)))

    with open(out_path, "w", encoding="utf-8") as f:
        json.dump(pack, f, ensure_ascii=False, indent=1)
    return len(d["poems"]), len(out_poems), skip


def main():
    pre_titles = load_prebuilt()
    total = 0
    print("重建离线包为名篇精选（剔除与预置重合）：")
    for key in ["tangshi", "songci", "xiaoxue"]:
        src_n, out_n, skip = build_one(key, pre_titles)
        total += out_n
        print("  [{}] 源 {} 首 → 输出 {} 首（剔除重合 {} 首）".format(
            key, src_n, out_n, skip))
    print("  合计新增可用名篇 {} 首".format(total))
    print("备份旧包至 build/packs_backup/")


if __name__ == "__main__":
    main()
