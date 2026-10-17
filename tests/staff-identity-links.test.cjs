const assert=require('assert/strict'),{resolveSchoolIdentity,identityCandidates,discoverStaffPages}=require('../scripts/collect-national-staff.cjs');
const seed={ogrn:'1020300977620',name:'Муниципальная общеобразовательная школа № 1',city:'Москва',address:'125000, г. Москва, ул. Тестовая, дом 1'},home={url:'https://school.example/',body:'<a href="/sveden/">Сведения об образовательной организации</a><a href="https://outside.example/contacts">Контакты</a>'};
(async()=>{
 const visited=[],pages={'https://school.example/sveden/':'<a href="/common">Основные сведения</a><a href="/staff">Педагогический состав</a>','https://school.example/common':'<p>ОГРН: 1020300977620</p>'};
 const found=await resolveSchoolIdentity(home,seed,async url=>{visited.push(url);return{url,body:pages[url]}});assert.equal(found.method,'explicit_ogrn');assert.deepEqual(visited,Object.keys(pages));assert.equal(found.pages.length,3);assert(found.pages[1].body.includes('/staff'));assert.equal(identityCandidates(home.body,home.url).length,1);
 const renamed={...seed,currentLicenseIdentity:{ogrn:seed.ogrn,name:'Муниципальное бюджетное общеобразовательное учреждение школа № 1',address:'125000, г. Москва, ул. Тестовая, дом 2'}};
 const legal={url:home.url,body:'<div itemprop="fullName">'+renamed.currentLicenseIdentity.name+'</div><div itemprop="address">'+renamed.currentLicenseIdentity.address+'</div>'};
 assert.equal((await resolveSchoolIdentity(legal,renamed,()=>assert.fail())).reference,'current_license');
 assert.equal((await resolveSchoolIdentity(legal,{...renamed,currentLicenseIdentity:{...renamed.currentLicenseIdentity,ogrn:'1033107012366'}},()=>assert.fail())).method,null);
 assert.equal((await resolveSchoolIdentity({...legal,body:'<p>ОГРН: 1033107012366</p>'+legal.body},renamed,()=>assert.fail())).method,null);
 let requests=0;const many={url:home.url,body:Array.from({length:12},(_,i)=>`<a href="/common/${i}">Основные сведения</a>`).join('')};
 assert.equal((await resolveSchoolIdentity(many,seed,async()=>{requests++;throw Error('http_404')})).method,null);assert.equal(requests,6,'failed links count toward the request bound');
 await assert.rejects(resolveSchoolIdentity(home,seed,async()=>{throw Error('http_403')}),/http_403/);
 const unrelated={url:home.url,body:'<a href="/news">Новости школы</a><a href="/guess">ОГРН где-то здесь</a>'};assert.equal((await resolveSchoolIdentity(unrelated,seed,()=>assert.fail())).method,null);
 const menu=await discoverStaffPages([home],async url=>({url,body:pages[url]}));assert.equal(menu.staff.length,1);assert.equal(menu.staff[0].url,'https://school.example/staff');assert.equal(menu.pages.length,2);
 const direct=await discoverStaffPages([{url:home.url,body:'<a href="/staff">Педагогический состав</a>'}],()=>assert.fail());assert.equal(direct.staff.length,1);
 let menuRequests=0;const missing=await discoverStaffPages([many],async()=>{menuRequests++;throw Error('http_404')});assert.equal(missing.staff.length,0);assert.equal(menuRequests,4);
 console.log('PASS: bounded linked identity traversal, same-OGRN current-license names, mismatched identifiers and restricted pages held, no guessed or external paths');
})().catch(e=>{console.error(e);process.exitCode=1});
