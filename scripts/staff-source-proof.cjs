/* Recover a decoded cache only when its original response checksum proves every byte. */
const crypto=require('crypto');
const hash=bytes=>crypto.createHash('sha256').update(bytes).digest('hex');
let windows1251;
function encodeWindows1251(value){
 if(!windows1251){windows1251=new Map();const decoder=new TextDecoder('windows-1251',{fatal:true});for(let i=0;i<256;i++){try{const char=decoder.decode(Uint8Array.of(i));if(char.length===1&&!windows1251.has(char))windows1251.set(char,i)}catch{}}}
 const bytes=Buffer.allocUnsafe(value.length);let offset=0;for(const char of value){const byte=windows1251.get(char);if(byte===undefined)return null;bytes[offset++]=byte}return bytes.subarray(0,offset);
}
function proveCachedSource(cache,expectedSha256){
 if(!Buffer.isBuffer(cache)||cache.length>15000000||!/^[a-f0-9]{64}$/.test(expectedSha256))return null;
 const html=cache.toString('utf8');if(cache.length<=5000000&&hash(cache)===expectedSha256)return{html,bytes:cache,encoding:'utf-8',recovered:false};
 const candidates=[{bytes:Buffer.concat([Buffer.from([0xef,0xbb,0xbf]),cache]),encoding:'utf-8-bom'}];
 const legacy=encodeWindows1251(html);if(legacy)candidates.push({bytes:legacy,encoding:'windows-1251'});
 const little=Buffer.from(html,'utf16le'),big=Buffer.from(little).swap16();candidates.push({bytes:little,encoding:'utf-16le'},{bytes:Buffer.concat([Buffer.from([0xff,0xfe]),little]),encoding:'utf-16le-bom'},{bytes:big,encoding:'utf-16be'},{bytes:Buffer.concat([Buffer.from([0xfe,0xff]),big]),encoding:'utf-16be-bom'});
 for(const candidate of candidates)if(candidate.bytes.length<=5000000&&hash(candidate.bytes)===expectedSha256)return{html,...candidate,recovered:true};return null;
}
function readCachedSource(file,expectedSha256){try{const fs=require('fs');if(fs.statSync(file).size>16000000)return null;const buffer=fs.readFileSync(file),cache=file.endsWith('.gz')?require('zlib').gunzipSync(buffer,{maxOutputLength:15000000}):buffer;return proveCachedSource(cache,expectedSha256)}catch{return null}}
module.exports={proveCachedSource,readCachedSource};
