const https = require('https');

function list(path) {
  return new Promise((resolve, reject) => {
    const url = `https://api.github.com/repos/chinese-poetry/chinese-poetry/contents/${path}`;
    https.get(url, { headers: { 'User-Agent': 'node' } }, (res) => {
      let data = '';
      res.on('data', (c) => (data += c));
      res.on('end', () => {
        try {
          const json = JSON.parse(data);
          if (Array.isArray(json)) {
            resolve(json);
          } else {
            resolve({ error: json.message || JSON.stringify(json).slice(0, 200) });
          }
        } catch (e) {
          reject(new Error(`Parse: ${data.slice(0, 200)}`));
        }
      });
    }).on('error', reject);
  });
}

async function main() {
  for (const d of ['全唐诗', '蒙学', '水墨唐诗', '诗经', '楚辞', '曹操诗集']) {
    try {
      const sub = await list(encodeURIComponent(d));
      if (Array.isArray(sub)) {
        const files = sub.map((x) => x.name).slice(0, 8);
        console.log(`${d}/:`, files);
      } else {
        console.log(`${d}/ ERR:`, sub);
      }
    } catch (e) {
      console.log(`${d}/ EXC:`, e.message);
    }
  }
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
