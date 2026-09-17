# -*- coding: utf-8 -*-
"""从 gushici.net（古诗词网）抓取译文，修复离线包坏译文。

站点特点：
- 详情页静态 HTML，含「译文及注释」
- 列表页 /shici/index_N.html 可分页，条目自带标题/作者/原文摘录
- 搜索为前端渲染，故用「列表索引 + 详情抽取」而非站内搜索

用法：
    python tools/fetch_gushici_translations.py --build-index
    python tools/fetch_gushici_translations.py --limit 20
    python tools/fetch_gushici_translations.py --apply
"""
from __future__ import annotations

import argparse
import html as html_lib
import json
import re
import time
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
PACKS = ROOT / "assets" / "data" / "packs"
CACHE = ROOT / "tools" / "gushici_cache"
INDEX_PATH = CACHE / "index.json"
SUSPECTS = ROOT / "tools" / "suspect_translations.json"
PATCH_OUT = ROOT / "tools" / "gushici_translation_patches.json"

UA = (
    "Mozilla/5.0 (Windows NT 10.0; Win64; x64) "
    "AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"
)
DELAY = 0.45

TAG_RE = re.compile(r"<[^>]+>")
WS_RE = re.compile(r"\s+")
PUNCT_RE = re.compile(r"[，。！？、；：,.!?;:\s「」『』（）()《》〈〉—…“”\"'’]")


def http_get(url: str, timeout: int = 25) -> str:
    req = urllib.request.Request(
        url,
        headers={
            "User-Agent": UA,
            "Accept": "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
            "Accept-Language": "zh-CN,zh;q=0.9,en;q=0.8",
            "Referer": "https://www.gushici.net/",
            "Connection": "keep-alive",
        },
    )
    with urllib.request.urlopen(req, timeout=timeout) as resp:
        raw = resp.read()
    return raw.decode("utf-8", errors="replace")


def clean_text(s: str) -> str:
    if not s:
        return ""
    s = html_lib.unescape(s)
    s = s.replace("</br>", "\n").replace("<br/>", "\n").replace("<br>", "\n")
    s = TAG_RE.sub("", s)
    return WS_RE.sub(" ", s).strip()


def strip_punct(s: str) -> str:
    return PUNCT_RE.sub("", s or "")


def norm(s: str) -> str:
    return re.sub(r"[\s·・]", "", clean_text(s or ""))


def content_overlap(a: str, b: str) -> float:
    sa, sb = set(strip_punct(a)), set(strip_punct(b))
    if not sa or not sb:
        return 0.0
    return len(sa & sb) / min(len(sa), len(sb))


def score_match(want_title: str, want_author: str, got_title: str, got_author: str) -> float:
    wt, gt = norm(want_title), norm(got_title)
    wa, ga = norm(want_author), norm(got_author)
    if not wt or not gt:
        return 0.0
    score = 0.0
    if wt == gt:
        score += 1.0
    elif wt in gt or gt in wt:
        score += 0.75
    else:
        wt2 = re.sub(r"其[一二三四五六七八九十0-9]+$", "", wt)
        gt2 = re.sub(r"其[一二三四五六七八九十0-9]+$", "", gt)
        if wt2 == gt2:
            score += 0.85
        elif wt2 and gt2 and (wt2 in gt2 or gt2 in wt2):
            score += 0.6
        # 词牌：去掉副题再比
        wt3 = re.sub(r"[·・].*$", "", wt)
        gt3 = re.sub(r"[·・].*$", "", gt)
        if wt3 and wt3 == gt3 and len(wt3) >= 2:
            score += 0.55
    if wa and ga:
        if wa == ga:
            score += 0.55
        elif wa in ga or ga in wa:
            score += 0.4
    return score


def parse_list_page(page_html: str, page_no: int) -> list[dict]:
    items: list[dict] = []
    # 条目块：href="/shici/xx/yy.html" ... <b>title</b> ... source 作者 ... 正文
    for m in re.finditer(
        r'href="(/shici/(\d+)/(\d+)\.html)"[^>]*>\s*<b>(.*?)</b>[\s\S]*?'
        r'class="source">([\s\S]*?)</p>[\s\S]*?'
        r'class="gushici-box-text">([\s\S]*?)</div>',
        page_html,
    ):
        href, _a, _b, title_raw, source_raw, body_raw = m.groups()
        title = clean_text(title_raw)
        source = clean_text(source_raw)
        # source 形如「唐代：杜甫」
        author = ""
        if "：" in source:
            author = source.split("：", 1)[-1].strip()
        elif ":" in source:
            author = source.split(":", 1)[-1].strip()
        body = clean_text(body_raw).replace(" ", "").replace("\n", "")
        url = "https://www.gushici.net" + href
        items.append(
            {
                "url": url,
                "title": title,
                "author": author,
                "body_preview": body[:80],
                "page": page_no,
            }
        )
    return items


def build_index(max_pages: int = 120) -> list[dict]:
    CACHE.mkdir(parents=True, exist_ok=True)
    if INDEX_PATH.exists():
        return json.loads(INDEX_PATH.read_text(encoding="utf-8"))
    index: list[dict] = []
    seen: set[str] = set()
    for n in range(1, max_pages + 1):
        if n == 1:
            url = "https://www.gushici.net/shici/"
        else:
            url = f"https://www.gushici.net/shici/index_{n}.html"
        try:
            page = http_get(url)
        except Exception as e:
            print(f"page {n} fail: {e}")
            if n > 5:
                break
            time.sleep(DELAY * 2)
            continue
        items = parse_list_page(page, n)
        if not items and n > 3:
            print(f"page {n} empty, stop")
            break
        for it in items:
            if it["url"] not in seen:
                seen.add(it["url"])
                index.append(it)
        print(f"page {n}: +{len(items)} total={len(index)}", flush=True)
        if n % 10 == 0:
            INDEX_PATH.write_text(json.dumps(index, ensure_ascii=False), encoding="utf-8")
        time.sleep(DELAY)
    INDEX_PATH.write_text(json.dumps(index, ensure_ascii=False, indent=2), encoding="utf-8")
    print(f"index done: {len(index)} -> {INDEX_PATH}")
    return index


def parse_detail(page_html: str) -> dict:
    """从详情页抽标题/作者/译文/赏析/背景。"""
    title = ""
    author = ""
    m = re.search(r"<title>(.*?)</title>", page_html, re.S)
    if m:
        t = clean_text(m.group(1))
        # 「八声甘州·对潇潇暮雨洒江天原文、翻译及赏析_柳永_古诗词网」
        t = re.sub(r"原文[、,].*赏析", "", t)
        t = re.sub(r"_?古诗词网.*$", "", t)
        parts = [p.strip() for p in t.split("_") if p.strip()]
        if parts:
            title = parts[0]
            if len(parts) > 1:
                author = parts[1]
        else:
            title = t
    # 页面里「唐代：杜甫」
    m_dyn = re.search(
        r"(?:先秦|两汉|魏晋|南北朝|隋|唐代|宋代|元代|明代|清代|近现代|当代)\s*[：:]\s*([^<\s]{1,12})",
        page_html,
    )
    if m_dyn:
        author = clean_text(m_dyn.group(1)) or author
    # 页面主标题
    m2 = re.search(r'class="(?:title|article-title|content-title)"[^>]*>\s*([^<]+)', page_html)
    if m2:
        title = clean_text(m2.group(1)) or title
    m3 = re.search(r'宋代\s*[：:]\s*([^<\s]+)|唐代\s*[：:]\s*([^<\s]+)|作者\s*[：:]\s*([^<\s]+)', page_html)
    if m3:
        author = next(g for g in m3.groups() if g) or author

    # 译文：优先取 <strong>译文</strong> 汇总块；否则拼 class="cb" 段
    translation = ""
    mm = re.search(
        r"<strong>\s*译文\s*</strong>\s*<br\s*/?>([\s\S]{10,4000}?)</p>",
        page_html,
        re.I,
    )
    if mm:
        translation = clean_text(mm.group(1))
    if not translation:
        parts = re.findall(r'class="cb"[^>]*>([\s\S]*?)</span>', page_html)
        if parts:
            translation = clean_text("".join(parts))
    if not translation:
        # 兜底：译文及注释 块里抽 cb
        block = re.search(r"译文及注释([\s\S]{50,8000})", page_html)
        if block:
            parts = re.findall(r'class="cb"[^>]*>([\s\S]*?)</span>', block.group(1))
            if parts:
                translation = clean_text("".join(parts))

    appreciation = ""
    mm = re.search(r"<strong>\s*赏析\s*</strong>\s*<br\s*/?>([\s\S]{20,3000}?)</p>", page_html, re.I)
    if mm:
        appreciation = clean_text(mm.group(1))[:600]
    else:
        mm = re.search(r'class="shici-fanyi"[\s\S]{0,200}?赏析[\s\S]{20,2000}', page_html)
        # 简单标题块
        mm = re.search(r"赏析\s*</span></h2>([\s\S]{20,3000}?)(?:<div\s+class=\"(?:tag|ckzl)|创作背景)", page_html)
        if mm:
            appreciation = clean_text(mm.group(1))[:600]

    background = ""
    mm = re.search(r"<strong>\s*创作背景\s*</strong>\s*<br\s*/?>([\s\S]{20,2000}?)</p>", page_html, re.I)
    if mm:
        background = clean_text(mm.group(1))[:500]
    else:
        mm = re.search(r"创作背景\s*</span></h2>([\s\S]{20,2000}?)(?:赏析|<div\s+class=\"(?:tag|ckzl)|参考资料)", page_html)
        if mm:
            background = clean_text(mm.group(1))[:500]

    body = ""
    mm = re.search(r'class="gushici-box-text">([\s\S]*?)</div>', page_html)
    if mm:
        body = clean_text(mm.group(1)).replace(" ", "").replace("\n", "")

    return {
        "title": title,
        "author": author,
        "translation": translation.strip(),
        "appreciation": appreciation.strip(),
        "background": background.strip(),
        "body": body,
    }


def fetch_detail(url: str) -> dict | None:
    CACHE.mkdir(parents=True, exist_ok=True)
    safe = re.sub(r"[^\w]+", "_", url)[-80:]
    cp = CACHE / f"detail_{safe}.json"
    if cp.exists():
        data = json.loads(cp.read_text(encoding="utf-8"))
        return data if data else None
    try:
        page = http_get(url)
    except Exception:
        return None
    info = parse_detail(page)
    info["url"] = url
    cp.write_text(json.dumps(info, ensure_ascii=False, indent=2), encoding="utf-8")
    return info


def load_suspects() -> list[dict]:
    return json.loads(SUSPECTS.read_text(encoding="utf-8"))


def load_pack_poems() -> dict[tuple[str, int], dict]:
    out: dict[tuple[str, int], dict] = {}
    for path in PACKS.glob("*.json"):
        data = json.loads(path.read_text(encoding="utf-8"))
        poems = data if isinstance(data, list) else data.get("poems", data.get("items", []))
        for p in poems:
            out[(path.name, int(p["id"]))] = p
    return out


def find_candidates(index: list[dict], title: str, author: str, content: str) -> list[dict]:
    scored: list[tuple[float, dict]] = []
    content_head = strip_punct(content or "")[:20]
    for it in index:
        sc = score_match(title, author, it.get("title") or "", it.get("author") or "")
        # 用列表页正文预览辅助
        if content_head and it.get("body_preview"):
            ov = content_overlap(content_head, it["body_preview"])
            if ov >= 0.6:
                sc += 0.4
            elif ov >= 0.4:
                sc += 0.15
        if sc >= 0.9:
            scored.append((sc, it))
    scored.sort(key=lambda x: -x[0])
    return [it for _, it in scored[:5]]


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--build-index", action="store_true")
    ap.add_argument("--max-pages", type=int, default=120)
    ap.add_argument("--limit", type=int, default=0)
    ap.add_argument("--offset", type=int, default=0)
    ap.add_argument("--delay", type=float, default=DELAY)
    ap.add_argument("--apply", action="store_true")
    args = ap.parse_args()

    if args.build_index:
        build_index(args.max_pages)
        return

    index = json.loads(INDEX_PATH.read_text(encoding="utf-8")) if INDEX_PATH.exists() else []
    if not index:
        print("index empty, run --build-index first")
        return
    print(f"index size {len(index)}")

    suspects = load_suspects()
    poems_index = load_pack_poems()
    if args.offset:
        suspects = suspects[args.offset :]
    if args.limit:
        suspects = suspects[: args.limit]

    patches: list[dict] = []
    if PATCH_OUT.exists():
        try:
            patches = json.loads(PATCH_OUT.read_text(encoding="utf-8"))
        except json.JSONDecodeError:
            patches = []
    done = {(p["pack"], int(p["id"])) for p in patches}
    stats = {"ok": 0, "no_match": 0, "no_trans": 0, "body_mismatch": 0, "already": 0, "skip": 0}

    for i, s in enumerate(suspects, 1):
        pack, pid = s["pack"], int(s["id"])
        if (pack, pid) in done:
            stats["already"] += 1
            continue
        poem = poems_index.get((pack, pid))
        if not poem:
            stats["skip"] += 1
            continue
        title, author = s["title"], s["author"]
        content = poem.get("content") or ""
        cands = find_candidates(index, title, author, content)
        print(f"[{i}/{len(suspects)}] {pack} #{pid} {title}/{author} cands={len(cands)}", flush=True)

        best = None
        best_sc = 0.0
        best_info = None
        for c in cands[:3]:
            info = fetch_detail(c["url"])
            time.sleep(args.delay)
            if not info:
                continue
            sc = score_match(title, author, info.get("title") or c["title"], info.get("author") or c["author"])
            if sc > best_sc:
                best_sc = sc
                best = c
                best_info = info
            if best_sc >= 1.5:
                break

        if not best_info or best_sc < 1.25:
            print(f"  weak/no match sc={best_sc:.2f}")
            stats["no_match"] += 1
            patches.append(
                {
                    "pack": pack,
                    "id": pid,
                    "title": title,
                    "author": author,
                    "status": "no_match",
                    "match_score": best_sc,
                    "got": (best or {}).get("title"),
                }
            )
            continue

        got_body = best_info.get("body") or best.get("body_preview") or ""
        if got_body and content:
            ov = content_overlap(content, got_body)
            if ov < 0.5:
                print(f"  body mismatch ov={ov:.2f} got={best_info.get('title')}")
                stats["body_mismatch"] += 1
                patches.append(
                    {
                        "pack": pack,
                        "id": pid,
                        "title": title,
                        "author": author,
                        "status": "body_mismatch",
                        "body_overlap": ov,
                    }
                )
                continue

        trans = best_info.get("translation") or ""
        # 翻译不能又是原文
        if trans and content_overlap(trans, content) > 0.85 and len(strip_punct(trans)) < len(strip_punct(content)) * 1.2:
            # 可能是原文复述，检查现代汉语密度
            modern_hits = sum(trans.count(w) for w in ["的", "了", "着", "这", "那", "我", "你", "他"])
            if modern_hits / max(len(strip_punct(trans)), 1) < 0.03:
                print("  translation looks like original")
                stats["no_trans"] += 1
                patches.append(
                    {
                        "pack": pack,
                        "id": pid,
                        "title": title,
                        "author": author,
                        "status": "trans_is_original",
                    }
                )
                continue

        if len(strip_punct(trans)) < 12:
            print("  translation too short")
            stats["no_trans"] += 1
            patches.append(
                {
                    "pack": pack,
                    "id": pid,
                    "title": title,
                    "author": author,
                    "status": "no_trans",
                }
            )
            continue

        patch = {
            "pack": pack,
            "id": pid,
            "title": title,
            "author": author,
            "status": "ok",
            "new_translation": trans,
            "new_appreciation": best_info.get("appreciation") or None,
            "new_background": best_info.get("background") or None,
            "source": "gushici.net",
            "url": best_info.get("url") or best.get("url"),
            "match_score": best_sc,
        }
        patches.append(patch)
        stats["ok"] += 1
        print(f"  OK sc={best_sc:.2f} trans_len={len(trans)}")
        print(f"  -> {trans[:70]}")

        if i % 10 == 0:
            PATCH_OUT.write_text(json.dumps(patches, ensure_ascii=False, indent=2), encoding="utf-8")

    PATCH_OUT.write_text(json.dumps(patches, ensure_ascii=False, indent=2), encoding="utf-8")
    print("stats", stats)
    print(f"patches {len(patches)} -> {PATCH_OUT}")

    if args.apply:
        apply_patches([p for p in patches if p.get("status") == "ok"])


def apply_patches(patches: list[dict]) -> None:
    by_pack: dict[str, list[dict]] = {}
    for p in patches:
        by_pack.setdefault(p["pack"], []).append(p)
    for pack, items in by_pack.items():
        path = PACKS / pack
        data = json.loads(path.read_text(encoding="utf-8"))
        poems = data if isinstance(data, list) else data.get("poems", data.get("items", []))
        index = {int(p["id"]): p for p in poems}
        hit = 0
        for it in items:
            p = index.get(int(it["id"]))
            if not p:
                continue
            p["translation"] = it["new_translation"]
            if it.get("new_appreciation"):
                old_a = (p.get("appreciation") or "").strip()
                if len(old_a) < 30 or "值得细读" in old_a or "章法铺叙有序" in old_a:
                    p["appreciation"] = it["new_appreciation"]
            if it.get("new_background"):
                old_b = (p.get("background") or "").strip()
                if len(old_b) < 24:
                    p["background"] = it["new_background"]
            hit += 1
        path.write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
        print(f"applied {hit} -> {path}")


if __name__ == "__main__":
    main()
