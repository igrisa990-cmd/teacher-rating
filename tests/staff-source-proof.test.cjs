const assert=require('assert/strict'),crypto=require('crypto'),{proveCachedSource}=require('../scripts/staff-source-proof.cjs'),sha=b=>crypto.createHash('sha256').update(b).digest('hex');
const original=Buffer.from('d3f7e8f2e5ebfc','hex'),cache=Buffer.from('Учитель','utf8');
let proof=proveCachedSource(cache,sha(original));assert.equal(proof.encoding,'windows-1251');assert.deepEqual(proof.bytes,original);assert.equal(proof.html,'Учитель');assert.equal(proof.recovered,true);
assert.equal(proveCachedSource(Buffer.from('Учитель!'),sha(original)),null,'Changed decoded text cannot satisfy the original response checksum');
proof=proveCachedSource(cache,sha(cache));assert.equal(proof.recovered,false);assert.equal(proof.encoding,'utf-8');
const bom=Buffer.concat([Buffer.from([0xef,0xbb,0xbf]),cache]);assert.deepEqual(proveCachedSource(cache,sha(bom)).bytes,bom);
const wide=Buffer.concat([Buffer.from([0xff,0xfe]),Buffer.from('Учитель','utf16le')]);assert.equal(proveCachedSource(cache,sha(wide)).encoding,'utf-16le-bom');
assert.equal(proveCachedSource(cache,'0'.repeat(64)),null);assert.equal(proveCachedSource(cache,'bad'),null);assert.equal(proveCachedSource(Buffer.alloc(5000001),'0'.repeat(64)),null);
console.log('PASS: legacy/BOM cache recovery requires an exact original-response SHA256; modified or unsupported bytes remain unproven');
