/* Preserve explicit settlement labels; never infer a settlement from a municipality or school name. */
const {regionIn}=require('./prepare-license-snapshot.cjs');
const regions=JSON.parse(require('fs').readFileSync('data/registry/20261013-accredited-schools-report.json')).regions;
function explicitRegion(address,authority=''){
 const direct=regionIn(address)||regionIn(authority);if(direct)return direct;
 const s=(' '+address+' '+authority+' ').normalize('NFKC').toLowerCase().replaceAll('ё','е').replace(/[^\p{L}\p{N}]+/gu,' '),matches=[];
 for(const region of regions.filter(r=>r.endsWith(' Республика'))){const stem=region.toLowerCase().slice(0,-' республика'.length).replace(/ая$/,'').replaceAll('-',' '),adj=stem+'(?:ая|ой|ую)';if(new RegExp('(?:^| )(?:'+adj+' респ(?:ублика|ублики)?|респ(?:ублика|ублики)? '+adj+')(?: |$)','u').test(s))matches.push(region)}
 return matches.length===1?matches[0]:'';
}
function explicitSettlement(address,region){
 const valid=s=>s.length>=2&&s.length<100&&/^\p{L}/u.test(s)&&!/район|р[-.]н|округ|муниципаль|поселение|улица|ул[.]|проспект|переулок|шоссе|дом|область|республик|г[.]о[.]|;|\sг[.]\s/iu.test(s)&&!/^(?:город|село|деревня|поселок|посёлок)\s|^\p{L}[.]/iu.test(s);
 const parts=String(address).normalize('NFC').split(',').map(s=>s.trim().replace(/^\d{6}\s+/,''));
 const word='(?:город-курорт|городской поселок|городской посёлок|город|село|деревня|поселок|посёлок|станица|ст-ца|хутор|аул|улус|местечко)',short='(?:г|с|д|п|х|пос|м)';
 const names=[];for(let part of parts){part=part.replace(/^(?:городское поселение\s+|г[.]о[.]\s+(?=город\s))/iu,'');const start=part.match(new RegExp('^(?:'+word+'\\s+|'+short+'[.]\\s*)(.+)$','iu')),end=part.match(new RegExp('^(.+?)\\s+(?:'+word+'|'+short+'[.]?)$','iu'));let name=start?.[1]||end?.[1];if(name){name=name.split(/\s+(?:улица|ул[.]|проспект|проезд|переулок|пер[.]|шоссе|дом|д[.]|здание|зд[.])\s*/iu)[0].trim().replace(/^[«"]|[»"]$/g,'');if(valid(name))names.push(name)}}
 const unique=[...new Set(names)];return unique.length===1?unique[0]:'';
}
module.exports={explicitRegion,explicitSettlement};
