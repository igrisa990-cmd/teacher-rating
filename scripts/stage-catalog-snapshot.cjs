/* Prepare auditable SQL files only. No network, database credentials or automatic publication. */
const fs=require('fs'),path=require('path'),zlib=require('zlib'),crypto=require('crypto');
const hash=b=>crypto.createHash('sha256').update(b).digest('hex'),quote=s=>"'"+String(s).replaceAll("'","''")+"'";
function stage(kind,file,run){
 if(!['license','staff'].includes(kind)||!file?.endsWith('.ndjson.gz')||!/^[a-z0-9-]{5,80}$/.test(run||''))throw Error('Usage: node scripts/stage-catalog-snapshot.cjs license|staff data/registry/SNAPSHOT.ndjson.gz RUN-KEY');
 const report=JSON.parse(fs.readFileSync(file.replace('.ndjson.gz','-report.json'))),gzip=fs.readFileSync(file),raw=zlib.gunzipSync(gzip),rows=raw.toString('utf8').trim().split('\n').map(JSON.parse),expected=kind==='staff'?report.teachers:report.eligibleOrganizations??report.eligible;
 if(hash(raw)!==report.processedSha256||hash(gzip)!==report.gzipSha256||rows.length!==expected)throw Error('Snapshot checksum/count mismatch');
 const keys=rows.map(r=>kind==='license'?r.registry_ogrn:r.school_ogrn+'|'+r.name.toLocaleLowerCase('ru').replaceAll('ё','е').replace(/[^\p{L}\p{N}]+/gu,' ').trim());if(new Set(keys).size!==rows.length)throw Error('Duplicate import identity');
 const root=path.join('work','catalog-stage',run);fs.mkdirSync(root,{recursive:true});
 const source=kind==='license'?report.download?.source||report.source?.source:'https://isga.obrnadzor.gov.ru/accredreestr/opendata',snapshotHash=report.download?.sha256||report.processedSha256;
 fs.writeFileSync(path.join(root,'000-run.sql'),`insert into private.catalog_import_runs(run_key,source_url,snapshot_sha256,expected_rows) values(${quote(run)},${quote(source)},${quote(snapshotHash)},${expected}) on conflict(run_key) do nothing;\n`);
 for(let i=0;i<rows.length;i+=2000){const json=quote(JSON.stringify(rows.slice(i,i+2000))),sql=kind==='license'?`insert into private.catalog_license_stage(run_key,ogrn,payload) select ${quote(run)},p->>'registry_ogrn',p from jsonb_array_elements(${json}::jsonb)p on conflict(run_key,ogrn) do update set payload=excluded.payload;`:`insert into private.catalog_staff_stage(run_key,school_ogrn,name_key,payload) select ${quote(run)},p->>'school_ogrn',private.staff_name_key(p->>'name'),p from jsonb_array_elements(${json}::jsonb)p on conflict(run_key,school_ogrn,name_key) do update set payload=excluded.payload;`;fs.writeFileSync(path.join(root,String(i/2000+1).padStart(3,'0')+'-stage.sql'),sql+'\n');}
 fs.writeFileSync(path.join(root,'999-apply.sql'),`select private.apply_${kind}_snapshot(${quote(run)});\n`);console.log(JSON.stringify({root,rows:rows.length,processedSha256:hash(raw)}));return root;
}
module.exports={stage};if(require.main===module)try{stage(...process.argv.slice(2))}catch(e){console.error(e.message);process.exitCode=1}
