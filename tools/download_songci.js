// 单独下载宋词分卷
const https = require('https');
const fs = require('fs');
const path = require('path');

const OUT_DIR = __dirname;
const BASE = 'https://cdn.jsdelivr.net/gh/chinese-poetry/chinese-poetry@master/';

const FILES = [
  ['ci.song.1000.json', '宋词/ci.song.1000.json'],
  ['ci.song.2000.json', '宋词/ci.song.2000.json'],
  ['ci.song.3000.json', '宋词/ci.song.3000.json'],
  ['ci.song.4000.json', '宋词/ci.song.4000.json'],
  ['ci.song.5000.json', '宋词/ci.song.5000.json'],
];

function download(url) {
  return new Promise((resolve, reject) => {
    const req = https.get(url, { headers: { 'User-Agent': 'node-fetch' } }, (res) => {
      if (res.statusCode === 301 || res.statusCode === 302) return download(res.headers.location).then(resolve, reject);
      if (res.statusCode !== 200) return reject(new Error(`HTTP ${res.statusCode} for ${url}`));
      const chunks = [];
      let total = 0;
      const MAX = 3 * 1024 * 1024;
      res.on('data', (c) => { total += c.length; if (total > MAX) { req.destroy(new Error('too large')); return; } chunks.push(c); });
      res.on('end', () => resolve(Buffer.concat(chunks)));
      res.on('error', reject);
    });
    req.on('error', reject);
    req.setTimeout(120000, () => req.destroy(new Error('Timeout')));
  });
}

async function main() {
  for (const [name, rel] of FILES) {
    const url = BASE + encodeURIComponent('宋词') + '/' + rel.split('/').pop();
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

main().catch((e) => { console.error(e); process.exit(1); });
