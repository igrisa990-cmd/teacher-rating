/* Read explicit physical settlement labels; administrative settlements stay unresolved. */
function explicitPhysicalSettlement(address,region){
 const names=[];
 const marker='(?:город(?:-курорт)?|село|деревня|аул|улус|хутор|станица|станция|местечко|слобода|насел[её]нный пункт|(?:дачный|сельский|рабочий|городской) пос[её]лок|пос[её]лок)';
 const short='(?:пгт|рп|гп|дер|сел|ст-ца|пос|г|с|д|п|х)';
 for(let part of String(address).normalize('NFC').split(/[,;]/)){
  part=part.trim().replace(/^\d{6}[.\s]+/,'');
  if(/сельское поселение|с[.]\s*п[.]|сельский округ|городское поселение|г[.]\s*о[.]|муниципальн\p{L}* округ|городской округ|муниципальное образование/iu.test(part))continue;
  const afterAdmin=part.match(/^(.+?(?:область|республика|край|район|округ))\s+(.+)$/iu);
  if(afterAdmin&&!/(?:улица|шоссе|переулок|\bhttps?\b)/iu.test(afterAdmin[1]))part=afterAdmin[2];
  const start=part.match(new RegExp('^(?:'+marker+'[.]?\\s+|'+short+'\\s*[.]?\\s+|'+short+'\\s*[.]\\s*)(.+)$','iu'));
  if(!start)continue;
  const name=start[1].split(/\s+(?:улица|ул\s*[.]|проспект|просп\s*[.]|проезд|переулок|пер\s*[.]|шоссе|дом|д\s*[.]|здание|зд\s*[.]|квартал|кв-л|микрорайон|мкр\s*[.])\s*/iu)[0].trim().replace(/^(?:«(.+)»|"(.+)")$/u,(_match,a,b)=>a||b);
  if(name.length<2||name.length>100||!/[\p{L}]/u.test(name)||!/^[\p{L}\p{N}][\p{L}\p{N} .’'"«»()\/-]*$/u.test(name)||/район|область|округ|республик|поселение|сельсовет|улица|переулок|шоссе|проспект|\s(?:город|село|деревня|пос[её]лок)\s|\s(?:г|д|с|п|ст)\s*[.]|\sкра[яйе](?:\s|$)/iu.test(name)||/^\p{L}[.]/u.test(name)||/^\d+(?:[/.-]\d+)*[а-я]?$/iu.test(name.replace(/[\s«»"']/g,'')))continue;
  names.push(name);
 }
 const unique=[...new Map(names.map(n=>[n.toLocaleLowerCase('ru').replaceAll('ё','е'),n])).values()];return unique.length===1?unique[0]:'';
}
module.exports={explicitPhysicalSettlement};
