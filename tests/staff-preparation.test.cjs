const fs=require('fs'),path=require('path'),os=require('os'),assert=require('assert/strict'),zlib=require('zlib'),{prepare}=require('../scripts/prepare-national-staff.cjs');
const tmp=fs.mkdtempSync(path.join(os.tmpdir(),'staff-preparation-')),ogrn='1020300977620',root=tmp+'/cohort',input=tmp+'/seeds.ndjson',licenseInput=tmp+'/licenses.ndjson',output=tmp+'/snapshot';
fs.mkdirSync(root+'/schools',{recursive:true});
const seed={ogrn,region:'Тестовый регион',website:'https://school.example/',websiteSource:'government_platform_exact_licensed_identity'};
fs.writeFileSync(input,JSON.stringify(seed)+'\n');fs.writeFileSync(licenseInput,JSON.stringify({ogrn})+'\n');
const row=(name,subject,evidence,source='staff')=>({name,subject,subjects:[subject],role:'Учитель, русский язык',subject_evidence:evidence,source_url:'https://school.example/'+source,identity_url:'https://school.example/common',identity_method:'explicit_ogrn',source_sha256:'a'.repeat(64),checked_at:'2026-10-18T10:00:00Z'});
const rows=[row('Иванова Анна Петровна','Математика','explicit_discipline'),row('Иванова Анна Петровна','Химия','published_teaching_position','summary'),row('Петрова Мария Игоревна','Русский язык','explicit_discipline'),row('Сидорова Ольга Петровна','Физика','explicit_discipline'),row('Сидорова Ольга Петровна','Химия','explicit_discipline','other')];
fs.writeFileSync(root+'/schools/'+ogrn+'.json',JSON.stringify({ogrn,rows,status:'prepared',website:seed.website,registryWebsite:seed.website,evidence:[]}));
try{
 const result=prepare({root,input,licenseInput,output});assert.equal(result.length,2);assert.equal(result.find(r=>r.name.startsWith('Иванова')).subject,'Математика');assert(!result.some(r=>r.name.startsWith('Сидорова')));
 const report=JSON.parse(fs.readFileSync(output+'-report.json'));assert(report.completeInventoryPass);assert(report.source.includes('government-platform'));assert.equal(report.rejectedPeople,1);assert.deepEqual(zlib.gunzipSync(fs.readFileSync(output+'.ndjson.gz')).toString('utf8').trim().split('\n').map(JSON.parse),result);
 fs.writeFileSync(input,JSON.stringify(seed)+'\n'+JSON.stringify(seed)+'\n');assert.throws(()=>prepare({root,input,licenseInput,output}),/one verified source per organization/);
 console.log('PASS: explicit cohort seeds and teaching-role punctuation; single-source fields, conflicting disciplines held and duplicate organization seeds rejected');
}finally{assert(path.resolve(tmp).startsWith(path.resolve(os.tmpdir())+path.sep+'staff-preparation-'));fs.rmSync(tmp,{recursive:true,force:true})}
