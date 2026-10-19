const assert=require('assert/strict'),{verifyIdentity}=require('../scripts/collect-national-staff.cjs');
const seed={ogrn:'1020300977620',name:'Муниципальная школа',address:'',city:''};
for(const prefix of ['ОГРН) : ','ОГРН. ','ОГРН — ','ОГРН \u200b'])assert.equal(verifyIdentity(prefix+seed.ogrn,seed),'explicit_ogrn');
assert.equal(verifyIdentity('ОГРН) : 1027700132195',seed),null,'A differently punctuated contradictory organization number is held');
assert.equal(verifyIdentity('ОГРН ИНН 1020300977620',seed),null,'The parser cannot skip another identifier label');
assert.equal(verifyIdentity('ОГРН) : 10203009776200',seed),null);assert.equal(verifyIdentity('ОГРН) : 1020300977621',seed),null);
console.log('PASS: explicit organization IDs tolerate label punctuation/zero-width formatting; checksums and contradictory identifier holds remain');
