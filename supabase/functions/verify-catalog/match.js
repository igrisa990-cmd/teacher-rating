export const normalize = value => String(value || '').toLocaleLowerCase('ru').replaceAll('ё','е').replace(/[^\p{L}\p{N}]+/gu,' ').trim();
export function matchesOfficialRow(html, name, subject) {
 const blocks = html.match(/<tr\b[^>]*>[\s\S]*?<\/tr>/gi) || [];
 const n=normalize(name),s=normalize(subject);
 if(!n||!s)return false;
 return blocks.some(row=>{const text=' '+normalize(row.replace(/<script\b[^>]*>[\s\S]*?<\/script>/gi,'').replace(/<[^>]*>/g,' '))+' ';return text.includes(' '+n+' ')&&text.includes(' '+s+' ')});
}
export function publicAddress(ip){
 if(ip.includes(':'))return /^2[0-9a-f]{3}:/i.test(ip)&&!/^2001:(db8|0):/i.test(ip);
 const n=ip.split('.').map(Number);if(n.length!==4||n.some(v=>!Number.isInteger(v)||v<0||v>255))return false;
 return !([0,10,127].includes(n[0])||n[0]>=224||n[0]===169&&n[1]===254||n[0]===172&&n[1]>=16&&n[1]<=31||n[0]===192&&n[1]===168||n[0]===100&&n[1]>=64&&n[1]<=127||n[0]===192&&n[1]===0||n[0]===198&&[18,19,51].includes(n[1])||n[0]===203&&n[1]===0);
}
