# -*- coding: utf-8 -*-
"""内容可信度分级 —— 产出 `assets/data/content_quality.json`。

## 为什么需要它

`tools/auto_fill_content.py` 曾为缺译文的诗词批量生成「完整但偏说明性」的译文/赏析/背景。
这些文本读起来像赏析，其实是同一套句式反复套用（例如「…善用风、雨、花等意象，情景相生，
是李贺笔下值得细读的一首」）。生成本身是有意的（脚本头写明不编造史实），
问题在于 **App 把它们和人工精校的赏析不加区分地展示** —— 用户翻到第 300 首时读到的是流水线套话。

所以这里把每条内容分成三级，交给 App 如实标注：

- `curated`  人工撰写或精校（三个数据源里的预置 70 首全部属于这一级）
- `generated` 脚本生成的说明性补充
- `missing`  缺失

## 判据

全部基于**可复现的文本特征**，不做主观判断，也不在此处修改原数据：

| 字段 | 判为 `generated` 的条件 |
| --- | --- |
| translation | 去掉标点后，译文是原文的子串（即"译文"就是原文某几句的复制） |
| appreciation | 命中模板句特征（见 `TEMPLATE_PHRASES` / `TEMPLATE_PATTERNS`） |
| background | 命中模板句特征 / 长度短于 `MIN_BACKGROUND` / 等于「作者+诗名」拼接 |

## 用法

    python tools/audit_content_quality.py           # 重新生成 JSON 并打印汇总
    python tools/audit_content_quality.py --check   # 只比对不写盘，不一致则退出码 1

放进 CI 或提交前跑 `--check`，可以防止「改了数据忘了刷新分级」这种静默漂移。
"""
from __future__ import annotations

import io
import json
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DATA = os.path.join(ROOT, "assets", "data")
OUT = os.path.join(DATA, "content_quality.json")

SOURCES = [
    ("preset", os.path.join(DATA, "poems.json")),
    ("xiaoxue", os.path.join(DATA, "packs", "xiaoxue.json")),
    ("tangshi", os.path.join(DATA, "packs", "tangshi.json")),
    ("songci", os.path.join(DATA, "packs", "songci.json")),
]

FIELDS = ["translation", "appreciation", "background"]

# 模板句特征（子串）。留空串会让判据失效，所以宁可长一点、具体一点。
TEMPLATE_PHRASES = [
    "值得细读的一首",
    "章法铺叙有序",
    "全篇围绕题意展开",
    "情景相生",
    "句式自由，气势流畅",
]
# 模板句特征（正则）
#
# ⚠️ 不要加 `以「.+?」为题`：模板文里确实有「此词以「夜游宫」为题，章法铺叙有序…」，
# 但人工精校的《锦瑟》背景里也写着「此诗以「锦瑟」为题（取首二字，亦近无题）…」。
# 实测这条正则单独贡献 0 个真阳性、1 个假阳性（把《锦瑟》误判成占位），
# 而它的真阳性全部已被下面的短语覆盖 —— 所以删掉，不做没有收益的风险。
TEMPLATE_PATTERNS = [
    re.compile(r"为.{1,8}的作品"),      # 《夜游宫》为贺铸的作品，题旨明确，结构完整。
]

# 短于此长度的背景基本是占位（如「黄庭坚归田乐引。」）
MIN_BACKGROUND = 24
# 短于此长度的赏析视为缺失
MIN_APPRECIATION = 30

_PUNCT = re.compile(r"[，。！？、；：,.!?;:\s「」『』（）()《》〈〉—…“”\"'’]")

# 繁→简映射（opencc 生成的 t2s_mapping.json，3751 对）。
# 扩充包的原文混用繁简（如「鬬鸡」「六鼇」），而占位译文是简体照抄 ——
# 不做归一的话，「译文=原文复制」会因繁简字形差异漏判成精校。
_T2S_PATH = os.path.join(DATA, "t2s_mapping.json")


def _load_t2s() -> dict:
    with io.open(_T2S_PATH, encoding="utf-8") as fh:
        return json.load(fh)


def _strip(text: str) -> str:
    return _PUNCT.sub("", text or "")


def _canon(text: str, t2s: dict) -> str:
    """去标点 + 逐字繁转简 —— 只用于「是否原文复制」的形态比较，不改数据。"""
    body = _strip(text)
    return "".join(t2s.get(ch, ch) for ch in body)


def _has_template(text: str) -> bool:
    if not text:
        return False
    if any(p in text for p in TEMPLATE_PHRASES):
        return True
    return any(p.search(text) for p in TEMPLATE_PATTERNS)


# 跨诗串包检测用的语料（build() 时填充）：id -> 归一后的原文
_CORPUS: dict[int, str] = {}
_T2S: dict = {}


def classify_translation(poem: dict) -> str:
    raw = (poem.get("translation") or "").strip()
    if not raw:
        return "missing"
    body = _canon(raw, _T2S)
    if not body:
        return "missing"
    pid = int(poem["id"])
    # ① 译文是**本诗**原文的复制（繁简归一后比较）
    own = _CORPUS.get(pid, "")
    if own and body in own:
        return "generated"
    # ② 译文是**另一首诗**原文的复制 —— 批量补写时按错行串包
    #    （例：贺铸《念彩云·夜游宫》拿到另一首《夜游宫》的「译文」）
    for other_id, other_body in _CORPUS.items():
        if other_id != pid and body in other_body:
            return "generated"
    return "curated"


def classify_appreciation(poem: dict) -> str:
    raw = (poem.get("appreciation") or "").strip()
    # 先看模板特征再看长度：有一条模板句只有 28 字（「古体/乐府句式自由，气势流畅，
    # 是张籍笔下值得细读的一首。」），按长度它会掉进 missing —— 那是**错的**，
    # 它明明是脚本生成的，只是短。长度只用来判断「有没有」。
    if _has_template(raw):
        return "generated"
    if len(raw) < MIN_APPRECIATION:
        return "missing"
    return "curated"


def classify_background(poem: dict) -> str:
    raw = (poem.get("background") or "").strip()
    if not raw:
        return "missing"
    if len(raw) < MIN_BACKGROUND:
        return "generated"
    if _has_template(raw):
        return "generated"
    # 「作者+诗名。」式的拼接（例如「黄庭坚归田乐引。」）
    joined = _strip(f"{poem.get('author') or ''}{poem.get('title') or ''}")
    if joined and _strip(raw) == joined:
        return "generated"
    return "curated"


CLASSIFIERS = {
    "translation": classify_translation,
    "appreciation": classify_appreciation,
    "background": classify_background,
}


def load_poems() -> list[tuple[str, dict]]:
    out: list[tuple[str, dict]] = []
    for name, path in SOURCES:
        with io.open(path, encoding="utf-8") as fh:
            raw = json.load(fh)
        poems = raw.get("poems", raw) if isinstance(raw, dict) else raw
        for poem in poems:
            out.append((name, poem))
    return out


def build() -> dict:
    global _T2S
    _T2S = _load_t2s()
    poems = load_poems()
    _CORPUS.clear()
    for _pack, poem in poems:
        _CORPUS[int(poem["id"])] = _canon(poem.get("content") or "", _T2S)
    buckets = {f: {"curated": [], "generated": [], "missing": []} for f in FIELDS}

    for _pack, poem in poems:
        pid = int(poem["id"])
        for field in FIELDS:
            buckets[field][CLASSIFIERS[field](poem)].append(pid)

    for field in FIELDS:
        for level in buckets[field]:
            buckets[field][level].sort()

    counts = {
        "total": len(poems),
        **{f: {lv: len(buckets[f][lv]) for lv in ("curated", "generated", "missing")}
           for f in FIELDS},
    }

    return {
        "version": 2,
        # 用数据文件的最后修改时间而非当前时间：同样的数据生成同样的文件，git 不会无谓变化
        "data_mtime": max(int(os.path.getmtime(p)) for _, p in SOURCES),
        "criteria": {
            "translation": "繁简归一去标点后，译文是本诗或另一首诗原文的子串",
            "appreciation": f"命中模板句特征或短于 {MIN_APPRECIATION} 字",
            "background": f"命中模板句特征、短于 {MIN_BACKGROUND} 字，或等于作者+诗名拼接",
            "template_phrases": TEMPLATE_PHRASES,
        },
        "counts": counts,
        "generated": {f: buckets[f]["generated"] for f in FIELDS},
        "missing": {f: buckets[f]["missing"] for f in FIELDS},
    }


def dump(payload: dict) -> str:
    return json.dumps(payload, ensure_ascii=False, indent=2, sort_keys=True) + "\n"


def main() -> int:
    payload = build()
    text = dump(payload)
    check = "--check" in sys.argv

    counts = payload["counts"]
    total = counts["total"]
    print(f"共 {total} 首")
    for field in FIELDS:
        c = counts[field]
        print(
            f"  {field:12s} 精校 {c['curated']:5d} "
            f"({c['curated'] / total:5.1%}) · 说明性补充 {c['generated']:5d} "
            f"({c['generated'] / total:5.1%}) · 缺失 {c['missing']}"
        )

    if check:
        if not os.path.exists(OUT):
            print("✗ 缺少 content_quality.json，请先跑一次不带 --check 的生成")
            return 1
        with io.open(OUT, encoding="utf-8") as fh:
            on_disk = fh.read()
        if on_disk != text:
            print("✗ content_quality.json 与当前数据不一致，请重新生成并提交")
            return 1
        print("✓ content_quality.json 与数据一致")
        return 0

    with io.open(OUT, "w", encoding="utf-8", newline="\n") as fh:
        fh.write(text)
    print(f"✓ 已写入 {os.path.relpath(OUT, ROOT)}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
