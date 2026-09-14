const https = require('https');

function list(path) {
  return new Promise((resolve, reject) => {
    const url = `https://api.github.com/repos/chinese-poetry/chinese-poetry/contents/${path}?per_page=100`;
    https.get(url, { headers: { 'User-Agent': 'node' } }, (res) => {
      let data = '';
      res.on('data', (c) => (data += c));
      res.on('end', () => {
        try {
          const json = JSON.parse(data);
          if (Array.isArray(json)) resolve(json);
          else resolve({ error: json.message || JSON.stringify(json).slice(0, 200) });
        } catch (e) { reject(e); }
      });
    }).on('error', reject);
  });
}

async function main() {
  const all = await list(encodeURIComponent('全唐诗'));
  if (Array.isArray(all)) {
    const tang = all.filter(x => x.name.startsWith('poet.tang.')).map(x => x.name);
    const song = all.filter(x => x.name.startsWith('poet.song.')).map(x => x.name);
    console.log('全唐诗唐诗文件:', tang);
    console.log('全唐诗宋诗文件:', song.slice(0, 20), '...');
  }
  const songCi = await list(encodeURIComponent('宋词'));
  if (Array.isArray(songCi)) {
    const ci = songCi.filter(x => x.name.startsWith('ci.')).map(x => x.name);
    console.log('宋词文件:', ci);
  }
}

main().catch(console.error);
