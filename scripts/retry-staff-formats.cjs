/* Retry the finite review inventory; retain earlier verified checkpoints. */
const fs=require('fs'),path=require('path'),{collect}=require('./collect-national-staff.cjs');
async function retry({previousRoot,root,input='work/accreditation-xml/staff-seeds.ndjson',workers=24,savePages=false}){
 if(!previousRoot||!root||path.resolve(previousRoot)===path.resolve(root))throw Error('Use distinct --previous-root and --root');
 fs.mkdirSync(path.join(root,'schools'),{recursive:true});const seeds=fs.readFileSync(input,'utf8').trim().split('\n').map(JSON.parse),pending=[];
 for(const seed of seeds){const original=path.join(previousRoot,'schools',seed.ogrn+'.json'),saved=JSON.parse(fs.readFileSync(original)),target=path.join(root,'schools',seed.ogrn+'.json');if(saved.status==='staff_format_needs_review'&&saved.identityMethod)pending.push(seed);else if(!fs.existsSync(target))fs.copyFileSync(original,target)}
 const inventory=path.join(root,'retry-seeds.ndjson');fs.writeFileSync(inventory,pending.map(JSON.stringify).join('\n')+'\n');console.log(JSON.stringify({previousInventory:seeds.length,retryInventory:pending.length}));if(!pending.length)return{completed:0};return collect({input:inventory,root,workers,savePages});
}
module.exports={retry};if(require.main===module){const args=process.argv.slice(2),get=key=>args.includes(key)?args[args.indexOf(key)+1]:undefined;retry({previousRoot:get('--previous-root'),root:get('--root'),input:get('--input'),workers:Number(get('--workers')||24),savePages:args.includes('--save-pages')}).catch(e=>{console.error(e.message);process.exit(1)})}
