// 把 chinese-poetry 原始数据转换为 shici_yaji 离线包 JSON
// 输出：assets/data/packs/{tangshi.json, songci.json, xiaoxue.json}
const fs = require('fs');
const path = require('path');

const TOOLS = __dirname;
const OUT = path.join(TOOLS, '..', 'assets', 'data', 'packs');
if (!fs.existsSync(OUT)) fs.mkdirSync(OUT, { recursive: true });

function joinParagraphs(arr) {
  return (arr || []).join('\n');
}

// 加载所有已下载的 tang.*.json 文件，合并
function loadAllTangshi() {
  const files = fs.readdirSync(TOOLS).filter((f) => /^tang\.\d+\.json$/.test(f));
  const all = [];
  for (const f of files) {
    const data = JSON.parse(fs.readFileSync(path.join(TOOLS, f), 'utf-8'));
    all.push(...data);
  }
  return { all, files };
}

// 加载所有宋词分卷（含 songci.json）
function loadAllSongci() {
  const all = [];
  // 1. 优先加载 ci.song.*.json
  const files = fs.readdirSync(TOOLS).filter((f) => /^ci\.song\.\d+\.json$/.test(f));
  for (const f of files) {
    const data = JSON.parse(fs.readFileSync(path.join(TOOLS, f), 'utf-8'));
    all.push(...data);
  }
  // 2. 合并 songci.json（宋词三百首精选）
  const songci = path.join(TOOLS, 'songci.json');
  if (fs.existsSync(songci)) {
    const data = JSON.parse(fs.readFileSync(songci, 'utf-8'));
    all.push(...data);
  }
  return all;
}

// 标准化标题：去尾部"一/二/三..."序号
function normTitle(t) {
  if (!t) return '';
  return t.replace(/[一二三四五六七八九十百千]+[、，。．.\s]*$/, '').trim();
}

const TANGSHI_AUTHORS = [
  '李白','杜甫','白居易','王维','孟浩然','王昌龄','岑参','高适',
  '李商隐','杜牧','刘禹锡','柳宗元','王之涣','贺知章','王勃',
  '骆宾王','张九龄','王翰','李绅','孟郊','韩愈','贾岛',
  '温庭筠','张志和','崔护','陈子昂','王湾','李贺','元稹',
  '刘长卿','韦应物','祖咏','崔颢','常建','王建','张籍',
  '杜审言','宋之问','沈佺期','刘希夷','张若虚',
  '李颀','綦毋潜','王梵志','寒山','拾得',
  '高骈','王之涣','薛涛','鱼玄机','李益','张祜','许浑',
  '皮日休','杜荀鹤','韦庄','罗隐','聂夷中','于谦',
  '骆宾王','虞世南','李峤','苏味道','崔湜','李乂','薛稷','张说',
  '张九龄','张若虚','陈子昂','贺知章','张旭',
  '王昌龄','刘长卿','韦应物','李端','卢纶','司空曙','钱起',
  '崔峒','耿湋','夏侯审','李嘉祐','严维','顾况','柳宗元',
  '韩愈','柳宗元','元稹','白居易','刘禹锡','李贺','杜牧',
  '温庭筠','李商隐','聂夷中','杜荀鹤','皮日休',
];

// 宋词作者：用频次补全代替穷举
const SONGCI_AUTHORS_PRIORITY = [
  '苏轼','辛弃疾','李清照','陆游','王安石','欧阳修','范仲淹',
  '晏殊','柳永','秦观','周邦彦','贺铸','张先','晏几道',
  '黄庭坚','范成大','张孝祥','陈亮','刘克庄','吴文英',
  '王沂孙','蒋捷','张炎','文及翁','邓剡','刘辰翁','周密',
  '史达祖','高观国','袁去华','陆游','张元干',
  '朱敦儒','叶梦得','李纲','赵鼎','李清照',
  '姜夔','吴文英','史达祖','高观国','张炎',
];

const XIAOXUE_TITLES = [
  '静夜思','春晓','村居','所见','小池','赠刘景文','山行','回乡偶书',
  '赠汪伦','草','宿建德江','六月二十七日望湖楼醉书','西江月·夜行黄沙道中','敕勒歌','咏鹅',
  '风','咏柳','晓出净慈寺送林子方','绝句','悯农',
  '寻隐者不遇','长歌行','七步诗','江南','江南春','登鹳雀楼','望庐山瀑布',
  '早发白帝城','黄鹤楼送孟浩然之广陵','春夜喜雨','江畔独步寻花','渔歌子','塞下曲',
  '游子吟','望天门山','古朗月行','独坐敬亭山','秋词','夜书所见','九月九日忆山东兄弟',
  '望洞庭','采莲曲','出塞','芙蓉楼送辛渐','凉州词',
  '江南逢李龟年','竹里馆','梅花','鹿柴','江雪','游园不值',
  '饮湖上初晴后雨','望岳','题西林壁','惠崇春江晚景','春日','清平调',
  '小儿垂钓','池上','四时田园杂兴','舟夜书所见','江上渔者','陶者','蚕妇',
  '元日','清明','泊船瓜洲','相思','示儿',
  '冬夜读书示子聿','观书有感','卜算子·送鲍浩然之浙东','浪淘沙','古从军行',
  '山居秋暝','终南望余雪','送元二使安西','秋夕','夜雨寄北','无题',
  '商山早行','题都城南庄','登幽州台歌',
  '咏煤炭','石灰吟','竹石','己亥杂诗','题菊花','黄鹤楼','枫桥夜泊',
  '渔歌子','游子吟','秋思','春望','闻官军收河南河北',
  '赠花卿','江南春绝句','春夜洛城闻笛','逢入京使','月夜','旅夜书怀',
  '春望','绝句·两个黄鹂鸣翠柳','绝句二首·迟日江山丽','绝句·生当作人杰',
  '江上渔者','陶者','蚕妇','梅花','书愤','示儿','临安春雨初霁',
  '四时田园杂兴','稚子弄冰','村晚','从军行','咏史',
  '夏日绝句','如梦令','声声慢','一剪梅','武陵春',
  '卜算子·咏梅','如梦令·常记溪亭日暮','醉花阴·薄雾浓云愁永昼',
];

function pickTangshi(limit = 300) {
  const { all: raw, files } = loadAllTangshi();
  console.log(`  唐诗原始数据：${raw.length} 首，来自 ${files.length} 个分卷`);
  const result = [];
  const seen = new Set();

  // 第一轮：按知名作者
  for (const p of raw) {
    if (result.length >= limit) break;
    if (TANGSHI_AUTHORS.includes(p.author) && !seen.has(p.title)) {
      seen.add(p.title);
      result.push(makePoem(p, 20000 + result.length + 1, result.length + 1, 5, '唐诗', '《全唐诗》', [1, 3]));
    }
  }
  // 第二轮：按作者频率补全（出现频次高的作者优先）
  if (result.length < limit) {
    const authorCount = new Map();
    for (const p of raw) authorCount.set(p.author, (authorCount.get(p.author) || 0) + 1);
    const sortedAuthors = [...authorCount.entries()].sort((a, b) => b[1] - a[1]);
    for (const [author] of sortedAuthors) {
      if (result.length >= limit) break;
      for (const p of raw) {
        if (result.length >= limit) break;
        if (p.author === author && !seen.has(p.title)) {
          seen.add(p.title);
          result.push(makePoem(p, 20000 + result.length + 1, result.length + 1, 5, '唐诗', '《全唐诗》', [1, 3]));
        }
      }
    }
  }
  return result;
}

function pickSongci(limit = 200) {
  const raw = loadAllSongci();
  console.log(`  宋词原始数据：${raw.length} 首`);
  const result = [];
  const seen = new Set();

  // 直接按作者频次取（频次高的作者是公认大家）
  const authorCount = new Map();
  for (const p of raw) authorCount.set(p.author, (authorCount.get(p.author) || 0) + 1);
  const sortedAuthors = [...authorCount.entries()].sort((a, b) => b[1] - a[1]).map(([a]) => a);

  // 优先作者置顶（确保苏轼/辛弃疾/李清照等一定在前）
  const ordered = [...new Set([...SONGCI_AUTHORS_PRIORITY, ...sortedAuthors])];
  for (const author of ordered) {
    if (result.length >= limit) break;
    for (const p of raw) {
      if (result.length >= limit) break;
      if (p.author === author && !seen.has(p.title + '_' + p.author)) {
        seen.add(p.title + '_' + p.author);
        result.push(makePoem(p, 30000 + result.length + 1, result.length + 1, 6, '宋词', '《宋词》', [1], p.rhythmic));
      }
    }
  }
  return result;
}

function pickXiaoxue(limit = 100) {
  const { all: tang } = loadAllTangshi();
  // 用标准化标题建索引
  const byNorm = new Map();
  for (const p of tang) {
    const n = normTitle(p.title);
    if (!byNorm.has(n)) byNorm.set(n, []);
    byNorm.get(n).push(p);
  }
  const result = [];
  const seen = new Set();

  for (const title of XIAOXUE_TITLES) {
    if (result.length >= limit) break;
    // 1. 标准化精确匹配
    let pool = byNorm.get(title) || [];
    // 2. 包含匹配
    if (pool.length === 0) {
      for (const p of tang) {
        const nt = normTitle(p.title);
        if (nt === title || nt.includes(title) || title.includes(nt)) {
          pool.push(p);
        }
      }
    }
    // 3. 选 TANGSHI_AUTHORS 作者的版本
    let found = pool.find((p) => TANGSHI_AUTHORS.includes(p.author) && !seen.has(p.title));
    if (!found) found = pool.find((p) => !seen.has(p.title));
    if (found) {
      seen.add(found.title);
      result.push(makePoem(found, 10000 + result.length + 1, result.length + 1, found.author && getDynastyForTang(found.author) || 5, '小学必背', '《全唐诗》', [1, 15]));
    }
  }
  // 不足则从小学知名度高作者补
  if (result.length < limit) {
    for (const p of tang) {
      if (result.length >= limit) break;
      if (!seen.has(p.title) && TANGSHI_AUTHORS.includes(p.author)) {
        seen.add(p.title);
        result.push(makePoem(p, 10000 + result.length + 1, result.length + 1, 5, '小学必背', '《全唐诗》', [1, 15]));
      }
    }
  }
  return result.slice(0, limit);
}

function getDynastyForTang(author) {
  return 5;
}

function makePoem(p, id, sortOrder, dynastyId, type, source, categoryIds, rhythmic) {
  const out = {
    id,
    title: p.title,
    content: joinParagraphs(p.paragraphs),
    author: p.author,
    dynasty_id: dynastyId,
    type,
    sort_order: sortOrder,
    source,
    category_ids: categoryIds,
  };
  if (rhythmic) out.rhythmic = rhythmic;
  return out;
}

function writePack(name, desc, data) {
  const out = {
    pack_name: name,
    description: desc,
    version: 1,
    source: 'chinese-poetry 开源库（MIT 协议）',
    count: data.length,
    poems: data,
  };
  const filePath = path.join(OUT, `${name}.json`);
  fs.writeFileSync(filePath, JSON.stringify(out, null, 2), 'utf-8');
  console.log(`✓ ${name}.json: ${data.length} 首, ${(fs.statSync(filePath).size / 1024).toFixed(1)} KB`);
}

console.log('=== 转换 chinese-poetry → 离线包 ===');
writePack('tangshi', '唐诗精选300首', pickTangshi(300));
writePack('songci', '宋词精选200首', pickSongci(200));
writePack('xiaoxue', '小学必背100首', pickXiaoxue(100));
console.log('✅ 离线包生成完成');
