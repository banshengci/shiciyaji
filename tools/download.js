// 下载 chinese-poetry 离线包原始数据（精简版 - 使用 jsdelivr CDN）
const https = require('https');
const fs = require('fs');
const path = require('path');

const OUT_DIR = path.join(__dirname);
const BASE = 'https://cdn.jsdelivr.net/gh/chinese-poetry/chinese-poetry@master/';

// 只下载必要文件
const FILES = [
  // 全唐诗 4 个分卷
  ['tang.2000.json', encodeURIComponent('全唐诗') + '/poet.tang.2000.json'],
  ['tang.3000.json', encodeURIComponent('全唐诗') + '/poet.tang.3000.json'],
  ['tang.4000.json', encodeURIComponent('全唐诗') + '/poet.tang.4000.json'],
  ['tang.5000.json', encodeURIComponent('全唐诗') + '/poet.tang.5000.json'],
];

function download(url) {
  return new Promise((resolve, reject) => {
    const req = https.get(url, { headers: { 'User-Agent': 'node-fetch' } }, (res) => {
      if (res.statusCode === 301 || res.statusCode === 302) {
        return download(res.headers.location).then(resolve, reject);
      }
      if (res.statusCode !== 200) {
        return reject(new Error(`HTTP ${res.statusCode} for ${url}`));
      }
      const chunks = [];
      let totalSize = 0;
      const MAX_SIZE = 3 * 1024 * 1024; // 3MB
      res.on('data', (c) => {
        totalSize += c.length;
        if (totalSize > MAX_SIZE) {
          req.destroy(new Error('File too large'));
          return;
        }
        chunks.push(c);
      });
      res.on('end', () => resolve(Buffer.concat(chunks)));
      res.on('error', reject);
    });
    req.on('error', reject);
    req.setTimeout(120000, () => req.destroy(new Error('Timeout')));
  });
}

async function main() {
  if (!fs.existsSync(OUT_DIR)) fs.mkdirSync(OUT_DIR, { recursive: true });
  for (const [name, rel] of FILES) {
    const url = BASE + rel;
    process.stdout.write(`↓ ${name} ... `);
    try {
      const buf = await download(url);
      fs.writeFileSync(path.join(OUT_DIR, name), buf);
      console.log(`${buf.length} bytes`);
    } catch (e) {
      console.log(`FAIL: ${e.message}`);
    }
  }
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
