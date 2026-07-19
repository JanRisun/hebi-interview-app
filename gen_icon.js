// 生成合法的 72x72 PNG 图标（纯色 #185FA5），供鸿蒙工程引用
const zlib = require('zlib');
const fs = require('fs');
const path = require('path');
const W = 72, H = 72;
function crc32(buf) { let c = ~0; for (let i = 0; i < buf.length; i++) { c ^= buf[i]; for (let k = 0; k < 8; k++) c = (c >>> 1) ^ (0xEDB88320 & -(c & 1)); } return ~c >>> 0; }
function chunk(type, data) {
  const len = Buffer.alloc(4); len.writeUInt32BE(data.length, 0);
  const t = Buffer.from(type, 'ascii');
  const crc = Buffer.alloc(4); crc.writeUInt32BE(crc32(Buffer.concat([t, data])), 0);
  return Buffer.concat([len, t, data, crc]);
}
const raw = Buffer.alloc((W * 4 + 1) * H);
let p = 0;
for (let y = 0; y < H; y++) { raw[p++] = 0; for (let x = 0; x < W; x++) { raw[p++] = 0x18; raw[p++] = 0x5F; raw[p++] = 0xA5; raw[p++] = 0xFF; } }
const ihdr = Buffer.alloc(13);
ihdr.writeUInt32BE(W, 0); ihdr.writeUInt32BE(H, 4); ihdr[8] = 8; ihdr[9] = 6;
const idat = zlib.deflateSync(raw);
const png = Buffer.concat([
  Buffer.from([137, 80, 78, 71, 13, 10, 26, 10]),
  chunk('IHDR', ihdr), chunk('IDAT', idat), chunk('IEND', Buffer.alloc(0))
]);
const dirs = [
  'AppScope/resources/base/media',
  'entry/src/main/resources/base/media'
];
dirs.forEach(d => {
  fs.mkdirSync(path.join(__dirname, d), { recursive: true });
  fs.writeFileSync(path.join(__dirname, d, 'app_icon.png'), png);
});
console.log('icons written:', png.length, 'bytes');
