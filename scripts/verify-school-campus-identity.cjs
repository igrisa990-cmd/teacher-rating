/* Campus-only identity checks. They never relax teacher affiliation verification. */
const {parse}=require('./staff-parser/node_modules/parse5'),{matchSchoolIdentity}=require('./collect-national-staff.cjs'),{normalizeAddress}=require('./parse-school-campuses.cjs');
function verifyCampusIdentity(html,seed,license){
 if(!license||license.ogrn!==seed.ogrn)return null;
 const tree=parse(html),nodes=[],stack=[tree];while(stack.length){const n=stack.pop();if(nodes.length>=150000)throw Error('html_node_limit');nodes.push(n);stack.push(...(n.childNodes||[]).slice().reverse())}
 const plain=n=>{const out=[],stack=[n];while(stack.length){const n=stack.pop();if(['script','style','template'].includes(n.tagName))continue;if(n.nodeName==='#text')out.push(n.value);else stack.push(...(n.childNodes||[]).slice().reverse())}return out.join(' ').replace(/\s+/g,' ').trim()},attr=(n,k)=>n.attrs?.find(a=>a.name===k)?.value||'';
 const licenseLinks=nodes.filter(n=>n.tagName==='a').map(n=>{try{return new URL(attr(n,'href'))}catch{return null}}).filter(u=>u?.hostname==='islod.obrnadzor.gov.ru'&&/^\/(?:rlic\/details\/[a-f0-9-]{36}|view\/\d+)\/?$/i.test(u.pathname));
 const ids=new Set(licenseLinks.map(u=>u.pathname.replace(/\/$/,'').toLowerCase()));
 if(ids.size===1&&(ids.has('/rlic/details/'+license.id.toLowerCase())||license.schoolGuid&&ids.has('/view/'+license.schoolGuid.split(':')[0])))return 'official_license_record_link';
 const old=matchSchoolIdentity(html,seed);if(old)return old.method;
 const fields=label=>nodes.filter(n=>attr(n,'class').split(/\s+/).includes('content_doc__table_label')&&label.test(plain(n))).map(n=>{const siblings=n.parentNode?.childNodes||[],next=siblings.slice(siblings.indexOf(n)+1).find(n=>n.tagName);return next?plain(next):''});
 const names=[...nodes.filter(n=>attr(n,'itemprop').toLowerCase()==='fullname').map(plain),...fields(/^Полное наименование образовательной организации$/i)],addresses=[...nodes.filter(n=>attr(n,'itemprop').toLowerCase()==='address').map(plain),...fields(/^Место нахождения образовательной организации(?:\s*\(|$)/i)];
 const compact=v=>String(v).normalize('NFKC').toLowerCase().replaceAll('ё','е').replace(/[^\p{L}\p{N}]/gu,''),address=v=>compact(normalizeAddress(v));
 if(names.some(n=>compact(n)===compact(license.name))&&addresses.some(a=>address(a)===address(license.address)))return 'exact_name_address';
 return null;
}
module.exports={verifyCampusIdentity};
