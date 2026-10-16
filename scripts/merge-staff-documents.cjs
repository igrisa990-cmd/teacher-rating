/* Add validated document rows to a separate copy of the resumable inventory. */
const fs=require('fs'),path=require('path'),crypto=require('crypto');
const {normalize}=require('./collect-national-staff.cjs');
function merge({previousRoot,documentRoot,root}){
 if(!previousRoot||!documentRoot||!root||path.resolve(root)===path.resolve(previousRoot))throw Error('Use a distinct output root');
 const directory=path.join(root,'schools');fs.mkdirSync(directory,{recursive:true});
 for(const f of fs.readdirSync(path.join(previousRoot,'schools')).filter(f=>f.endsWith('.json'))){const target=path.join(directory,f);if(!fs.existsSync(target))fs.copyFileSync(path.join(previousRoot,'schools',f),target)}
 const groups=new Map();let validatedDocuments=0;
 for(const f of fs.readdirSync(path.join(documentRoot,'parsed')).filter(f=>f.endsWith('.json'))){const d=JSON.parse(fs.readFileSync(path.join(documentRoot,'parsed',f)));
  if(!['prepared','prepared_partial'].includes(d.status)||d.documentParserVersion<2||!d.rows.length)continue;
  if(crypto.createHash('sha256').update(fs.readFileSync(d.file)).digest('hex')!==d.sha256||!/^\w{64}$/.test(d.identity_sha256||''))throw Error('Invalid document proof');
  if(d.rows.some(r=>r.school_ogrn!==d.school_ogrn||r.source_sha256!==d.sha256||r.source_url!==d.source_url||r.identity_url!==d.identity_url))throw Error('Document/source association mismatch');
  const list=groups.get(d.school_ogrn)||[];list.push(d);groups.set(d.school_ogrn,list);validatedDocuments++;
 }
 let teacherRows=0;
 for(const [ogrn,documents] of groups){const source=path.join(previousRoot,'schools',ogrn+'.json');if(!fs.existsSync(source))throw Error('Unknown school checkpoint');const school=JSON.parse(fs.readFileSync(source));
  if(school.status!=='staff_format_needs_review'||school.rows.length)throw Error('Do not replace an existing HTML roster');
  const people=new Map();
  for(const d of documents)for(const r of d.rows){const key=normalize(r.name);const old=people.get(key);if(old){old.subjects=[...new Set([...old.subjects,r.subject].filter(Boolean))];old.subject=old.subjects.join('; ')}else people.set(key,{...r,subjects:r.subject?[r.subject]:[]})}
  school.htmlCheckedAt=school.checkedAt;school.checkedAt=documents.map(d=>d.downloadedAt).sort().at(-1);school.rows=[...people.values()];school.status='partial_staff_pages';school.documentParserVersion=3;
  school.documentEvidence=documents.map(d=>({url:d.source_url,sha256:d.sha256,checkedAt:d.downloadedAt,identitySha256:d.identity_sha256,partialTables:d.partial_tables}));
  school.documentCoverage='Validated current-year tables only. Other documents, scanned pages and inaccessible sources may leave the roster incomplete.';
  fs.writeFileSync(path.join(directory,ogrn+'.json'),JSON.stringify(school));teacherRows+=school.rows.length;
 }
 const report={preparedAt:new Date().toISOString(),validatedDocuments,schools:groups.size,teacherRows,method:'Separate inventory copy; original HTML checks retained. Deduplicate full names within an organization, merge only explicit published subjects, then apply the existing current-license and cross-organization duplicate-roster guards.'};
 fs.writeFileSync(path.join(root,'document-merge-report.json'),JSON.stringify(report,null,2));console.log(JSON.stringify(report));return report;
}
module.exports={merge};if(require.main===module){const a=process.argv.slice(2),get=k=>a[a.indexOf(k)+1];try{merge({previousRoot:get('--previous-root'),documentRoot:get('--document-root'),root:get('--root')})}catch(e){console.error(e.message);process.exitCode=1}}
