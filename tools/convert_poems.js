/**
 * 诗词数据转换工具
 * 从内嵌的经典唐诗宋词数据生成项目格式文件
 *
 * 使用方法: node convert_poems.js
 *
 * 输出文件:
 * - poems_v2.json - 合并后的完整诗词数据
 * - pack_tangshi.json - 唐诗离线包
 * - pack_songci.json - 宋词离线包
 * - pack_xiaoxue.json - 小学必背离线包
 */

const fs = require('fs');
const path = require('path');
const { tangshi, songci } = require('./poems_data.js');

const OUTPUT_DIR = path.join(__dirname, '..', 'assets', 'data');
const POEMS_JSON_PATH = path.join(OUTPUT_DIR, 'poems.json');

// 朝代 ID 映射
const DYNASTY_MAP = { '唐': 5, '宋': 6, '元': 3, '明': 4, '清': 1, '五代': 2 };

// ============ 工具函数 ============

function loadExistingPoems() {
  const raw = fs.readFileSync(POEMS_JSON_PATH, 'utf-8');
  return JSON.parse(raw);
}

function isDuplicate(title, existingTitles) {
  const norm = title.replace(/[\s·.。!！?？,，;；:：""''《》（）\[\]【】\-]/g, '');
  for (const t of existingTitles) {
    const normT = t.replace(/[\s·.。!！?？,，;；:：""''《》（）\[\]【】\-]/g, '');
    if (norm === normT) return true;
  }
  return false;
}

function guessCategoryIds(title, content, defaultCats) {
  if (defaultCats && defaultCats.length > 0) return defaultCats;
  const text = title + content;
  const cats = [];
  if (/思乡|故乡|归乡|望乡|乡愁|客愁/.test(text)) cats.push(2);
  if (/山|水|河|湖|江|海|泉|瀑|溪|峰|春|夏|秋|冬|花|柳/.test(text) && !cats.includes(2)) cats.push(3);
  if (/送别|别|赠|寄/.test(text)) cats.push(4);
  if (/咏|题|画/.test(title)) cats.push(5);
  if (/塞|关|军|战|征|马|笛/.test(text)) cats.push(6);
  if (/田|农|耕|渔|村/.test(text)) cats.push(7);
  if (/古|故|昔|宫|殿/.test(text)) cats.push(8);
  if (/情|爱|恋|相思/.test(text)) cats.push(9);
  if (/理|道|禅|悟/.test(text)) cats.push(10);
  if (/元|春|清明|端午|中秋|重阳/.test(text)) cats.push(12);
  if (/国|忠|义|志|壮/.test(text) && /国|民|河山|中原/.test(text)) cats.push(13);
  if (cats.length === 0) cats.push(14);
  return [...new Set(cats)].slice(0, 3);
}

function isSuitableForKids(title, content, type) {
  const len = content.replace(/[\s\n]/g, '').length;
  if (['五言绝句', '七言绝句', '五言律诗', '七言律诗', '词'].includes(type) && len <= 300) return true;
  return false;
}

// ============ 主流程 ============

function main() {
  console.log('=== 诗词数据转换工具 ===\n');

  // 1. 加载现有数据
  console.log('1. 加载现有 poems.json...');
  const existingData = loadExistingPoems();
  const { dynasties, authors: existingAuthors, categories, poems: existingPoems } = existingData;

  console.log(`   现有: ${existingPoems.length} 首诗词, ${existingAuthors.length} 位作者`);

  const existingTitles = existingPoems.map(p => p.title);
  const existingContents = new Set(existingPoems.map(p => p.content.replace(/[\s\n]/g, '')));

  // 收集现有作者名到 ID 的映射
  const authorNameToId = {};
  for (const a of existingAuthors) {
    authorNameToId[a.name] = a.id;
  }

  // 2. 处理唐诗数据
  console.log('\n2. 处理唐诗数据...');
  const tangPoems = [];
  for (const item of tangshi) {
    if (isDuplicate(item.title, existingTitles)) continue;
    if (existingContents.has(item.content.replace(/[\s\n]/g, ''))) continue;
    tangPoems.push({ ...item, dynasty: '唐', dynasty_id: 5 });
  }
  console.log(`   有效唐诗: ${tangPoems.length} 首`);

  // 3. 处理宋词数据
  console.log('\n3. 处理宋词数据...');
  const songPoems = [];
  for (const item of songci) {
    if (isDuplicate(item.title, existingTitles)) continue;
    if (existingContents.has(item.content.replace(/[\s\n]/g, ''))) continue;
    songPoems.push({ ...item, dynasty: '宋', dynasty_id: 6 });
  }
  console.log(`   有效宋词: ${songPoems.length} 首`);

  // 4. 去重内部重复（同一脚本内可能有重复标题）
  console.log('\n4. 内部去重...');
  const seenTitles = new Set();
  const uniqueTang = tangPoems.filter(p => {
    const key = p.title + p.author;
    if (seenTitles.has(key)) return false;
    seenTitles.add(key);
    return true;
  });
  const uniqueSong = songPoems.filter(p => {
    const key = p.title + p.author;
    if (seenTitles.has(key)) return false;
    seenTitles.add(key);
    return true;
  });
  console.log(`   去重后唐诗: ${uniqueTang.length} 首`);
  console.log(`   去重后宋词: ${uniqueSong.length} 首`);

  // 5. 添加新作者
  console.log('\n5. 添加新作者...');
  let nextAuthorId = Math.max(...existingAuthors.map(a => a.id)) + 1;
  const newAuthors = [];
  const newAuthorNameToId = { ...authorNameToId };

  const allNewPoems = [...uniqueTang, ...uniqueSong];
  const neededAuthors = new Set(allNewPoems.map(p => p.author));

  for (const name of neededAuthors) {
    if (!newAuthorNameToId[name]) {
      const dynasty = allNewPoems.find(p => p.author === name).dynasty;
      const author = {
        id: nextAuthorId++,
        name: name,
        dynasty_id: DYNASTY_MAP[dynasty] || 0,
        bio: '',
        birth_year: '',
        death_year: ''
      };
      newAuthors.push(author);
      newAuthorNameToId[name] = author.id;
    }
  }
  console.log(`   新增作者: ${newAuthors.length} 位`);
  const allAuthors = [...existingAuthors, ...newAuthors];

  // 6. 生成完整诗词列表
  console.log('\n6. 生成完整诗词列表...');
  let nextPoemId = existingPoems.length + 1;
  let nextSortOrder = existingPoems.length + 1;

  function toFinalFormat(poem) {
    const content = poem.content;
    const type = poem.type || detectType(content);
    return {
      id: nextPoemId++,
      title: poem.title,
      content: content,
      author_id: newAuthorNameToId[poem.author] || 0,
      dynasty_id: poem.dynasty_id,
      type: type,
      sort_order: nextSortOrder++,
      translation: '',
      appreciation: '',
      background: '',
      source: '',
      category_ids: guessCategoryIds(poem.title, content, poem.category_ids)
    };
  }

  function detectType(content) {
    const lines = content.split('\n').filter(l => l.trim());
    const lineCount = lines.length;
    const charCounts = lines.map(l => l.replace(/[，。！？、；：""''《》（）\s]/g, '').length);
    if (lineCount <= 4) {
      if (charCounts.every(c => c === 5)) return '五言绝句';
      if (charCounts.every(c => c === 7)) return '七言绝句';
    }
    if (charCounts.every(c => c === 5)) return '五言古诗';
    if (charCounts.every(c => c === 7)) return '七言古诗';
    return '词';
  }

  const newPoems = [];
  for (const p of uniqueTang) newPoems.push(toFinalFormat(p));
  for (const p of uniqueSong) newPoems.push(toFinalFormat(p));

  console.log(`   新增诗词: ${newPoems.length} 首`);
  const allPoems = [...existingPoems, ...newPoems];
  console.log(`   合并后: ${allPoems.length} 首`);

  // 7. 生成 poems_v2.json
  console.log('\n7. 生成 poems_v2.json...');
  if (!fs.existsSync(OUTPUT_DIR)) {
    fs.mkdirSync(OUTPUT_DIR, { recursive: true });
  }

  const fullData = { dynasties, authors: allAuthors, categories, poems: allPoems };
  const poemsV2Path = path.join(OUTPUT_DIR, 'poems_v2.json');
  fs.writeFileSync(poemsV2Path, JSON.stringify(fullData, null, 2), 'utf-8');
  console.log(`   已保存: ${poemsV2Path}`);
  console.log(`   总诗词: ${allPoems.length}, 总作者: ${allAuthors.length}`);

  // 8. 生成唐诗包
  console.log('\n8. 生成 pack_tangshi.json...');
  const tangPackPoems = allPoems.filter(p => p.dynasty_id === 5);
  const tangPack = buildPack(tangPackPoems, allAuthors, dynasties, categories, 71);
  fs.writeFileSync(path.join(OUTPUT_DIR, 'pack_tangshi.json'), JSON.stringify(tangPack, null, 2), 'utf-8');
  console.log(`   唐诗包: ${tangPackPoems.length} 首 (id 从 71 开始)`);

  // 9. 生成宋词包
  console.log('\n9. 生成 pack_songci.json...');
  const songPackPoems = allPoems.filter(p => p.dynasty_id === 6);
  const songPack = buildPack(songPackPoems, allAuthors, dynasties, categories, 271);
  fs.writeFileSync(path.join(OUTPUT_DIR, 'pack_songci.json'), JSON.stringify(songPack, null, 2), 'utf-8');
  console.log(`   宋词包: ${songPackPoems.length} 首 (id 从 271 开始)`);

  // 10. 生成小学必背包
  console.log('\n10. 生成 pack_xiaoxue.json...');
  const kidPoems = allPoems.filter(p => isSuitableForKids(p.title, p.content, p.type)).slice(0, 80);
  const xiaoxuePack = buildPack(kidPoems, allAuthors, dynasties, categories, 421);
  fs.writeFileSync(path.join(OUTPUT_DIR, 'pack_xiaoxue.json'), JSON.stringify(xiaoxuePack, null, 2), 'utf-8');
  console.log(`   小学必背包: ${kidPoems.length} 首 (id 从 421 开始)`);

  console.log('\n=== 完成! ===');
  console.log(`总计: ${allPoems.length} 首诗词, ${allAuthors.length} 位作者`);
  console.log(`唐诗包: ${tangPackPoems.length} 首`);
  console.log(`宋词包: ${songPackPoems.length} 首`);
  console.log(`小学必背包: ${kidPoems.length} 首`);
}

function buildPack(poems, allAuthors, dynasties, categories, startId) {
  let id = startId;
  let sortOrder = startId;
  const reindexed = poems.map(p => ({
    ...p,
    id: id++,
    sort_order: sortOrder++
  }));
  const authorIds = new Set(reindexed.map(p => p.author_id));
  const packAuthors = allAuthors.filter(a => authorIds.has(a.id));
  return { dynasties, authors: packAuthors, categories, poems: reindexed };
}

main();
