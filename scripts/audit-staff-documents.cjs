/* Inventory explicit same-origin staff documents from identity-verified HTML.
 * This does not parse personnel, refresh checked_at, or publish PDF contents. */
const fs=require('fs'),path=require('path'),crypto=require('crypto');
const {links,verifyIdentity}=require('./collect-national-staff.cjs');
function audit({root,output}){
 const seeds=new Map(fs.readFileSync('work/accreditation-xml/staff-seeds.ndjson','utf8').trim().split('\n').map(JSON.parse).map(s=>[s.ogrn,s]));
 const hash=s=>crypto.createHash('sha256').update(s).digest('hex'),documents=[];
 let pending=0,identityCacheMissing=0,identityMismatch=0;
 for(const f of fs.readdirSync(path.join(root,'schools')).filter(f=>f.endsWith('.json'))){
  const s=JSON.parse(fs.readFileSync(path.join(root,'schools',f)));if(s.status!=='staff_format_needs_review'||!s.identityMethod)continue;pending++;
  const identityFile=path.join(root,'pages',hash(s.identityUrl)+'.html');
  if(!fs.existsSync(identityFile)){identityCacheMissing++;continue}
  if(!seeds.has(s.ogrn)||!verifyIdentity(fs.readFileSync(identityFile,'utf8'),seeds.get(s.ogrn))){identityMismatch++;continue}
  const seen=new Set();
  for(const evidence of s.evidence||[]){const file=path.join(root,'pages',hash(evidence.url)+'.html');if(!fs.existsSync(file))continue;
   for(const link of links(fs.readFileSync(file,'utf8'),evidence.url)){
    let basename;try{basename=decodeURIComponent(new URL(link.url).pathname.split('/').at(-1))}catch{continue}
    const format=basename.match(/\.(pdf|docx?|xlsx?)$/i)?.[1]?.toLowerCase(),description=basename+' '+link.label;
    if(!format||!/(?:педагог|учител|состав|сотрудник|pedagog|sostav|staff)/i.test(description)||/(?:здоров|зарплат|snils|снилс|паспорт|медицин|payroll)/i.test(description)||new URL(link.url).origin!==new URL(s.identityUrl).origin||seen.has(link.url))continue;
    seen.add(link.url);const years=[...description.matchAll(/(?:^|\D)(20\d{2})(?!\d)/g)].map(m=>Number(m[1]));
    documents.push({school_ogrn:s.ogrn,url:link.url,label:link.label,format,identity_url:s.identityUrl,html_checked_at:s.checkedAt,status:format==='doc'?'legacy_binary_word':years.length&&Math.max(...years)<2026?'explicitly_older_document':years.some(y=>y>=2026)?'current_year_candidate':'date_requires_review'});
   }
  }
 }
 const report={preparedAt:new Date().toISOString(),pendingIdentityVerifiedSites:pending,identityCacheMissing,identityMismatch,documentSchools:new Set(documents.map(d=>d.school_ogrn)).size,documentLinks:documents.length,formats:{},outcomes:{},coverage:'Inventory of links only; upload-folder dates do not prove roster currency. Documents need date, table layout, teaching-role and same-row identity validation before import. Cached HTML check times are retained. No document personnel were imported by this audit.'};
 for(const d of documents){report.formats[d.format]=(report.formats[d.format]||0)+1;report.outcomes[d.status]=(report.outcomes[d.status]||0)+1}
 fs.writeFileSync(output+'.ndjson',documents.map(JSON.stringify).join('\n')+'\n');fs.writeFileSync(output+'-report.json',JSON.stringify(report,null,2));console.log(JSON.stringify(report));return report;
}
module.exports={audit};if(require.main===module){const args=process.argv.slice(2),get=k=>args[args.indexOf(k)+1];audit({root:get('--root'),output:get('--output')})}
