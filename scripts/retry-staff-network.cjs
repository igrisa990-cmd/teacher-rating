/* One complete pass over the remaining licensed, empty network/DNS checkpoints.
 * Every fresh page still passes the normal DNS, TLS, robots and organization checks. */
const fs=require('fs'),path=require('path'),{collect}=require('./collect-national-staff.cjs'),{networkCheckpoint}=require('./merge-staff-retry.cjs');
async function retry({previousRoot,root,input='work/accreditation-xml/staff-seeds.ndjson',licenseInput='work/license-xml-20261015/active-general.ndjson',workers=24}){
 if(!previousRoot||!root||path.resolve(previousRoot)===path.resolve(root))throw Error('Use distinct source and output roots');
 const seeds=fs.readFileSync(input,'utf8').trim().split('\n').map(JSON.parse),licensed=new Set(fs.readFileSync(licenseInput,'utf8').trim().split('\n').map(JSON.parse).map(r=>r.ogrn)),pending=[],outcomes={};
 for(const seed of seeds){const r=JSON.parse(fs.readFileSync(path.join(previousRoot,'schools',seed.ogrn+'.json')));if(r.ogrn!==seed.ogrn||r.registryWebsite!==seed.website)throw Error('Registry association changed');if(licensed.has(seed.ogrn)&&networkCheckpoint(r)){pending.push(seed);outcomes[r.status]=(outcomes[r.status]||0)+1}}
 if(!pending.length)throw Error('No remaining eligible network checkpoints');
 fs.mkdirSync(root,{recursive:true});const queue=path.join(root,'retry-seeds.ndjson');fs.writeFileSync(queue,pending.map(JSON.stringify).join('\n')+'\n');
 const selection={preparedAt:new Date().toISOString(),previousInventory:seeds.length,retryInventory:pending.length,previousOutcomes:outcomes,scope:'Every remaining empty transient-network or DNS checkpoint with a current general-education license. Existing rosters, restrictions, certificate failures and unresolved source identities are retained. New data must pass fresh organization validation.'};
 fs.writeFileSync(path.join(root,'selection-report.json'),JSON.stringify(selection,null,2));console.log(JSON.stringify(selection));return collect({input:queue,root,workers,savePages:true});
}
module.exports={retry};if(require.main===module){const a=process.argv.slice(2),get=k=>a.includes(k)?a[a.indexOf(k)+1]:undefined;retry({previousRoot:get('--previous-root'),root:get('--root'),input:get('--input'),licenseInput:get('--license-input'),workers:Number(get('--workers')||24)}).catch(e=>{console.error(e.message);process.exitCode=1})}
