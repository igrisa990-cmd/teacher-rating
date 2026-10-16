const fs=require('fs'),path=require('path'),zlib=require('zlib'),crypto=require('crypto'),assert=require('assert/strict');
const {stage}=require('../scripts/stage-catalog-snapshot.cjs'),{diff}=require('../scripts/catalog-snapshot-diff.cjs');
fs.mkdirSync('work',{recursive:true});const root=fs.mkdtempSync(path.resolve('work','incomplete-snapshot-')),file=path.join(root,'incomplete.ndjson.gz'),raw=Buffer.from('{"school_ogrn":"1020300977620","name":"Иванова Анна Петровна"}\n'),gzip=zlib.gzipSync(raw),hash=b=>crypto.createHash('sha256').update(b).digest('hex');
fs.writeFileSync(file,gzip);fs.writeFileSync(file.replace('.ndjson.gz','-report.json'),JSON.stringify({completeInventoryPass:false,teachers:1,processedSha256:hash(raw),gzipSha256:hash(gzip)}));
assert.throws(()=>stage('staff',file,'test-incomplete'),/Incomplete inventory snapshot/);assert.throws(()=>diff('staff',file,file,path.join(root,'delta')),/Incomplete inventory snapshot/);
fs.unlinkSync(file);fs.unlinkSync(file.replace('.ndjson.gz','-report.json'));fs.rmdirSync(root);console.log('PASS: incomplete inventory snapshots cannot produce deltas or database staging files');
