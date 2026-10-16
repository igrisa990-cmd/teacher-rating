/* Overlay a completed identity-review retry, preserving every established roster. */
const fs=require('fs'),path=require('path');
function merge({previousRoot,retryRoot,root,expectedStatus='school_identity_needs_review'}){
 if(!['school_identity_needs_review','staff_format_needs_review'].includes(expectedStatus))throw Error('Retry only unresolved identity or format checkpoints');
 if(!previousRoot||!retryRoot||!root||[previousRoot,retryRoot].some(p=>path.resolve(p)===path.resolve(root)))throw Error('Use a distinct output root');
 const report=JSON.parse(fs.readFileSync(path.join(retryRoot,'report.json')));
 if(!report.completeInventoryPass||report.completed!==report.inventory)throw Error('Incomplete retry inventory');
 const files=fs.readdirSync(path.join(retryRoot,'schools')).filter(f=>f.endsWith('.json'));
 if(files.length!==report.inventory)throw Error('Retry checkpoint count mismatch');
 const overlay=[];for(const file of files){const next=JSON.parse(fs.readFileSync(path.join(retryRoot,'schools',file))),previous=JSON.parse(fs.readFileSync(path.join(previousRoot,'schools',file)));
  if(file!==next.ogrn+'.json'||next.ogrn!==previous.ogrn||next.registryWebsite!==previous.registryWebsite)throw Error('Registry association changed');
  if(previous.status!==expectedStatus||previous.rows.length)throw Error('Do not replace an established roster');
  if(!next.checkedAt||next.status==='pending'||!Array.isArray(next.rows))throw Error('Unfinished checkpoint');overlay.push(file);
 }
 const target=path.join(root,'schools');if(fs.existsSync(target)&&fs.readdirSync(target).length)throw Error('Output must be empty');fs.mkdirSync(target,{recursive:true});
 const originalFiles=fs.readdirSync(path.join(previousRoot,'schools')).filter(f=>f.endsWith('.json'));
 for(const file of originalFiles)fs.copyFileSync(path.join(previousRoot,'schools',file),path.join(target,file));
 for(const file of overlay)fs.copyFileSync(path.join(retryRoot,'schools',file),path.join(target,file));
 const result={preparedAt:new Date().toISOString(),originalCheckpoints:originalFiles.length,retriedCheckpoints:overlay.length,previousStatus:expectedStatus,completeRetryPass:true,method:'Only previously unresolved identity/format checkpoints without staff rows are replaced by freshly checked registry-linked sources. Every established HTML/document roster and its original check date is preserved. Full license, association and duplicate-roster validation follows before staging.'};
 fs.writeFileSync(path.join(root,'retry-merge-report.json'),JSON.stringify(result,null,2));console.log(JSON.stringify(result));return result;
}
module.exports={merge};if(require.main===module){const a=process.argv.slice(2),get=k=>a.includes(k)?a[a.indexOf(k)+1]:undefined;try{merge({previousRoot:get('--previous-root'),retryRoot:get('--retry-root'),root:get('--root'),expectedStatus:get('--status')})}catch(e){console.error(e.message);process.exitCode=1}}
