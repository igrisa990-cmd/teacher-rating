/* Read educational places only. A legal address is never promoted to a campus. */
const {parse}=require('./staff-parser/node_modules/parse5');
function normalizeAddress(value){return String(value||'').normalize('NFKC').toLowerCase().replaceAll('ё','е').replace(/(?:^|\D)\d{6}(?=\D|$)/g,' ').replace(/(?<!\p{L})(?:российская федерация|россия)(?!\p{L})/giu,' ').replace(/(?<!\p{L})(?:ул|улиц)[.]?(?=\s)/giu,'улица').replace(/(?:^|[\s,])г[.](?=\s)/giu,' город').replace(/(?:^|[\s,])д[.](?=\s*\d)/giu,' дом ').replace(/(?:^|[\s,])(?:корп|к)[.](?=\s*\d)/giu,' корпус ').replace(/(?:^|[\s,])стр[.](?=\s*\d)/giu,' строение ').replace(/[,;\s]+/g,' ').trim()}
function parseCampuses(html){
 if(Buffer.byteLength(html)>5000000)throw Error('page_too_large');
 const root=parse(html),nodes=[],stack=[root];while(stack.length){const n=stack.pop();if(nodes.length>=150000)throw Error('html_node_limit');nodes.push(n);stack.push(...(n.childNodes||[]).slice().reverse())}
 const prop=n=>(n.attrs?.find(a=>a.name==='itemprop')?.value||'').toLowerCase().split(/\s+/);
 const plain=n=>{const out=[],pending=[n];while(pending.length){const c=pending.pop();if(['script','style','template'].includes(c.tagName))continue;if(c.nodeName==='#text')out.push(c.value);else pending.push(...(c.childNodes||[]).slice().reverse())}return out.join(' ').replace(/\s+/g,' ').trim()};
 const address=v=>v.length>=12&&v.length<=250&&/\d/.test(v)&&/\p{L}/u.test(v)&&!/телефон|электрон|@|https?:\/\/|\+7\s*\(?\d{3}|не (?:осуществля|ведет)|отсутству|не име[ею]т|осуществления|ОГРН/iu.test(v)&&/(?:ул[. ]|улиц|проспект|пр[. -]|проезд|переул|пер[. ]|шоссе|площадь|наб[. ]|набережн|дом|д[.]|корпус|строение|микрорайон|мкр[. ])\s*[^\n]*\d/iu.test(v)&&[...v.matchAll(/(?:^|\D)\d{6}(?=\D|$)/g)].length<=1&&[...v.matchAll(/(?<!\p{L})(?:ул[.]|улица|проспект|проезд|переулок|шоссе|набережная)(?!\p{L})/giu)].length<=1;
 const label=v=>v.length>=3&&v.length<=160&&!/@|https?:|телефон|учител|директор|заведующ|осуществля|следующ|места /i.test(v)&&/корпус|филиал|школ|гимнази|лицей|детск.{0,8}сад|центр (?:образования|развития|дополнительного)|здание|структурн.{0,20}подразделен/i.test(v);
 const result=[],seen=new Set();
 function add(value,name='Учебная площадка'){if(!address(value))return;const key=normalizeAddress(value);if(seen.has(key))return;seen.add(key);result.push({name,kind:/детск.{0,8}сад|дошкольн/i.test(name)?'preschool':/филиал/i.test(name)?'branch':/школ|гимнази|лицей|корпус/i.test(name)&&name!=='Учебная площадка'?'school':'education_place',address:value,aliases:[]})}
 for(const field of nodes.filter(n=>prop(n).some(p=>['addressplace','addressplaceset'].includes(p)))){
  const siblings=field.parentNode?.childNodes||[],before=siblings.slice(0,siblings.indexOf(field)).filter(n=>n.nodeName!=='#text').slice(-1).map(plain).join(' '),context=plain(field).slice(0,350)+' '+before.slice(-500);
  if(/сетев.{0,12}форм|практической подготов|места проведения (?:практик|государственн)|дополнительным профессиональным/iu.test(context))continue;
  const blocks=nodes.filter(n=>['p','li','tr'].includes(n.tagName)&&(()=>{for(let a=n.parentNode;a;a=a.parentNode){if(a===field)return true;if(['p','li','tr'].includes(a.tagName))return false}return false})());
  if(!blocks.length){add(plain(field));continue}let current='Учебная площадка';
  for(const block of blocks){const value=plain(block);if(label(value)&&!address(value)){current=value;continue}
   if(block.tagName==='tr'){const cells=(block.childNodes||[]).filter(n=>['td','th'].includes(n.tagName)).map(plain),addresses=cells.filter(address),names=cells.filter(v=>label(v)&&!address(v));if(addresses.length===1){add(addresses[0],names.length===1?names[0]:current);continue}}
   const inline=value.match(/^(.{3,160}?)\s*[-–—:]\s*((?:\d{6},?\s*)?(?:г[.]|город|область|республика|россия|край)\s*.+)$/iu);
   if(inline&&label(inline[1])&&address(inline[2])){add(inline[2].replace(/[;\s]+$/,''),inline[1].trim());continue}
   if(address(value)){const postal=value.search(/(?:^|\D)\d{6}(?=\D|$)/);if(postal>3&&label(value.slice(0,postal).trim()))add(value.slice(postal).trim(),value.slice(0,postal).trim());else add(value,current)}
  }
 }
 return result;
}
module.exports={parseCampuses,normalizeAddress};
