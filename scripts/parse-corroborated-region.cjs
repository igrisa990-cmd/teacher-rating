/* A region abbreviation needs independent confirmation by the named licensing authority. */
const {explicitRegion}=require('./parse-school-localities.cjs');
const aliases={КЧР:['Карачаево-Черкесская Республика'],КБР:['Кабардино-Балкарская Республика'],РД:['Республика Дагестан'],ЧР:['Чеченская Республика','Чувашская Республика'],РБ:['Республика Башкортостан','Республика Бурятия'],РТ:['Республика Татарстан','Республика Тыва']};
function corroboratedRegion(address,authority){
 const direct=explicitRegion(address);
 const fields=String(address).normalize('NFKC').split(/[,;]/).map(s=>s.trim().replace(/^\d{6}[.\s]+/,'').replace(/[.]$/,'').trim().toLocaleUpperCase('ru'));
 const matches=fields.filter(s=>Object.hasOwn(aliases,s));if(direct)return matches.every(alias=>aliases[alias].includes(direct))?direct:'';
 const issuer=explicitRegion('',authority);if(!issuer||matches.length!==1||!aliases[matches[0]].includes(issuer))return '';
 return issuer;
}
module.exports={corroboratedRegion};
