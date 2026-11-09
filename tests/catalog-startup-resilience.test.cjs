'use strict';
const assert=require('node:assert/strict'),fs=require('node:fs'),vm=require('node:vm');

const runtime=fs.readFileSync('public/catalog-runtime.js','utf8').split('const catalogProfileBefore')[0];
const render=fs.readFileSync('public/index.html','utf8').split('\n').find(line=>line.startsWith('function render(){'));
const fallback=fs.readFileSync('public/real-account.js','utf8').split('const realRenderBefore=render;')[1];
const app={innerHTML:'',insertAdjacentHTML(_position,html){this.innerHTML=html+this.innerHTML;}};
const location={hash:'#home'};
const timers=new Map();
let nextTimer=0,abortCount=0,failBoot=false;
const pending=new Promise(()=>{});
const clock={
 setTimeout(callback,delay){const id=++nextTimer;timers.set(id,{callback,delay});return id;},
 clearTimeout(id){timers.delete(id);}
};
function fire(delay){for(const [id,timer] of timers)if(timer.delay===delay){timers.delete(id);timer.callback();}}
const state={loading:true,schools:[],teachers:[],reviews:[{id:1}],votes:[],db:{
 auth:{getSession:()=>pending},
 rpc(){return {abortSignal(signal){signal.addEventListener('abort',()=>abortCount++);return failBoot?pending:Promise.resolve({data:{stats:{schools:1}}});}};},
 from(table){return {select(){return this;},order(){return this;},limit(){return this;},abortSignal(signal){
  signal.addEventListener('abort',()=>abortCount++);
  return table==='reviews'?pending:Promise.reject(Error('votes unavailable'));
 }};}
}};
const context=vm.createContext({
 state,location,window:{supabase:{},RUNTIME_CONFIG:{supabaseUrl:'https://example.test',supabaseAnonKey:'example'}},
 $:()=>app,esc:String,home:()=>'<h1>Главная</h1>',guidePage:()=>'<h1>Материал</h1>',loading:()=>'<p>Загрузка</p>',
 currentRouteName:()=>location.hash.slice(1),setActive(){},updateCompare(){},injectGuideBanner(){},requestAnimationFrame(){},
 preferredRegion:()=>'',accountBindAuth(){},realAccount:()=>null,account(){},accountMaybeRegionOnboarding(){},toast(){},
 AbortController,console:{error(){}},...clock
});
vm.runInContext(render+'\nconst realRenderBefore=render;'+fallback+'\n'+runtime,context);

(async()=>{
 const startup=context.loadData();
 assert.match(app.innerHTML,/Главная/u);
 location.hash='#guide/example';context.render();assert.match(app.innerHTML,/Материал/u);
 location.hash='#home';
 await Promise.resolve();fire(12000);await startup;
 assert.equal(state.loading,false);assert.equal(state.catalogError,null);
 assert.equal(state.catalogStats.schools,1);assert.equal(state.reviews[0].id,1);
 assert(abortCount>=1);

 failBoot=true;
 const timedOut=context.loadData();
 await Promise.resolve();fire(12000);fire(18000);await timedOut;
 assert.equal(state.loading,false);
 assert.match(app.innerHTML,/Повторить/u);assert.match(app.innerHTML,/Главная/u);
 assert(abortCount>=3);
 location.hash='#guide/example';context.render();assert.match(app.innerHTML,/Материал/u);
 assert.doesNotMatch(app.innerHTML,/Справочник временно недоступен/u);

 failBoot=false;location.hash='#home';
 const retry=context.loadData();
 await Promise.resolve();fire(12000);await retry;
 assert.equal(state.catalogError,null);assert.match(app.innerHTML,/Главная/u);assert.doesNotMatch(app.innerHTML,/Повторить/u);
 console.log('PASS: the home and guides open during startup, stalled requests are bounded, and a failed catalogue leaves the home and retry available');
})().catch(error=>{console.error(error);process.exitCode=1;});
