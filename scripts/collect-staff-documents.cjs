/* A finite document pass. Every origin is sequential, public and robots checked. */
const fs=require('fs'),path=require('path'),crypto=require('crypto'),dns=require('dns').promises;
const {pinnedFetch,safeUrl,publicAddress,parseRobots,robotsAllowed,verifyIdentity}=require('./collect-national-staff.cjs');
const sha=b=>crypto.createHash('sha256').update(b).digest('hex');
async function collect({input='work/staff-document-review.ndjson',root='work/staff-documents-20261016',workers=12,maxSchools=Infinity,includeUndated=false,includeLegacyDoc=false}={}){
 if(!Number.isInteger(workers)||workers<1||workers>16)throw Error('Use 1–16 workers');
 const seeds=new Map(fs.readFileSync('work/accreditation-xml/staff-seeds.ndjson','utf8').trim().split('\n').map(JSON.parse).map(s=>[s.ogrn,s]));
 const groups=new Map();for(const d of fs.readFileSync(input,'utf8').trim().split('\n').map(JSON.parse).filter(d=>((d.status==='current_year_candidate'||includeUndated&&d.status==='date_requires_review')&&['pdf','docx','xlsx','xls'].includes(d.format))||(includeLegacyDoc&&d.format==='doc'&&d.status==='legacy_binary_word'))){const u=safeUrl(d.url),identity=safeUrl(d.identity_url);if(u.origin!==identity.origin||!seeds.has(d.school_ogrn))continue;const group=groups.get(u.origin)||[];group.push(d);groups.set(u.origin,group)}
 const queue=[...groups.values()].slice(0,maxSchools),inventory=queue.reduce((n,g)=>n+g.length,0);fs.mkdirSync(path.join(root,'files'),{recursive:true});fs.mkdirSync(path.join(root,'documents'),{recursive:true});
 const resolver=new dns.Resolver({timeout:2500,tries:1}),startedAt=new Date().toISOString();let completed=0,requests=0,bytes=0;
 async function originBatch(docs){const origin=new URL(docs[0].url).origin,dnsCache=new Map();let blocked=false,groups;
  async function raw(value,isRobots=false){let u=safeUrl(value);for(let redirect=0;redirect<5;redirect++){
   if(u.origin!==origin)throw Error('cross_origin_redirect');if(blocked)throw Error('origin_blocked');
   if(!isRobots&&groups&&!robotsAllowed(groups,u.href))throw Error('robots_disallow');
   let addresses=dnsCache.get(u.hostname);if(!addresses){const answer=await Promise.allSettled([resolver.resolve4(u.hostname),resolver.resolve6(u.hostname)]);addresses=answer.flatMap((r,i)=>r.status==='fulfilled'?r.value.map(address=>({address,family:i?6:4})):[]);if(!addresses.length||addresses.some(a=>!publicAddress(a.address)))throw Error('non_public_address');dnsCache.set(u.hostname,addresses)}
   requests++;const r=await pinnedFetch(u,addresses);if([301,302,303,307,308].includes(r.status)){r.body.destroy();u=safeUrl(r.headers.get('location'),u);continue}
   if([401,403,429].includes(r.status)){blocked=true;r.body.destroy();throw Error('http_'+r.status)}
   if(!r.ok){r.body.destroy();if(isRobots&&r.status===404)return{url:u.href,buffer:Buffer.alloc(0),type:'text/plain'};throw Error('http_'+r.status)}
   const parts=[];let size=0;for await(const b of r.body){size+=b.length;if(size>5000000){r.body.destroy();throw Error('file_too_large')}parts.push(b)}bytes+=size;let buffer=Buffer.concat(parts);const encoding=r.headers.get('content-encoding');if(encoding==='gzip')buffer=require('zlib').gunzipSync(buffer,{maxOutputLength:5000000});if(encoding==='br')buffer=require('zlib').brotliDecompressSync(buffer,{maxOutputLength:5000000});
   const type=r.headers.get('content-type')||'';if(/html|text\/plain/.test(type)&&/access denied|проверка безопасности|доступ ограничен|домен продается/i.test(buffer.toString('utf8').slice(0,20000))){blocked=true;throw Error('source_challenge')}
   return{url:u.href,buffer,type};
  }throw Error('redirect_limit')}
  const identityCache=new Map();let setupError;
  try{groups=parseRobots((await raw(origin+'/robots.txt',true)).buffer.toString('utf8'));if(groups.some(g=>g.delay>10))throw Error('long_crawl_delay')}catch(e){setupError=e.message}
  async function fetchChecked(url){await new Promise(r=>setTimeout(r,Math.max(250,...groups.map(g=>g.delay*1000))));return raw(url)}
  for(const d of docs){const key=sha(d.url),target=path.join(root,'documents',key+'.json');if(fs.existsSync(target)){completed++;continue}
   const result={...d,inventoryStatus:d.status,parserVersion:1,downloadedAt:new Date().toISOString(),status:'pending'};
   try{if(setupError)throw Error(setupError);let identity=identityCache.get(d.identity_url+'|'+d.school_ogrn);
    if(!identity){const p=await fetchChecked(d.identity_url);if(!/html|text\/plain/.test(p.type))throw Error('identity_not_html');const charset=(p.type+' '+p.buffer.subarray(0,3000).toString('latin1')).match(/charset\s*=\s*["']?([\w-]+)/i)?.[1]||'utf-8';let html;try{html=new TextDecoder(charset.replace(/^cp1251$/i,'windows-1251')).decode(p.buffer)}catch{html=p.buffer.toString('utf8')}
     const method=verifyIdentity(html,seeds.get(d.school_ogrn));if(!method)throw Error('school_identity_needs_review');identity={url:p.url,method,sha256:sha(p.buffer)};identityCache.set(d.identity_url+'|'+d.school_ogrn,identity)}
    const p=await fetchChecked(d.url);if(d.format==='pdf'&&!p.buffer.subarray(0,1024).includes(Buffer.from('%PDF-')))throw Error('not_pdf');if(['xls','doc'].includes(d.format)&&!p.buffer.subarray(0,8).equals(Buffer.from('d0cf11e0a1b11ae1','hex')))throw Error('not_ole_document');if(['docx','xlsx'].includes(d.format)&&(p.buffer.length<4||p.buffer.readUInt32LE(0)!==0x04034b50))throw Error('not_ooxml');
    result.file=path.join(root,'files',key+'.'+d.format);result.sha256=sha(p.buffer);result.source_url=p.url;result.identity_url=identity.url;result.identity_method=identity.method;result.identity_sha256=identity.sha256;result.status='downloaded';fs.writeFileSync(result.file,p.buffer);
   }catch(e){result.status=e.message||'network_error'}
   fs.writeFileSync(target+'.tmp',JSON.stringify(result));fs.renameSync(target+'.tmp',target);completed++;
  }
 }
 const timer=setInterval(()=>console.log(JSON.stringify({completed,inventory,requests,megabytes:Math.round(bytes/1e6)})),15000);
 try{await Promise.all(Array.from({length:Math.min(workers,queue.length)},async()=>{while(queue.length)await originBatch(queue.shift())}))}finally{clearInterval(timer)}
 const report={startedAt,finishedAt:new Date().toISOString(),inventory,completed,requests,bytes,outcomes:{}};
 for(const f of fs.readdirSync(path.join(root,'documents'))){const d=JSON.parse(fs.readFileSync(path.join(root,'documents',f)));report.outcomes[d.status]=(report.outcomes[d.status]||0)+1}
 fs.writeFileSync(path.join(root,'download-report.json'),JSON.stringify(report,null,2));console.log(JSON.stringify(report));return report;
}
module.exports={collect};if(require.main===module){const args=process.argv.slice(2),get=(k,v)=>args.includes(k)?args[args.indexOf(k)+1]:v;collect({input:get('--input',undefined),root:get('--root',undefined),workers:Number(get('--workers',12)),maxSchools:Number(get('--max-schools',Infinity)),includeUndated:args.includes('--include-undated'),includeLegacyDoc:args.includes('--include-legacy-doc')}).catch(e=>{console.error(e.message);process.exitCode=1})}
