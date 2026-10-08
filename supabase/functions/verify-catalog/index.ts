import {createClient} from 'https://esm.sh/@supabase/supabase-js@2';
import {matchesOfficialRow,publicAddress} from './match.js';
const cors={'Access-Control-Allow-Origin':'*','Access-Control-Allow-Headers':'authorization,x-client-info,apikey,content-type','Content-Type':'application/json'};
const reply=(data:unknown,status=200)=>new Response(JSON.stringify(data),{status,headers:cors});
async function officialPage(url:URL){
 const addresses=(await Promise.allSettled([Deno.resolveDns(url.hostname,'A'),Deno.resolveDns(url.hostname,'AAAA')])).flatMap(r=>r.status==='fulfilled'?r.value:[]);
 if(!addresses.length||addresses.some(ip=>!publicAddress(ip)))throw Error('Источник недоступен для безопасной проверки');
 const response=await fetch(url,{redirect:'error',signal:AbortSignal.timeout(8000)});
 if(!response.ok||!response.headers.get('content-type')?.includes('text/html'))throw Error('Источник не вернул страницу');
 const reader=response.body?.getReader();if(!reader)throw Error('Пустой источник');let size=0,text='';const decoder=new TextDecoder();
 try{while(true){const {done,value}=await reader.read();if(done)break;size+=value.length;if(size>1000000)throw Error('Слишком большой источник');text+=decoder.decode(value,{stream:true})}return text+decoder.decode()}finally{await reader.cancel()}
}
Deno.serve(async req=>{
 if(req.method==='OPTIONS')return reply({});if(req.method!=='POST')return reply({error:'Method not allowed'},405);
 const client=createClient(Deno.env.get('SUPABASE_URL')!,Deno.env.get('SUPABASE_ANON_KEY')!,{global:{headers:{Authorization:req.headers.get('Authorization')||''}}});
 const {data:{user},error}=await client.auth.getUser();if(error||!user)return reply({error:'Требуется вход'},401);
 const admin=createClient(Deno.env.get('SUPABASE_URL')!,Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!);
 let id;try{id=(await req.json()).request_id}catch{return reply({error:'Неверный запрос'},400)}
 if(typeof id!=='string'||! /^[0-9a-f-]{36}$/i.test(id))return reply({error:'Неверный номер заявки'},400);
 const {data:row}=await admin.from('catalog_requests').select('*').eq('id',id).eq('user_id',user.id).maybeSingle();if(!row)return reply({error:'Заявка не найдена'},404);
 if(row.status!=='queued')return reply({status:row.status});
 let outcome='needs_review',note='Не хватает подтверждённого официального источника. Требуется модератор.',evidence={};
 try{
  if(row.kind!=='school'&&row.school_id){
   const {data:school}=await admin.from('schools').select('source_url,source_type,verified_at').eq('id',row.school_id).single();
   if(school?.verified_at&&school.source_url&&['official','moderated'].includes(school.source_type)){
    const trusted=new URL(school.source_url),url=new URL(row.source_url||'/sveden/employees/',trusted);
    if(trusted.protocol!=='https:'||url.protocol!=='https:'||url.origin!==trusted.origin||url.username||url.password||url.port&&url.port!=='443')throw Error('Ссылка не совпадает с подтверждённым сайтом школы');
    const html=await officialPage(url);
    if(matchesOfficialRow(html,row.person_name,row.kind==='director'?'директор':row.subject)){outcome='verified';note='Полное имя и профессиональные сведения совпали в одной строке официального сайта школы.';evidence={url:url.href,checked_at:new Date().toISOString()}}
    else note='Однозначное совпадение на официальной странице не найдено. Требуется модератор.';
   }
  }
 }catch{note='Автоматическая проверка источника не завершена. Требуется модератор.'}
 const result=await admin.rpc('catalog_finish',{p_request_id:id,p_outcome:outcome,p_method:outcome==='verified'?'official_row':'source_check',p_note:note,p_evidence:evidence});
 if(result.error){await client.rpc('queue_catalog_review',{p_request_id:id});return reply({status:'needs_review'})}
 return reply({status:result.data.status});
});
