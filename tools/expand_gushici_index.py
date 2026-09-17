# -*- coding: utf-8 -*-
"""扩充 gushici 索引：按作者标签 /t/1/N/ 爬取全集。"""
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
DELAY = 0.35


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
    s = re.sub(r"<[^>]+>", "", s or "")
    s = re.sub(r"\s+", " ", s)
    return s.strip()


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


def discover_author_tags(start: int = 1, end: int = 220) -> dict[str, str]:
    """扫描 /t/1/N/，保存「作者名 -> 标签URL」。"""
    if AUTHOR_TAGS.exists():
        return json.loads(AUTHOR_TAGS.read_text(encoding="utf-8"))
    tags: dict[str, str] = {}
    for n in range(start, end + 1):
        url = f"https://www.gushici.net/t/1/{n}/"
        try:
            html = http_get(url)
        except Exception:
            time.sleep(DELAY)
            continue
        title_m = re.search(r"<title>(.*?)</title>", html, re.S)
        if not title_m:
            time.sleep(DELAY)
            continue
        t = clean(title_m.group(1))
        # 「李白的诗词全集、诗集_古诗词网」 or 「关于唐代的古诗_古诗词网」
        name = ""
        m = re.match(r"(.+?)的诗词", t)
        if m:
            name = m.group(1)
        if name and len(name) <= 6:
            tags[name] = url
            print(f"author tag {n}: {name}", flush=True)
        time.sleep(DELAY)
    AUTHOR_TAGS.write_text(json.dumps(tags, ensure_ascii=False, indent=2), encoding="utf-8")
    print(f"author tags {len(tags)}")
    return tags


def crawl_author(url: str, max_pages: int = 80) -> list[dict]:
    out = []
    for n in range(1, max_pages + 1):
        page_url = url if n == 1 else f"{url.rstrip('/')}/index_{n}.html"
        try:
            html = http_get(page_url)
        except Exception:
            if n == 1:
                return []
            break
        items = parse_poems(html)
        if not items:
            break
        out.extend(items)
        print(f"  page {n}: +{len(items)} total={len(out)}", flush=True)
        time.sleep(DELAY)
    return out


def merge_index(new_items: list[dict]) -> int:
    index = []
    if INDEX_PATH.exists():
        index = json.loads(INDEX_PATH.read_text(encoding="utf-8"))
    seen = {it["url"] for it in index}
    added = 0
    for it in new_items:
        if it["url"] not in seen:
            seen.add(it["url"])
            index.append(it)
            added += 1
    INDEX_PATH.write_text(json.dumps(index, ensure_ascii=False, indent=2), encoding="utf-8")
    return added


def main() -> None:
    # 1) 发现作者标签
    tags = discover_author_tags()
    # 2) 只爬 suspects 里出现的作者
    suspects = json.loads((ROOT / "tools" / "suspect_translations.json").read_text(encoding="utf-8"))
    needed = sorted({s["author"] for s in suspects if s.get("author")})
    print("needed authors", len(needed))
    for author in needed:
        url = tags.get(author)
        if not url:
            print(f"SKIP no tag: {author}")
            continue
        print(f"CRAWL {author} {url}", flush=True)
        items = crawl_author(url)
        added = merge_index(items)
        print(f"  added {added} for {author}", flush=True)
    index = json.loads(INDEX_PATH.read_text(encoding="utf-8"))
    print("index size", len(index))


if __name__ == "__main__":
    main()
