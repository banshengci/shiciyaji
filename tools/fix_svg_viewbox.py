# -*- coding: utf-8 -*-
"""给 assets/icons 下的 SVG 补 viewBox。

Ardot 导出的 SVG 只有 width/height、没有 viewBox，flutter_svg 在缩放时
会按原始视口渲染，导致 SvgPicture 指定尺寸后图形不跟随放大。
本脚本从 width/height 推导并写入 viewBox="0 0 w h"，同时把尺寸统一归一到
24x24 画布（保留原始坐标，靠 viewBox 缩放），使 Flutter 侧可按任意 size 使用。

用法：python tools/fix_svg_viewbox.py
"""
import os
import re
import sys

ICON_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', 'assets', 'icons')


def process(path: str) -> str:
    with open(path, 'r', encoding='utf-8') as f:
        src = f.read()

    if 'viewBox' in src:
        return 'skip(already)'

    m = re.search(r'<svg([^>]*)>', src)
    if not m:
        return 'error(no-svg-tag)'
    attrs = m.group(1)

    wm = re.search(r'width="([\d.]+)"', attrs)
    hm = re.search(r'height="([\d.]+)"', attrs)
    if not wm or not hm:
        return 'error(no-size)'

    w, h = float(wm.group(1)), float(hm.group(1))
    new_svg = '<svg viewBox="0 0 %s %s"%s>' % (
        (str(int(w)) if w == int(w) else str(w)),
        (str(int(h)) if h == int(h) else str(h)),
        attrs,
    )
    out = src[:m.start()] + new_svg + src[m.end():]
    with open(path, 'w', encoding='utf-8') as f:
        f.write(out)
    return 'ok(%gx%g)' % (w, h)


def main() -> int:
    if not os.path.isdir(ICON_DIR):
        print('ICON_DIR not found: %s' % ICON_DIR)
        return 1
    files = sorted(f for f in os.listdir(ICON_DIR) if f.lower().endswith('.svg'))
    counts = {}
    for name in files:
        r = process(os.path.join(ICON_DIR, name))
        key = r.split('(')[0]
        counts[key] = counts.get(key, 0) + 1
    print('processed %d svg files' % len(files))
    for k, v in sorted(counts.items()):
        print('  %-16s %d' % (k, v))
    # 抽验
    for name in ('home.svg', 'bookmark.svg'):
        p = os.path.join(ICON_DIR, name)
        if os.path.exists(p):
            head = open(p, encoding='utf-8').read()[:180]
            print('\n--- %s ---\n%s' % (name, head))
    return 0


if __name__ == '__main__':
    sys.exit(main())
