# -*- coding: utf-8 -*-
"""从百度汉语抓取译文，回写离线包中「译文=原文/截取原文」的硬伤。

数据源：hanyu.baidu.com（免费诗词站点，页面内嵌 JSON，含 means/译文、shangxi、explain）
匹配：按标题搜索 → 标题+作者精确/近精确匹配 → 取 means 字段作为译文。

用法：
    python tools/fetch_baidu_translations.py --dry-run
    python tools/fetch_baidu_translations.py --limit 5
    python tools/fetch_baidu_translations.py
    python tools/fetch_baidu_translations.py --apply
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
CACHE = ROOT / "tools" / "baidu_hanyu_cache"
SUSPECTS = ROOT / "tools" / "suspect_translations.json"
PATCH_OUT = ROOT / "tools" / "baidu_translation_patches.json"

UA = (
    "Mozilla/5.0 (Windows NT 10.0; Win64; x64) "
    "AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"
)

# 请求间隔，避免给站点压力
DELAY_SEC = 1.2

RET_RE = re.compile(r'ret_array":(\[.*?\]),"extra"', re.S)
TAG_RE = re.compile(r"<[^>]+>")
WS_RE = re.compile(r"\s+")


def http_get(url: str, timeout: int = 25) -> str:
    req = urllib.request.Request(
        url,
        headers={
            "User-Agent": UA,
            "Accept": "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
            "Accept-Language": "zh-CN,zh;q=0.9,en;q=0.8",
            "Referer": "https://hanyu.baidu.com/",
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
    s = WS_RE.sub(" ", s).strip()
    return s


def norm_title(t: str) -> str:
    t = clean_text(t or "")
    # 去掉「·其一」等后缀的差异处理放在匹配里
    return re.sub(r"[\s·・]", "", t)


def norm_author(a: str) -> str:
    a = clean_text(a or "")
    a = re.sub(r"(唐|宋|元|明|清|汉|魏|晋|南北朝|五代|金)", "", a)
    return re.sub(r"[\s（）()]", "", a)


def parse_ret_array(page_html: str) -> list:
    m = RET_RE.search(page_html)
    if not m:
        return []
    try:
        return json.loads(m.group(1))
    except json.JSONDecodeError:
        return []


def extract_means(item: dict) -> str:
    means = item.get("means") or []
    parts: list[str] = []
    if isinstance(means, list):
        for x in means:
            if isinstance(x, str) and x.strip():
                parts.append(clean_text(x))
            elif isinstance(x, dict):
                t = clean_text(str(x.get("text") or x.get("@value") or ""))
                if t:
                    parts.append(t)
    elif isinstance(means, str):
        parts.append(clean_text(means))
    # 若 means 空，尝试拼 poemlines.translate
    if not parts:
        for pl in item.get("poemlines") or []:
            tr = clean_text(str(pl.get("translate") or ""))
            if tr:
                parts.append(tr)
    return "\n".join(p for p in parts if p).strip()


def extract_body(item: dict) -> str:
    body = item.get("body") or ""
    if isinstance(body, list):
        body = body[0] if body else ""
    body = clean_text(str(body))
    return body.replace(" ", "").replace("\n", "")


def content_overlap(a: str, b: str) -> float:
    sa, sb = set(re.sub(r"\s+", "", a or "")), set(re.sub(r"\s+", "", b or ""))
    if not sa or not sb:
        return 0.0
    return len(sa & sb) / min(len(sa), len(sb))


def extract_title_author(item: dict) -> tuple[str, str]:
    name = item.get("display_name") or item.get("baike_name") or ""
    if isinstance(name, list):
        name = name[0] if name else ""
    author = ""
    auths = item.get("literature_author") or []
    if auths and isinstance(auths[0], dict):
        author = auths[0].get("basic_name_chs") or auths[0].get("display_name") or ""
        if isinstance(author, list):
            author = author[0] if author else ""
    return clean_text(str(name)), clean_text(str(author))


def cache_path(key: str) -> Path:
    safe = re.sub(r"[^\w一-鿿-]+", "_", key)[:80]
    return CACHE / f"{safe}.json"


def search_queries(title: str, author: str, content: str = "") -> list[str]:
    """标题清洗后生成多组搜索词，提高召回。"""
    t = clean_text(title)
    variants = [t]
    # 「鼓吹曲辞 君马黄」→「君马黄」
    if " " in t:
        parts = [p for p in re.split(r"[\s　]+", t) if p]
        if len(parts) >= 2:
            variants.append(parts[-1])
            variants.append(parts[-1] + " " + author)
    # 「从军行七首·其四」→「从军行」
    base = re.sub(r"[·・].*$", "", t).strip()
    if base and base not in variants:
        variants.append(base)
    # 去掉「其N」
    base2 = re.sub(r"其[一二三四五六七八九十0-9]+$", "", base).strip()
    if base2 and base2 not in variants:
        variants.append(base2)
    if author and t:
        variants.append(f"{t} {author}")
    # 首句检索（冷门乐府常用）
    if content:
        first = re.split(r"[\n。！？；]", clean_text(content))[0].strip()
        if len(first) >= 4:
            variants.append(first[:12])
            variants.append(f"{first[:10]} {author}")
    # 去重保序
    out: list[str] = []
    for v in variants:
        v = v.strip()
        if v and v not in out:
            out.append(v)
    return out[:5]


def search_baidu(title: str, author: str, content: str = "") -> list[dict]:
    """返回候选 [{sid, title?, author?}]"""
    cands: list[dict] = []
    for q in search_queries(title, author, content):
        key = f"search::{q}"
        cp = cache_path(key)
        if cp.exists():
            page_cands = json.loads(cp.read_text(encoding="utf-8"))
        else:
            url = f"https://hanyu.baidu.com/s?wd={urllib.parse.quote(q)}&from=poem"
            page = http_get(url)
            page_cands = []
            for m in re.finditer(r"shici/detail\?pid=([a-f0-9]{16,})", page):
                sid = m.group(1)
                if not any(c["sid"] == sid for c in page_cands):
                    page_cands.append({"sid": sid})
            for m in re.finditer(
                r'\{"sid":"([a-f0-9]{16,})","name":"((?:\\u[0-9a-fA-F]{4}|\\.|[^"\\])*)","author":"((?:\\u[0-9a-fA-F]{4}|\\.|[^"\\])*)"',
                page,
            ):
                sid = m.group(1)
                try:
                    name = json.loads(f'"{m.group(2)}"')
                    author_name = json.loads(f'"{m.group(3)}"')
                except json.JSONDecodeError:
                    name, author_name = m.group(2), m.group(3)
                if not any(c["sid"] == sid for c in page_cands):
                    page_cands.append(
                        {
                            "sid": sid,
                            "title": clean_text(name),
                            "author": clean_text(author_name),
                        }
                    )
            cp.parent.mkdir(parents=True, exist_ok=True)
            cp.write_text(json.dumps(page_cands, ensure_ascii=False, indent=2), encoding="utf-8")
            time.sleep(0.3)
        for c in page_cands:
            if not any(x["sid"] == c["sid"] for x in cands):
                cands.append(c)
    return cands


def fetch_detail(sid: str, allow_network: bool = True) -> dict | None:
    cp = cache_path(f"detail::{sid}")
    if cp.exists():
        data = json.loads(cp.read_text(encoding="utf-8"))
        return data if data else None
    if not allow_network:
        return None
    url = f"https://hanyu.baidu.com/shici/detail?pid={sid}"
    try:
        page = http_get(url)
    except (urllib.error.URLError, TimeoutError, OSError):
        return None
    items = parse_ret_array(page)
    if not items:
        # 缓存空结果，避免反复打
        cp.parent.mkdir(parents=True, exist_ok=True)
        cp.write_text("{}", encoding="utf-8")
        return None
    item = items[0]
    slim = {
        "sid": sid,
        "means": extract_means(item),
        "title": extract_title_author(item)[0],
        "author": extract_title_author(item)[1],
        "body": extract_body(item),
        "shangxi": clean_text(((item.get("shangxi") or [{}])[0]).get("text") or ""),
        "explain": clean_text(((item.get("explain") or [{}])[0]).get("text") or ""),
    }
    cp.parent.mkdir(parents=True, exist_ok=True)
    cp.write_text(json.dumps(slim, ensure_ascii=False, indent=2), encoding="utf-8")
    return slim


def score_match(want_title: str, want_author: str, got_title: str, got_author: str) -> float:
    wt, gt = norm_title(want_title), norm_title(got_title)
    wa, ga = norm_author(want_author), norm_author(got_author)
    if not wt or not gt:
        return 0.0
    score = 0.0
    if wt == gt:
        score += 1.0
    elif wt in gt or gt in wt:
        score += 0.7
    else:
        # 去掉「其一」等
        wt2 = re.sub(r"其[一二三四五六七八九十]+$", "", wt)
        gt2 = re.sub(r"其[一二三四五六七八九十]+$", "", gt)
        if wt2 == gt2:
            score += 0.85
        elif wt2 and gt2 and (wt2 in gt2 or gt2 in wt2):
            score += 0.55
    if wa and ga:
        if wa == ga:
            score += 0.5
        elif wa in ga or ga in wa:
            score += 0.35
    return score


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


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--limit", type=int, default=0, help="最多处理 N 首（0=全部）")
    ap.add_argument("--offset", type=int, default=0, help="从第 N 条开始（0-based）")
    ap.add_argument("--delay", type=float, default=DELAY_SEC)
    ap.add_argument("--apply", action="store_true", help="把抓到的译文写回 packs/*.json")
    ap.add_argument("--dry-run", action="store_true", help="只打印，不写 patch 文件")
    ap.add_argument("--max-fetch-detail", type=int, default=3, help="每首最多拉几个候选详情")
    args = ap.parse_args()

    suspects = load_suspects()
    poems_index = load_pack_poems()
    if args.offset:
        suspects = suspects[args.offset :]
    if args.limit:
        suspects = suspects[: args.limit]

    patches_path = PATCH_OUT
    patches: list[dict] = []
    if patches_path.exists():
        try:
            patches = json.loads(patches_path.read_text(encoding="utf-8"))
        except json.JSONDecodeError:
            patches = []
    done_ids = {(p["pack"], int(p["id"])) for p in patches}

    stats = {"ok": 0, "no_match": 0, "no_means": 0, "fail": 0, "skip": 0, "already": 0}
    log_path = ROOT / "tools" / "_fetch_log.txt"

    def log(msg: str) -> None:
        print(msg, flush=True)
        with open(log_path, "a", encoding="utf-8") as fh:
            fh.write(msg + "\n")

    for i, s in enumerate(suspects, 1):
        pack, pid, title, author = s["pack"], int(s["id"]), s["title"], s["author"]
        if (pack, pid) in done_ids:
            stats["already"] += 1
            continue
        poem = poems_index.get((pack, pid))
        if not poem:
            stats["skip"] += 1
            continue
        log(f"[{i}/{len(suspects)}] {pack} #{pid} {title} / {author}")
        try:
            cands = search_baidu(title, author, poem.get("content") or "")
        except Exception as e:
            log(f"  search fail: {e}")
            stats["fail"] += 1
            time.sleep(args.delay)
            continue
        # search 内部已有缓存；网络请求后稍歇
        time.sleep(args.delay * 0.5)

        best = None
        best_score = 0.0
        fetched = 0
        for c in cands:
            if fetched >= args.max_fetch_detail and best_score >= 1.0:
                break
            if "title" not in c and "means" not in c:
                if fetched >= args.max_fetch_detail:
                    continue
                det = fetch_detail(c["sid"])
                fetched += 1
                time.sleep(args.delay)
                if not det:
                    continue
                c = {**c, **det}
            sc = score_match(title, author, c.get("title") or "", c.get("author") or "")
            if sc > best_score:
                best_score = sc
                best = c

        if not best:
            log("  no candidate")
            stats["no_match"] += 1
            # 写负面记录，避免重跑
            patches.append(
                {
                    "pack": pack,
                    "id": pid,
                    "title": title,
                    "author": author,
                    "status": "no_match",
                }
            )
            continue
        if best_score < 1.35:
            log(f"  weak match score={best_score:.2f} got={best.get('title')}/{best.get('author')}")
            stats["no_match"] += 1
            patches.append(
                {
                    "pack": pack,
                    "id": pid,
                    "title": title,
                    "author": author,
                    "status": "weak_match",
                    "match_score": best_score,
                    "got_title": best.get("title"),
                    "got_author": best.get("author"),
                }
            )
            continue

        # 正文对照：防「标题作者都像、正文却不是这一首」
        src_body = re.sub(r"\s+", "", poem.get("content") or "")
        got_body = re.sub(r"\s+", "", str(best.get("body") or ""))
        if got_body and src_body:
            ov = content_overlap(src_body, got_body)
            if ov < 0.55:
                log(f"  body mismatch ov={ov:.2f} got_title={best.get('title')}")
                stats["no_match"] += 1
                patches.append(
                    {
                        "pack": pack,
                        "id": pid,
                        "title": title,
                        "author": author,
                        "status": "body_mismatch",
                        "match_score": best_score,
                        "body_overlap": ov,
                    }
                )
                continue

        means = best.get("means") or ""
        if not means:
            log("  no means")
            stats["no_means"] += 1
            patches.append(
                {
                    "pack": pack,
                    "id": pid,
                    "title": title,
                    "author": author,
                    "status": "no_means",
                    "sid": best.get("sid"),
                    "match_score": best_score,
                }
            )
            continue

        old = (poem.get("translation") or "").strip()
        if means.strip() == old:
            log("  means equals old, skip")
            stats["skip"] += 1
            continue

        patch = {
            "pack": pack,
            "id": pid,
            "title": title,
            "author": author,
            "status": "ok",
            "old_preview": (old or "")[:80],
            "new_translation": means,
            "source": "baidu_hanyu",
            "sid": best.get("sid"),
            "match_score": best_score,
            "new_appreciation": (best.get("shangxi") or "")[:500] or None,
            "new_background": (best.get("explain") or "")[:500] or None,
        }
        patches.append(patch)
        stats["ok"] += 1
        log(f"  OK score={best_score:.2f} means_len={len(means)}")
        log(f"  -> {means[:80]}")

        # 增量落盘，中断可续
        if i % 3 == 0 and not args.dry_run:
            patches_path.write_text(
                json.dumps(patches, ensure_ascii=False, indent=2), encoding="utf-8"
            )
            print(f"  [saved {len(patches)} patches]", flush=True)

    log("\n=== stats ===")
    log(str(stats))
    if not args.dry_run:
        patches_path.write_text(json.dumps(patches, ensure_ascii=False, indent=2), encoding="utf-8")
        log(f"wrote {patches_path} ({len(patches)} entries)")

    if args.apply and patches:
        apply_patches(patches)


def apply_patches(patches: list[dict]) -> None:
    patches = [p for p in patches if p.get("status") == "ok" and p.get("new_translation")]
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
                # 仅在原赏析也是坏的情况下覆盖？这里只在原赏析命中模板或过短时覆盖
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
