# -*- coding: utf-8 -*-
"""从 chinese-poetry 源数据 + 精选内容库，批量扩充离线包。

背景
----
assets/data/packs/{tangshi,songci,xiaoxue}.json 此前是「名篇精选」，
数量偏少（74/51/19）。本脚本在保留精选内容（译文/赏析/背景）的前提下，
从 tools/tang.*.json 与 tools/ci.song.*.json 补齐更多名篇：

  1. 预置 poems.json（id 1-70）title+作者 重合的诗一律剔除
  2. 精选包 pack_*.json 中已完善的诗优先入包，并携带译文/赏析/背景
  3. 其余名篇按知名作者 / 正文质量筛选，繁体转简体
  4. id 重映射到 importPack/uninstallPack 区间：
     xiaoxue 10001+ / tangshi 20001+ / songci 30001+（每包预留 2000）

用法：
    python tools/expand_offline_packs.py [--dry-run]
"""
from __future__ import annotations

import argparse
import json
import os
import re
import shutil
from collections import Counter, defaultdict

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
TOOLS = os.path.join(ROOT, "tools")
DATA = os.path.join(ROOT, "assets", "data")

RANGES = {
    "xiaoxue": 10000,
    "tangshi": 20000,
    "songci": 30000,
}

# 每包目标数量（不超过 id 区间 2000）
LIMITS = {
    "xiaoxue": 150,
    "tangshi": 600,
    "songci": 500,
}

PACK_META = {
    "tangshi": {
        "pack_name": "tangshi",
        "description": (
            "唐诗扩充包：在预置之外精选 600 首唐诗，覆盖李白、杜甫、白居易、王维等大家。"
            "名篇含白话译文、赏析与创作背景；其余诗文完整可读，离线可用。"
        ),
        "version": "3",
        "source": "chinese-poetry（MIT）· 诗词雅集扩充",
    },
    "songci": {
        "pack_name": "songci",
        "description": (
            "宋词扩充包：在预置之外精选 500 首宋词，覆盖苏轼、辛弃疾、李清照、陆游等大家。"
            "名篇含白话译文、赏析与创作背景；其余词作完整可读，离线可用。"
        ),
        "version": "3",
        "source": "chinese-poetry（MIT）· 诗词雅集扩充",
    },
    "xiaoxue": {
        "pack_name": "xiaoxue",
        "description": (
            "小学补充篇目：部编教材常见而预置未收录的古诗 150 首，"
            "优先保留含译文赏析的篇目，其余诗文完整可读。"
        ),
        "version": "3",
        "source": "chinese-poetry（MIT）· 诗词雅集扩充",
    },
}

TANG_FAMOUS = [
    "李白", "杜甫", "白居易", "王维", "孟浩然", "王昌龄", "岑参", "高适",
    "李商隐", "杜牧", "刘禹锡", "柳宗元", "王之涣", "贺知章", "王勃",
    "骆宾王", "张九龄", "王翰", "李绅", "孟郊", "韩愈", "贾岛",
    "温庭筠", "张志和", "崔护", "陈子昂", "王湾", "李贺", "元稹",
    "刘长卿", "韦应物", "祖咏", "崔颢", "常建", "王建", "张籍",
    "杜审言", "宋之问", "沈佺期", "刘希夷", "张若虚",
    "李颀", "寒山", "拾得", "薛涛", "鱼玄机", "李益", "张祜", "许浑",
    "皮日休", "杜荀鹤", "韦庄", "罗隐", "虞世南", "李峤", "张说",
    "张旭", "卢纶", "司空曙", "钱起", "顾况", "高骈",
]

# 全唐诗源库混入的前唐/乐府/无名作者（非唐诗包目标）
NON_TANG_AUTHORS = {
    "汉乐府", "北朝民歌", "南朝民歌", "无名氏", "佚名", "乐府",
    "陶渊明", "曹操", "曹丕", "曹植", "谢灵运", "谢朓", "鲍照",
    "庾信", "左思", "陆机", "潘岳", "阮籍", "嵇康", "王粲",
    "蔡文姬", "班婕妤", "卓文君", "司马相如", "屈原", "宋玉",
    "诗经", "楚辞", "先秦", "郊庙歌辞", "燕射歌辞", "舞曲歌辞",
    "琴曲歌辞", "杂曲歌辞", "近代曲辞", "杂歌谣辞", "新乐府辞",
    "横吹曲辞", "相和歌辞", "清商曲辞", "太宗皇帝", "玄宗皇帝",
    "德宗皇帝", "文宗皇帝", "宣宗皇帝", "昭宗皇帝", "则天皇后",
}

# 宋词源库混入的非宋作者
NON_SONG_AUTHORS = {
    "无名氏", "佚名", "乐府",
}

# 小学包可保留的前唐名篇（title||author）
XIAOXUE_ALLOW_PRE_TANG = {
    ("敕勒歌", "北朝民歌"),
    ("长歌行", "汉乐府"),
    ("江南", "汉乐府"),
    ("七步诗", "曹植"),
    ("咏鹅", "骆宾王"),  # 唐，防误伤
}

SONG_FAMOUS = [
    "苏轼", "辛弃疾", "李清照", "陆游", "王安石", "欧阳修", "范仲淹",
    "晏殊", "柳永", "秦观", "周邦彦", "贺铸", "张先", "晏几道",
    "黄庭坚", "范成大", "张孝祥", "陈亮", "刘克庄", "吴文英",
    "王沂孙", "蒋捷", "张炎", "姜夔", "史达祖", "高观国",
    "朱敦儒", "叶梦得", "张元干", "岳飞", "文天祥", "杨万里",
    "辛弃疾", "周密", "刘辰翁", "文及翁",
]

# 部编/人教常见小学必背及拓展标题（用于从小学包优先匹配）
XIAOXUE_TITLES = [
    "静夜思", "春晓", "村居", "所见", "小池", "赠刘景文", "山行", "回乡偶书",
    "赠汪伦", "草", "赋得古原草送别", "宿建德江", "六月二十七日望湖楼醉书",
    "敕勒歌", "咏鹅", "风", "咏柳", "晓出净慈寺送林子方", "绝句", "悯农",
    "寻隐者不遇", "长歌行", "七步诗", "江南", "江南春", "登鹳雀楼",
    "望庐山瀑布", "早发白帝城", "黄鹤楼送孟浩然之广陵", "春夜喜雨",
    "江畔独步寻花", "渔歌子", "塞下曲", "游子吟", "望天门山", "古朗月行",
    "独坐敬亭山", "秋词", "夜书所见", "九月九日忆山东兄弟", "望洞庭",
    "采莲曲", "出塞", "芙蓉楼送辛渐", "凉州词", "江南逢李龟年", "竹里馆",
    "梅花", "鹿柴", "江雪", "游园不值", "饮湖上初晴后雨", "望岳",
    "题西林壁", "惠崇春江晚景", "春日", "小儿垂钓", "池上",
    "四时田园杂兴", "舟夜书所见", "江上渔者", "陶者", "蚕妇", "元日",
    "清明", "泊船瓜洲", "相思", "示儿", "冬夜读书示子聿", "观书有感",
    "浪淘沙", "山居秋暝", "终南望余雪", "送元二使安西", "秋夕",
    "夜雨寄北", "商山早行", "题都城南庄", "登幽州台歌", "石灰吟",
    "竹石", "己亥杂诗", "题菊花", "黄鹤楼", "枫桥夜泊", "春望",
    "闻官军收河南河北", "赠花卿", "春夜洛城闻笛", "逢入京使", "月夜",
    "旅夜书怀", "从军行", "夏日绝句", "如梦令", "声声慢", "一剪梅",
    "武陵春", "卜算子·咏梅", "醉花阴", "西江月", "清平乐", "村晚",
    "稚子弄冰", "书愤", "临安春雨初霁", "别董大", "题临安邸", "蜂",
    "寒食", "迢迢牵牛星", "十五从军征", "长歌行", "观沧海", "饮酒",
    "送杜少府之任蜀州", "次北固山下", "使至塞上", "渡荆门送别",
    "行路难", "宣州谢朓楼饯别校书叔云", "茅屋为秋风所破歌",
    "白雪歌送武判官归京", "走马川行奉送封大夫出师西征",
    "左迁至蓝关示侄孙湘", "雁门太守行", "赤壁", "泊秦淮",
    "夜雨寄北", "无题", "相见欢", "渔家傲", "浣溪沙", "登飞来峰",
    "江城子", "水调歌头", "破阵子", "过零丁洋", "天净沙", "山坡羊",
    "己亥杂诗", "论诗", "己亥杂诗", "竹里馆", "春夜洛城闻笛",
]

PUNCT_RE = re.compile(r"[\s　·.。!！?？,，;；:：\"“”‘’'《》（）()\[\]【】\-—_]+")

# 明确排除的散文/非诗词标题（精选库中曾误收）
PROSE_TITLE_BLACKLIST = {
    "岳阳楼记",
    "岳阳楼记节选",
    "岳阳楼记（节选）",
    "醉翁亭记",
    "小石潭记",
    "桃花源记",
    "陋室铭",
    "爱莲说",
    "出师表",
    "陈情表",
    "兰亭集序",
    "滕王阁序",
    "阿房宫赋",
    "前赤壁赋",
    "后赤壁赋",
    "赤壁赋",
    "师说",
    "马说",
    "捕蛇者说",
    "送东阳马生序",
    "核舟记",
    "口技",
    "湖心亭看雪",
    "与朱元思书",
    "五柳先生传",
}


def load_t2s() -> dict[str, str]:
    path = os.path.join(DATA, "t2s_mapping.json")
    with open(path, encoding="utf-8") as f:
        return json.load(f)


def to_simplified(text: str, t2s: dict[str, str]) -> str:
    if not text:
        return ""
    return "".join(t2s.get(ch, ch) for ch in text)


def clean_title(title: str) -> str:
    """清洗全唐诗标题：去掉「 一」「 其二」等卷内序号。"""
    t = (title or "").strip()
    t = re.sub(r"[\s　]+[一二三四五六七八九十百千]+$", "", t)
    t = re.sub(r"[\s　]+其[一二三四五六七八九十百千]+$", "", t)
    return t.strip()


def norm_title(title: str) -> str:
    if not title:
        return ""
    t = clean_title(title)
    t = re.sub(r"[一二三四五六七八九十百千]+$", "", t).strip()
    return PUNCT_RE.sub("", t)


def join_paragraphs(paras: list | None) -> str:
    return "\n".join(x.strip() for x in (paras or []) if x and x.strip())


def content_score(content: str) -> int:
    text = re.sub(r"\s", "", content or "")
    return len(text)


def _strip_poem_punct(s: str) -> str:
    return re.sub(r"[\s，。！？、；：,.!?;:“”\"'《》（）()「」『』—…·]", "", s or "")


def guess_tang_type(content: str, title: str = "") -> str:
    """按行长众数推断体裁。全唐诗常见「对句成行」（五言=10字、七言=14字）。"""
    lines = [_strip_poem_punct(ln) for ln in (content or "").split("\n")]
    lines = [ln for ln in lines if ln]
    if not lines:
        return "古诗"
    # 统计行内字数众数
    counter: Counter[int] = Counter(len(ln) for ln in lines)
    # 映射到每句字数：对句 10/14 → 五言/七言；单句 5/7
    def unit(n: int) -> int:
        if n in (5, 10):
            return 5
        if n in (7, 14):
            return 7
        if n in (4, 8):
            return 4
        if n in (6, 12):
            return 6
        return n if n <= 16 else 0

    unit_counter: Counter[int] = Counter()
    for ln in lines:
        u = unit(len(ln))
        if u:
            unit_counter[u] += 1
    if not unit_counter:
        return "古诗"
    unit_len, unit_hits = unit_counter.most_common(1)[0]
    # 估算句数：总字数 / 每句字数
    total = sum(len(ln) for ln in lines)
    # 对句行：总字数已含两句
    approx_couplets = total // (unit_len * 2) if unit_len in (5, 6, 7) else total // unit_len
    approx_lines = total // unit_len if unit_len else 0
    hit_ratio = unit_hits / max(len(lines), 1)

    if hit_ratio < 0.45:
        # 结构杂乱，按长度粗分
        if total <= 40:
            return "五言绝句" if unit_len == 5 else "七言绝句"
        if total <= 60:
            return "五言律诗" if unit_len <= 5 else "七言律诗"
        return "七言古诗" if unit_len >= 7 else "五言古诗"

    if unit_len == 5:
        if approx_lines <= 4 or approx_couplets <= 2:
            return "五言绝句"
        if approx_lines == 8 or approx_couplets == 4:
            return "五言律诗"
        return "五言古诗"
    if unit_len == 7:
        if approx_lines <= 4 or approx_couplets <= 2:
            return "七言绝句"
        if approx_lines == 8 or approx_couplets == 4:
            return "七言律诗"
        return "七言古诗"
    if unit_len == 4:
        return "四言古诗"
    if unit_len == 6:
        return "六言诗"
    if any(k in (title or "") for k in ("歌", "行", "引", "吟", "曲", "操")):
        return "乐府"
    return "古诗"


def guess_category_ids(title: str, content: str, default: list | None = None) -> list:
    if default:
        return list(default)
    text = (title or "") + (content or "")
    cats: list[int] = []
    if re.search(r"思乡|故乡|归乡|望乡|乡愁|客愁|乡思|忆江南", text):
        cats.append(2)
    if re.search(r"山|水|河|湖|江|海|泉|瀑|溪|峰|春|夏|秋|冬|花|柳|月|雪", text) and 2 not in cats:
        cats.append(3)
    if re.search(r"送别|赠|寄|别|饯|留别", title or ""):
        cats.append(4)
    if re.search(r"咏|题|画|赋得", title or ""):
        cats.append(5)
    if re.search(r"塞|关|军|战|征|马|笛|戍|凉州|从军", text):
        cats.append(6)
    if re.search(r"田|农|耕|渔|村|樵|桑", text):
        cats.append(7)
    if re.search(r"古|故|昔|宫|殿|怀古|金陵|赤壁|乌衣", text):
        cats.append(8)
    if re.search(r"情|爱|恋|相思|忆|梦|妾|郎", text):
        cats.append(9)
    if re.search(r"理|道|禅|悟|哲", text):
        cats.append(10)
    if re.search(r"元日|春|清明|端午|中秋|重阳|除夜|除夕|元夕", text):
        cats.append(12)
    if re.search(r"国|忠|义|志|壮|报国|中原|山河", text) and re.search(
        r"国|民|河山|中原|社稷", text
    ):
        cats.append(13)
    if not cats:
        cats.append(14)
    # 去重保序，最多 3 个
    out: list[int] = []
    for c in cats:
        if c not in out:
            out.append(c)
    return out[:3]


def load_prebuilt_titles() -> set[tuple[str, str]]:
    with open(os.path.join(DATA, "poems.json"), encoding="utf-8") as f:
        pre = json.load(f)
    auth = {a["id"]: a["name"] for a in pre["authors"]}
    return {(norm_title(p["title"]), auth.get(p.get("author_id"), "")) for p in pre["poems"]}


def is_prose_title(title: str) -> bool:
    n = PUNCT_RE.sub("", title or "")
    if n in PROSE_TITLE_BLACKLIST:
        return True
    # 明显散文题式：xxx记 / 说 / 序 / 赋 / 铭 / 传 / 表 / 疏
    if n.endswith(("记", "说", "序", "赋", "铭", "传", "表", "疏")) and len(n) >= 3:
        if not re.search(r"(词|吟|行|歌|引|曲|令|操|谣|咏)", n):
            return True
    return False


def load_curated(pack_key: str, pre_titles: set[tuple[str, str]], t2s: dict[str, str]):
    """从 pack_{key}.json 读取已完善诗词，返回 list[dict]（简化字、已去重）。"""
    path = os.path.join(DATA, "pack_{}.json".format(pack_key))
    if not os.path.exists(path):
        return []
    with open(path, encoding="utf-8") as f:
        d = json.load(f)
    auth = {a["id"]: a["name"] for a in d.get("authors", [])}
    out = []
    for p in d.get("poems", []):
        title = to_simplified((p.get("title") or "").strip(), t2s)
        author = to_simplified(auth.get(p.get("author_id"), "佚名") or "佚名", t2s)
        key = (norm_title(title), author)
        if not title or key in pre_titles:
            continue
        if is_prose_title(title):
            continue
        content = to_simplified(p.get("content") or "", t2s)
        if content_score(content) < 8:
            continue
        lines = [ln for ln in content.split("\n") if ln.strip()]
        if lines and max(len(re.sub(r"[，。！？、；：,.!?;:]", "", ln)) for ln in lines) > 40:
            continue
        dynasty_id = p.get("dynasty_id") or (5 if pack_key != "songci" else 6)
        ptype = p.get("type") or (
            "词" if pack_key == "songci" else guess_tang_type(content, title)
        )
        # 宋词包：排除元明清；唐诗包：保留唐/五代
        if pack_key == "songci" and dynasty_id not in (2, 5, 6):
            continue
        if pack_key == "tangshi" and dynasty_id not in (2, 5):
            continue
        out.append(
            {
                "title": title,
                "content": content,
                "author": author,
                "dynasty_id": dynasty_id,
                "type": ptype,
                "source": p.get("source") or "",
                "category_ids": p.get("category_ids") or guess_category_ids(title, content),
                "translation": to_simplified(p.get("translation") or "", t2s),
                "appreciation": to_simplified(p.get("appreciation") or "", t2s),
                "background": to_simplified(p.get("background") or "", t2s),
                "notes": p.get("notes") or "",
                "priority": 0,
            }
        )
    return out


def load_raw_tang(pre_titles: set[tuple[str, str]], t2s: dict[str, str]) -> list[dict]:
    files = sorted(
        f for f in os.listdir(TOOLS) if re.match(r"^tang\.\d+\.json$", f)
    )
    raw: list[dict] = []
    for fn in files:
        with open(os.path.join(TOOLS, fn), encoding="utf-8") as f:
            raw.extend(json.load(f))
    # 也纳入水墨唐诗
    sx = os.path.join(TOOLS, "shuimotangshi.json")
    if os.path.exists(sx):
        with open(sx, encoding="utf-8") as f:
            raw.extend(json.load(f))

    author_count: Counter[str] = Counter()
    for p in raw:
        author_count[to_simplified((p.get("author") or "").strip(), t2s)] += 1

    out = []
    seen: set[tuple[str, str]] = set(pre_titles)
    for p in raw:
        title = clean_title(to_simplified((p.get("title") or "").strip(), t2s))
        author = to_simplified((p.get("author") or "").strip() or "佚名", t2s)
        content = to_simplified(join_paragraphs(p.get("paragraphs")), t2s)
        # 过滤残缺标题（如「句」「佚题」等无信息标题）
        if len(PUNCT_RE.sub("", title)) < 2 or title in ("句", "佚题", "无题"):
            if title != "无题":
                continue
        key = (norm_title(title), author)
        if not title or not content or key in seen:
            continue
        if is_prose_title(title):
            continue
        sc = content_score(content)
        if sc < 10 or sc > 2500:
            continue
        # 过滤明显不是诗的超长/超短
        lines = [ln for ln in content.split("\n") if ln.strip()]
        if len(lines) > 80:
            continue
        if lines and max(len(re.sub(r"[，。！？、；：,.!?;:]", "", ln)) for ln in lines) > 36:
            continue
        seen.add(key)
        famous = author in TANG_FAMOUS
        # 优先级：0 名家，1 高频作者，2 其他
        if famous:
            pri = 0
        elif author_count[author] >= 20:
            pri = 1
        else:
            pri = 2
        out.append(
            {
                "title": title,
                "content": content,
                "author": author,
                "dynasty_id": 5,
                "type": guess_tang_type(content, title),
                "source": "《全唐诗》",
                "category_ids": guess_category_ids(title, content),
                "translation": "",
                "appreciation": "",
                "background": "",
                "notes": "",
                "priority": pri,
            }
        )
    return out


def load_raw_songci(pre_titles: set[tuple[str, str]], t2s: dict[str, str]) -> list[dict]:
    files = sorted(
        f for f in os.listdir(TOOLS) if re.match(r"^ci\.song\.\d+\.json$", f)
    )
    raw: list[dict] = []
    for fn in files:
        with open(os.path.join(TOOLS, fn), encoding="utf-8") as f:
            raw.extend(json.load(f))
    sc = os.path.join(TOOLS, "songci.json")
    if os.path.exists(sc):
        with open(sc, encoding="utf-8") as f:
            raw.extend(json.load(f))

    author_count: Counter[str] = Counter()
    for p in raw:
        author_count[to_simplified((p.get("author") or "").strip(), t2s)] += 1

    out = []
    seen: set[tuple[str, str]] = set(pre_titles)
    title_seen: set[str] = set()
    for p in raw:
        author = to_simplified((p.get("author") or "").strip() or "佚名", t2s)
        rhythmic = to_simplified((p.get("rhythmic") or "").strip(), t2s)
        content = to_simplified(join_paragraphs(p.get("paragraphs")), t2s)
        if not content or not rhythmic:
            continue
        sc_len = content_score(content)
        if sc_len < 12 or sc_len > 2000:
            continue
        lines = [ln for ln in content.split("\n") if ln.strip()]
        if len(lines) > 60:
            continue
        # 标题：词牌；重复时附加首句短语
        title = rhythmic
        base_key = (norm_title(title), author)
        if base_key in seen:
            first = re.sub(r"[，。！？、；：,.!?;:“”\"']", "", lines[0])[:8]
            if first:
                title = "{}·{}".format(rhythmic, first)
        key = (norm_title(title), author)
        if key in seen or (title in title_seen and author == ""):
            # 再兜底加序号
            n = 2
            while True:
                cand = "{}·其{}".format(rhythmic, n)
                key = (norm_title(cand), author)
                if key not in seen:
                    title = cand
                    break
                n += 1
        if key in pre_titles:
            continue
        seen.add(key)
        title_seen.add(title)
        famous = author in SONG_FAMOUS
        if famous:
            pri = 0
        elif author_count[author] >= 15:
            pri = 1
        else:
            pri = 2
        out.append(
            {
                "title": title,
                "content": content,
                "author": author,
                "dynasty_id": 6,
                "type": "词",
                "source": "《全宋词》",
                "category_ids": guess_category_ids(title, content),
                "translation": "",
                "appreciation": "",
                "background": "",
                "notes": "",
                "priority": pri,
                "rhythmic": rhythmic,
            }
        )
    return out


def pick_xiaoxue(
    tang_pool: list[dict],
    curated: list[dict],
    pre_titles: set[tuple[str, str]],
    limit: int,
) -> list[dict]:
    """小学包：先 curated，再标题命中，再短诗名家，最后补短诗。"""
    result: list[dict] = []
    seen: set[tuple[str, str]] = set()

    def try_add(p: dict) -> bool:
        key = (norm_title(p["title"]), p["author"])
        if key in seen or key in pre_titles:
            return False
        if len(result) >= limit:
            return False
        seen.add(key)
        item = dict(p)
        # 小学包补分类 15（若原分类未含）
        cats = list(item.get("category_ids") or [])
        if 15 not in cats and 1 not in cats:
            cats = [1, 15] if not cats else cats[:2] + [15]
        item["category_ids"] = cats[:3]
        # 保留原 dynasty，无则唐
        if not item.get("dynasty_id"):
            item["dynasty_id"] = 5
        result.append(item)
        return True

    for p in curated:
        try_add(p)

    by_norm: dict[str, list[dict]] = defaultdict(list)
    for p in tang_pool:
        by_norm[norm_title(p["title"])].append(p)

    for title in XIAOXUE_TITLES:
        if len(result) >= limit:
            break
        n = norm_title(title)
        pool = by_norm.get(n, [])
        if not pool:
            # 包含匹配
            for nt, items in by_norm.items():
                if n and (n in nt or nt in n):
                    pool.extend(items)
                    if len(pool) > 8:
                        break
        # 优先名家
        found = next((x for x in pool if x.get("author") in TANG_FAMOUS), None)
        if not found and pool:
            found = pool[0]
        if found:
            try_add(found)

    # 短诗名家补足
    short_famous = sorted(
        (
            p
            for p in tang_pool
            if p.get("author") in TANG_FAMOUS
            and content_score(p["content"]) <= 120
        ),
        key=lambda x: content_score(x["content"]),
    )
    for p in short_famous:
        if len(result) >= limit:
            break
        try_add(p)

    for p in tang_pool:
        if len(result) >= limit:
            break
        if content_score(p["content"]) <= 160:
            try_add(p)

    return result[:limit]


def select_top(pool: list[dict], limit: int) -> list[dict]:
    """按 priority、名家、正文长度适中排序取前 N；同 title+作者去重，保留有译文的。"""
    famous_set = set(TANG_FAMOUS) | set(SONG_FAMOUS)

    # 同 key 去重：优先有译文/赏析，其次 priority 更小
    best: dict[tuple[str, str], dict] = {}
    for p in pool:
        key = (norm_title(p["title"]), p["author"])
        cur = best.get(key)
        if cur is None:
            best[key] = p
            continue

        def rank(x: dict):
            return (
                0 if x.get("translation") or x.get("appreciation") else 1,
                x.get("priority", 9),
            )

        if rank(p) < rank(cur):
            best[key] = p
    deduped = list(best.values())

    def sort_key(p: dict):
        sc = content_score(p["content"])
        # 偏好中等长度（20-400 字），过长古风稍后
        len_pen = abs(sc - 80)
        famous = 0 if p["author"] in famous_set else 1
        has_meta = 0 if p.get("translation") or p.get("appreciation") else 1
        return (p.get("priority", 9), has_meta, famous, len_pen, -sc)

    ordered = sorted(deduped, key=sort_key)
    return ordered[:limit]


def build_pack(pack_key: str, poems: list[dict]) -> dict:
    start = RANGES[pack_key]
    out = []
    for i, p in enumerate(poems):
        item = {
            "id": start + i + 1,
            "title": p["title"],
            "content": p["content"],
            "author": p["author"],
            "dynasty_id": p.get("dynasty_id") or 5,
            "type": p.get("type") or "古诗",
            "sort_order": i + 1,
            "source": p.get("source") or "",
            "category_ids": p.get("category_ids") or [14],
            "translation": p.get("translation") or "",
            "appreciation": p.get("appreciation") or "",
            "background": p.get("background") or "",
            "notes": p.get("notes") or "",
        }
        if p.get("rhythmic"):
            item["rhythmic"] = p["rhythmic"]
        out.append(item)

    meta = dict(PACK_META[pack_key])
    meta["count"] = len(out)
    pack = dict(meta)
    pack["poems"] = out
    return pack


def _load_content_library() -> dict[str, dict]:
    """合并 fill_poem_content 与预置 poems.json 的译文/赏析/背景。"""
    lib: dict[str, dict] = {}

    # 1) fill_poem_content.CONTENT（title → t/a/b）
    try:
        from fill_poem_content import CONTENT as FILL  # type: ignore
    except Exception:
        FILL = {}
    for title, c in FILL.items():
        if "||" in title:
            continue
        entry = lib.setdefault(title, {})
        for k in ("translation", "appreciation", "background"):
            if c.get(k) and not entry.get(k):
                entry[k] = c[k]

    # 2) 预置 poems.json
    try:
        with open(os.path.join(DATA, "poems.json"), encoding="utf-8") as f:
            pre = json.load(f)
        auth = {a["id"]: a["name"] for a in pre.get("authors", [])}
        for p in pre.get("poems", []):
            title = p.get("title") or ""
            entry = lib.setdefault(title, {})
            for k in ("translation", "appreciation", "background"):
                v = (p.get(k) or "").strip()
                if v and not entry.get(k):
                    entry[k] = v
    except Exception as e:
        print("  ⚠️ 读取 poems.json 内容库失败:", e)

    # 3) 内容知识库 A/B（仅赏析/背景）
    try:
        from content.poem_content_a import POEM_CONTENT_A  # type: ignore
        from content.poem_content_b import POEM_CONTENT_B  # type: ignore

        for src in (POEM_CONTENT_A, POEM_CONTENT_B):
            for title, c in src.items():
                if "||" in title:
                    continue
                entry = lib.setdefault(title, {})
                for k in ("translation", "appreciation", "background"):
                    if c.get(k) and not entry.get(k):
                        entry[k] = c[k]
    except Exception as e:
        print("  ⚠️ 读取 poem_content A/B 失败:", e)

    return lib


def _apply_content_library(poems: list[dict], lib: dict[str, dict]) -> None:
    filled = 0
    for p in poems:
        if p.get("translation") and p.get("appreciation") and p.get("background"):
            continue
        c = lib.get(p["title"]) or lib.get(norm_title(p["title"]))
        # 词牌名标题也尝试精确匹配
        if not c and "·" in p["title"]:
            c = lib.get(p["title"].split("·")[0])
        if not c:
            continue
        changed = False
        for k in ("translation", "appreciation", "background"):
            if not (p.get(k) or "").strip() and c.get(k):
                p[k] = c[k]
                changed = True
        if changed:
            filled += 1
    if filled:
        print("  内容库回填：{} 首补齐了部分字段".format(filled))


def _attach_author_bios(pack: dict, poems: list[dict]) -> None:
    """为包内作者附加真实简介（导入时优先使用，避免占位模板）。"""
    try:
        from content.author_bios import AUTHOR_BIOS  # type: ignore
    except Exception:
        AUTHOR_BIOS = {}

    # 预置 poems.json 作者简介
    pre_bios: dict[str, dict] = {}
    try:
        with open(os.path.join(DATA, "poems.json"), encoding="utf-8") as f:
            pre = json.load(f)
        for a in pre.get("authors", []):
            pre_bios[a["name"]] = {
                "name": a["name"],
                "dynasty_id": a.get("dynasty_id"),
                "bio": a.get("bio") or "",
                "birth_year": a.get("birth_year"),
                "death_year": a.get("death_year"),
            }
    except Exception:
        pass

    seen: set[str] = set()
    authors: list[dict] = []
    for p in poems:
        name = p["author"]
        if name in seen:
            continue
        seen.add(name)
        if name in pre_bios:
            authors.append(dict(pre_bios[name]))
            continue
        if name in AUTHOR_BIOS:
            bio, birth, death, dyn_name = AUTHOR_BIOS[name]
            dyn_id = p.get("dynasty_id") or 5
            # 按朝代名映射到 poems.json 的 id
            for did, dname in ((5, "唐"), (6, "宋"), (3, "元"), (4, "明"),
                               (1, "清"), (2, "五代"), (7, "先秦"), (8, "汉"),
                               (9, "魏晋"), (10, "南北朝")):
                if dname == dyn_name:
                    dyn_id = did
                    break
            authors.append({
                "name": name,
                "dynasty_id": dyn_id,
                "bio": bio,
                "birth_year": birth,
                "death_year": death,
            })
            continue
        # 无简介则不写入，交给 importPack 占位
        authors.append({
            "name": name,
            "dynasty_id": p.get("dynasty_id") or 5,
            "bio": "",
        })

    pack["authors"] = authors


def write_pack(pack_key: str, pack: dict, dry_run: bool) -> str:
    path = os.path.join(DATA, "packs", "{}.json".format(pack_key))
    os.makedirs(os.path.dirname(path), exist_ok=True)
    if not dry_run:
        bak_dir = os.path.join(ROOT, "build", "packs_backup")
        os.makedirs(bak_dir, exist_ok=True)
        if os.path.exists(path):
            shutil.copy2(path, os.path.join(bak_dir, "{}.json".format(pack_key)))
        with open(path, "w", encoding="utf-8") as f:
            json.dump(pack, f, ensure_ascii=False, separators=(",", ":"))
    size = os.path.getsize(path) if os.path.exists(path) and not dry_run else 0
    # dry-run 时用序列化估算
    if dry_run:
        size = len(json.dumps(pack, ensure_ascii=False, separators=(",", ":")).encode("utf-8"))
    return size


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--dry-run", action="store_true")
    args = parser.parse_args()

    t2s = load_t2s()
    pre_titles = load_prebuilt_titles()
    print("预置 poems.json：{} 首（title+作者 去重键 {} 个）".format(
        len(pre_titles), len(pre_titles)))

    cur_x = load_curated("xiaoxue", pre_titles, t2s)
    cur_t = load_curated("tangshi", pre_titles, t2s)
    cur_s = load_curated("songci", pre_titles, t2s)
    print("精选素材：xiaoxue={} tangshi={} songci={}".format(
        len(cur_x), len(cur_t), len(cur_s)))

    raw_t = load_raw_tang(pre_titles, t2s)
    raw_s = load_raw_songci(pre_titles, t2s)
    print("源数据：全唐诗有效 {} 首，全宋词有效 {} 首".format(len(raw_t), len(raw_s)))

    # ---- xiaoxue ----
    xiaoxue = pick_xiaoxue(raw_t, cur_x, pre_titles, LIMITS["xiaoxue"])

    # ---- tangshi ----
    # 去掉已进小学包的 + 前唐/乐府/帝王作者
    xia_keys = {(norm_title(p["title"]), p["author"]) for p in xiaoxue}

    def _is_tang_poem(p: dict) -> bool:
        return p["author"] not in NON_TANG_AUTHORS

    t_cur = [
        p
        for p in cur_t
        if (norm_title(p["title"]), p["author"]) not in xia_keys and _is_tang_poem(p)
    ]
    t_raw = [
        p
        for p in raw_t
        if (norm_title(p["title"]), p["author"]) not in xia_keys and _is_tang_poem(p)
    ]
    tangshi = select_top(t_cur + t_raw, LIMITS["tangshi"])

    # ---- songci ----
    s_cur = [p for p in cur_s if p["author"] not in NON_SONG_AUTHORS]
    s_raw = [p for p in raw_s if p["author"] not in NON_SONG_AUTHORS]
    songci = select_top(s_cur + s_raw, LIMITS["songci"])

    # 回填已有内容库（fill_poem_content / 预置 poems.json）中可匹配的译文赏析背景
    content_lib = _load_content_library()
    for poems in (xiaoxue, tangshi, songci):
        _apply_content_library(poems, content_lib)

    stats = {}
    for key, poems in [("xiaoxue", xiaoxue), ("tangshi", tangshi), ("songci", songci)]:
        pack = build_pack(key, poems)
        _attach_author_bios(pack, poems)
        size = write_pack(key, pack, args.dry_run)
        with_tr = sum(1 for p in pack["poems"] if p.get("translation"))
        with_ap = sum(1 for p in pack["poems"] if p.get("appreciation"))
        stats[key] = pack["count"]
        print(
            "[{}] {} 首 | 含译文 {} | 含赏析 {} | {} KB{}".format(
                key,
                pack["count"],
                with_tr,
                with_ap,
                round(size / 1024, 1),
                " (dry-run)" if args.dry_run else "",
            )
        )
        # 抽样
        for p in pack["poems"][:3]:
            print("   ·", p["id"], p["title"], "·", p["author"])

    print("合计：{}".format(sum(stats.values())))
    if not args.dry_run:
        print("已写入 assets/data/packs/*.json，旧包备份至 build/packs_backup/")


if __name__ == "__main__":
    main()
