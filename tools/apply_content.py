# -*- coding: utf-8 -*-
"""把内容知识库同步应用到全部诗词数据文件。

处理四件事：
1. 填充/加厚作者简介（AUTHOR_BIOS）—— 仅在内容为空或明显更短时覆盖，避免退化
2. 加厚诗词赏析与创作背景（POEM_CONTENT_A/B）
3. 修正朝代归属错误（DYNASTY_FIX）
4. 修正诗词标题错字（TITLE_FIX）

用法：python tools/apply_content.py [--dry-run]
"""
import json
import os
import sys
import shutil
from datetime import datetime

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from content.author_bios import AUTHOR_BIOS, DYNASTY_FIX, TITLE_FIX
from content.poem_content_a import POEM_CONTENT_A
from content.poem_content_b import POEM_CONTENT_B
from content.poem_content_c import BACKGROUND_C
from content.poem_content_d import BACKGROUND_D

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DATA_DIR = os.path.join(ROOT, "assets", "data")

TARGETS = [
    "poems.json",
    "poems_v2.json",
    "pack_tangshi.json",
    "pack_songci.json",
    "pack_xiaoxue.json",
]

# 合并诗词内容库
POEM_CONTENT = {}
POEM_CONTENT.update(POEM_CONTENT_A)
POEM_CONTENT.update(POEM_CONTENT_B)

DRY_RUN = "--dry-run" in sys.argv


def text_len(v):
    return len(str(v).strip()) if v else 0


def ensure_dynasty(data, name):
    """确保朝代存在，返回其 id；不存在则新增。"""
    for d in data["dynasties"]:
        if d["name"] == name:
            return d["id"]
    new_id = max((d["id"] for d in data["dynasties"]), default=0) + 1
    data["dynasties"].append({
        "id": new_id,
        "name": name,
        "sort_order": new_id,
    })
    return new_id


def lookup_poem_content(title, author_name):
    """先按「标题||作者」精确查，再按标题查。"""
    if author_name:
        key = "{}||{}".format(title, author_name)
        if key in POEM_CONTENT:
            return POEM_CONTENT[key]
    return POEM_CONTENT.get(title)


def process(path):
    with open(path, encoding="utf-8") as f:
        data = json.load(f)

    authors = data.get("authors", [])
    poems = data.get("poems", [])
    stat = {"author": 0, "appreciation": 0, "background": 0,
            "dynasty": 0, "title": 0}

    # 1) 作者：朝代修正 + 简介填充/加厚
    for a in authors:
        name = a.get("name")
        info = AUTHOR_BIOS.get(name)
        if not info:
            continue
        bio, birth, death, dyn_name = info

        # 朝代归属修正
        if name in DYNASTY_FIX:
            want = DYNASTY_FIX[name]
            cur_id = a.get("dynasty_id")
            cur_name = next((d["name"] for d in data["dynasties"]
                             if d["id"] == cur_id), None)
            if cur_name != want:
                new_id = ensure_dynasty(data, want)
                a["dynasty_id"] = new_id
                stat["dynasty"] += 1

        # 生卒年（原数据为空才补）
        if birth and not a.get("birth_year"):
            a["birth_year"] = birth
        if death and not a.get("death_year"):
            a["death_year"] = death

        # 简介：为空或明显偏短时覆盖
        if text_len(bio) > text_len(a.get("bio")) + 20:
            a["bio"] = bio
            stat["author"] += 1

    # 2) 诗词：标题校正 + 赏析/背景加厚
    author_name = {a["id"]: a.get("name") for a in authors}
    for p in poems:
        title = p.get("title")

        if title in TITLE_FIX:
            p["title"] = TITLE_FIX[title]
            stat["title"] += 1
            title = p["title"]

        c = lookup_poem_content(title, author_name.get(p.get("author_id")))

        # 背景：A/B 批优先，C/D 批回退（C/D 覆盖 A/B 未收录的诗词，故不可因 c 为空而跳过）
        new_bg = c.get("background") if c else None
        if not new_bg:
            new_bg = BACKGROUND_C.get(title)
        if not new_bg:
            new_bg = BACKGROUND_D.get(title)
        if new_bg and text_len(new_bg) > text_len(p.get("background")) + 20:
            p["background"] = new_bg
            stat["background"] += 1

        # 赏析：仅 A/B 批提供
        new_app = c.get("appreciation") if c else None
        if new_app and text_len(new_app) > text_len(p.get("appreciation")) + 20:
            p["appreciation"] = new_app
            stat["appreciation"] += 1

    if not DRY_RUN:
        # 备份后写回
        bak = path + ".bak"
        if not os.path.exists(bak):
            shutil.copy2(path, bak)
        with open(path, "w", encoding="utf-8") as f:
            json.dump(data, f, ensure_ascii=False, indent=2)

    return stat, len(authors), len(poems)


def main():
    print("=" * 68)
    print("诗词内容完善 —— {}（dry-run={}）".format(
        datetime.now().strftime("%Y-%m-%d %H:%M:%S"), DRY_RUN))
    print("=" * 68)

    total = {"author": 0, "appreciation": 0, "background": 0,
             "dynasty": 0, "title": 0}

    for name in TARGETS:
        path = os.path.join(DATA_DIR, name)
        if not os.path.exists(path):
            print("  [skip] 不存在：{}".format(name))
            continue
        stat, na, np_ = process(path)
        print("\n[{}]  作者 {} 位 / 诗词 {} 首".format(name, na, np_))
        print("  作者简介补全/加厚 : {}".format(stat["author"]))
        print("  赏析加厚          : {}".format(stat["appreciation"]))
        print("  背景加厚          : {}".format(stat["background"]))
        print("  朝代修正          : {}".format(stat["dynasty"]))
        print("  标题校正          : {}".format(stat["title"]))
        for k in total:
            total[k] += stat[k]

    print("\n" + "-" * 68)
    print("合计：作者 {}, 赏析 {}, 背景 {}, 朝代 {}, 标题 {}".format(
        total["author"], total["appreciation"], total["background"],
        total["dynasty"], total["title"]))
    print("-" * 68)


if __name__ == "__main__":
    main()
