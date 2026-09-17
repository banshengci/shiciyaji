# -*- coding: utf-8 -*-
"""聚焦扩索引：补漏作者标签 + 朝代全量。"""
from __future__ import annotations

import json
import re
import time
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
CACHE = ROOT / "tools" / "gushici_cache"
INDEX_PATH = CACHE / "index.json"
AUTHOR_TAGS = CACHE / "author_tags.json"

UA = (
    "Mozilla/5.0 (Windows NT 10.0; Win64; x64) "
    "AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"
)
DELAY = 0.3


def http_get(url: str, timeout: int = 20) -> str:
    req = urllib.request.Request(
        url,
        headers={
            "User-Agent": UA,
            "Accept": "text/html,application/xhtml+xml,*/*;q=0.8",
            "Accept-Language": "zh-CN,zh;q=0.9",
            "Referer": "https://www.gushici.net/",
        },
    )
    with urllib.request.urlopen(req, timeout=timeout) as resp:
        return resp.read().decode("utf-8", errors="replace")


def clean(s: str) -> str:
    return re.sub(r"\s+", " ", re.sub(r"<[^>]+>", "", s or "")).strip()


def parse_poems(page_html: str) -> list[dict]:
    items = []
    for m in re.finditer(
        r'href="(/shici/(\d+)/(\d+)\.html)"[^>]*>\s*<b>(.*?)</b>[\s\S]*?'
        r'class="source">([\s\S]*?)</p>[\s\S]*?'
        r'class="gushici-box-text">([\s\S]*?)</div>',
        page_html,
    ):
        href, _a, _b, title_raw, source_raw, body_raw = m.groups()
        title = clean(title_raw)
        source = clean(source_raw)
        author = source.split("：", 1)[-1].strip() if "：" in source else source.split(":", 1)[-1].strip()
        body = clean(body_raw).replace(" ", "").replace("\n", "")
        items.append(
            {
                "url": "https://www.gushici.net" + href,
                "title": title,
                "author": author,
                "body_preview": body[:80],
            }
        )
    return items


def load_tags() -> dict[str, str]:
    return json.loads(AUTHOR_TAGS.read_text(encoding="utf-8")) if AUTHOR_TAGS.exists() else {}


def save_tags(tags: dict[str, str]) -> None:
    AUTHOR_TAGS.write_text(json.dumps(tags, ensure_ascii=False, indent=2), encoding="utf-8")


def merge_index(new_items: list[dict]) -> int:
    index = json.loads(INDEX_PATH.read_text(encoding="utf-8")) if INDEX_PATH.exists() else []
    seen = {it["url"] for it in index}
    added = 0
    for it in new_items:
        if it["url"] not in seen:
            seen.add(it["url"])
            index.append(it)
            added += 1
    INDEX_PATH.write_text(json.dumps(index, ensure_ascii=False, indent=2), encoding="utf-8")
    return added


def crawl_url(base: str, max_pages: int = 100) -> list[dict]:
    out = []
    for n in range(1, max_pages + 1):
        url = base if n == 1 else f"{base.rstrip('/')}/index_{n}.html"
        try:
            html = http_get(url)
        except Exception:
            if n == 1:
                return []
            break
        items = parse_poems(html)
        if not items:
            break
        out.extend(items)
        if n % 10 == 0:
            print(f"    page {n} total {len(out)}", flush=True)
        time.sleep(DELAY)
    return out


def missing_authors() -> list[str]:
    out = []
    for name in ("tangshi.json", "songci.json", "xiaoxue.json"):
        d = json.loads((ROOT / "assets" / "data" / "packs" / name).read_text(encoding="utf-8"))
        poems = d if isinstance(d, list) else d["poems"]
        for p in poems:
            if not (p.get("translation") or "").strip() and p.get("author"):
                out.append(p["author"])
    # 按出现次数
    from collections import Counter
    return [a for a, _ in Counter(out).most_common()]


def extract_author_tag_from_detail(url: str) -> tuple[str, str] | None:
    """从详情页抓 作者名 -> /t/.../ 链接。"""
    try:
        html = http_get(url)
    except Exception:
        return None
    time.sleep(DELAY)
    # <a href="/t/1/87/">杜甫</a>
    for m in re.finditer(r'href="(/t/\d+/\d+/)"[^>]*>\s*([^<]{2,8})\s*<', html):
        href, name = m.group(1), clean(m.group(2))
        if 2 <= len(name) <= 6:
            # 过滤朝代/标签
            if name in {"唐代", "宋代", "元代", "明代", "清代", "写景", "抒情", "爱国", "唐诗三百首", "宋词三百首"}:
                continue
            return name, "https://www.gushici.net" + href
    return None


def main() -> None:
    tags = load_tags()
    needed = missing_authors()
    print("needed", len(needed), "known tags", len(tags))

    # 1) 扫 169-230
    print("scan tags 169-230")
    for n in range(169, 231):
        url = f"https://www.gushici.net/t/1/{n}/"
        try:
            html = http_get(url)
        except Exception:
            time.sleep(DELAY)
            continue
        m = re.search(r"<title>(.*?)</title>", html, re.S)
        if m:
            t = clean(m.group(1))
            mm = re.match(r"(.+?)的诗词", t)
            if mm and 2 <= len(mm.group(1)) <= 6:
                name = mm.group(1)
                if name not in tags:
                    tags[name] = url
                    print(" new tag", name, url)
        time.sleep(DELAY)
    save_tags(tags)

    # 2) 从索引里找缺失作者的一首诗，去详情页反查标签
    index = json.loads(INDEX_PATH.read_text(encoding="utf-8")) if INDEX_PATH.exists() else []
    by_author: dict[str, str] = {}
    for it in index:
        a = it.get("author") or ""
        if a and a not in by_author:
            by_author[a] = it["url"]
    print("index authors", len(by_author))
    for author in needed:
        if author in tags:
            continue
        if author in by_author:
            got = extract_author_tag_from_detail(by_author[author])
            if got and got[0] == author:
                tags[author] = got[1]
                print(" found tag via detail", author, got[1])
                save_tags(tags)
            elif got:
                # 名字接近也收
                print(" detail other", got)

    # 3) 缺失作者全集
    for author in needed:
        url = tags.get(author)
        if not url:
            print("STILL NO TAG", author)
            continue
        print("CRAWL", author, url, flush=True)
        items = crawl_url(url)
        added = merge_index(items)
        print(f"  +{added}")

    # 4) 朝代兜底
    for dyn, label in [
        ("https://www.gushici.net/t/1/174/", "tang"),
        ("https://www.gushici.net/t/1/176/", "song"),
    ]:
        print("CRAWL dyn", label, flush=True)
        items = crawl_url(dyn, max_pages=60)
        added = merge_index(items)
        print(f"  +{added}")

    index = json.loads(INDEX_PATH.read_text(encoding="utf-8"))
    print("final index", len(index), "tags", len(tags))


if __name__ == "__main__":
    main()
