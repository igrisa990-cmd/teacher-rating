/* Produce reviewable admin SQL from a checksummed extract; no credentials or remote writes. */
const fs=require('fs'),path=require('path'),crypto=require('crypto'),zlib=require('zlib'),{validOgrn}=require('./import-russian-schools.cjs');
const quote=s=>"'"+String(s).replaceAll("'","''")+"'";
function batchSql(rows,run){return `insert into private.catalog_accreditation_stage(run_key,ogrn,payload) select ${quote(run)},r->>'accreditation_ogrn',r from jsonb_array_elements(${quote(JSON.stringify(rows))}::jsonb)r on conflict(run_key,ogrn) do update set payload=excluded.payload;\n`}
function prepare(input='data/registry/20261013-accredited-schools',output='work/accreditation-stage'){
 const report=JSON.parse(fs.readFileSync(input+'-report.json')),compressed=fs.readFileSync(input+'.ndjson.gz'),raw=zlib.gunzipSync(compressed);
 const hash=b=>crypto.createHash('sha256').update(b).digest('hex');if(hash(compressed)!==report.gzipSha256||hash(raw)!==report.processedSha256)throw Error('Snapshot checksum mismatch');
 const rows=raw.toString('utf8').trim().split('\n').map(JSON.parse),seen=new Set();if(rows.length!==report.eligibleOrganizations)throw Error('Snapshot count mismatch');
 for(const r of rows){if(!validOgrn(r.accreditation_ogrn)||seen.has(r.accreditation_ogrn)||r.accreditation_url!=='https://isga.obrnadzor.gov.ru/accredreestr/details/'+r.accreditation_id||!r.region||!r.city||!r.address)throw Error('Invalid snapshot identity');seen.add(r.accreditation_ogrn)}
 const run='accreditation-'+report.processedSha256.slice(0,16);fs.mkdirSync(output,{recursive:true});fs.writeFileSync(path.join(output,'000-init.sql'),`insert into private.catalog_import_runs(run_key,source_url,snapshot_sha256,expected_rows) values(${quote(run)},${quote(report.download.source)},${quote(report.download.sha256)},${rows.length}) on conflict(run_key) do nothing;\n`);
 for(let offset=0,i=1;offset<rows.length;offset+=500,i++)fs.writeFileSync(path.join(output,String(i).padStart(3,'0')+'-stage.sql'),batchSql(rows.slice(offset,offset+500),run));
 fs.writeFileSync(path.join(output,'999-apply.sql'),`select private.apply_accreditation_snapshot(${quote(run)});\n`);console.log(JSON.stringify({run,rows:rows.length,output}));
}
module.exports={batchSql,prepare};if(require.main===module)prepare(process.argv[2],process.argv[3]);
