// 检查 songci 数量 + 进一步下载所需文件
const fs = require('fs');
const path = require('path');

const songci = JSON.parse(fs.readFileSync(path.join(__dirname, 'songci.json'), 'utf-8'));
console.log('宋词三百首：', songci.length, '首');
console.log('示例作者：', [...new Set(songci.map(x => x.author))].slice(0, 10));
console.log('示例词牌：', [...new Set(songci.map(x => x.rhythmic))].slice(0, 5));
