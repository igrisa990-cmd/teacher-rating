const assert=require('assert/strict'),fs=require('fs'),vm=require('vm');
const elements=new Map(),calls=[],stored=new Map([['teacherPlusDemoMode','1']]);
const el=id=>{if(!elements.has(id))elements.set(id,{disabled:false,value:'',textContent:'',innerHTML:'',isConnected:true,focus(){}});return elements.get(id)};
let otpError=null,verifyError=null;
const auth={
 signInWithOtp:async p=>{calls.push(['send',p]);return{error:otpError}},
 verifyOtp:async p=>{calls.push(['verify',p]);return{error:verifyError,data:{session:{},user:{id:'real',is_anonymous:false,user_metadata:{name:'Имя'}}}}}
};
const c={console,Date,AbortSignal,fetch:async()=>({ok:true,json:async()=>({external:{phone:false}})}),setInterval:()=>1,clearInterval(){},setTimeout(){},localStorage:{removeItem:k=>stored.delete(k)},window:{RUNTIME_CONFIG:{supabaseUrl:'https://project.supabase.co',supabaseAnonKey:'public'}},state:{db:{auth}},$:el,openAuth(){},openModal(){},esc:x=>String(x),preferredRegion:()=> 'Московская область',catalogLoginResult:async r=>calls.push(['login',r.data.user.id]),account(){},closeModal(){},render(){},resumePending:async()=>{},regionOptions:()=>'',applyPreferredRegionV18(){},document:{},toast(){}};
vm.createContext(c);vm.runInContext(fs.readFileSync('public/real-account.js','utf8'),c);
(async()=>{assert(!stored.has('teacherPlusDemoMode'));assert.equal(c.state.demoMode,false);assert.equal(c.realAccount({id:'anon',is_anonymous:true}),null);assert.equal(c.normalizePhone('8 (999) 123-45-67'),'+79991234567');assert.equal(c.normalizePhone('9991234567'),'+79991234567');assert.throws(()=>c.normalizePhone('+74951234567'));assert.throws(()=>c.normalizePhone('+7999123'));
 c.openAuth();await new Promise(r=>setImmediate(r));assert.equal(el('#phoneSendButton').disabled,true);assert.match(el('#phoneAuthError').textContent,/ещё подключается/);
 el('#phoneSendButton').disabled=false;el('#loginPhone').value='123';await c.phoneSend();assert.equal(calls.length,0);
 el('#loginPhone').value='89991234567';otpError={code:'phone_provider_disabled'};await c.phoneSend();assert.match(el('#phoneAuthError').textContent,/недоступна/);assert.equal(el('#phoneForm').hidden,undefined);
 otpError=null;await c.phoneSend();assert.equal(calls.at(-1)[1].phone,'+79991234567');assert.equal(el('#phoneForm').hidden,true);assert.equal(el('#loginPhone').readOnly,true);
 const before=calls.length;await c.phoneSend();assert.equal(calls.length,before);el('#loginCode').value='123456';verifyError={code:'otp_expired'};await c.phoneVerify();assert.match(el('#phoneAuthError').textContent,/Код неверный/);assert(!calls.some(x=>x[0]==='login'));
 verifyError=null;await c.phoneVerify();assert.equal(calls.at(-1)[0],'login');assert.equal(calls.find(x=>x[0]==='verify')[1].type,'sms');assert.equal(c.state.user.id,'real');c.state.demoMode=true;assert.equal(c.state.demoMode,false);
 const ranges=[];
 const query={
  select(){return this},
  order(key){assert.equal(key,'id');return this},
  async range(a,b){ranges.push([a,b]);return {data:Array.from({length:a<1000?500:2},(_,i)=>({id:a+i}))}}
 };
 c.state.db={from:()=>query};
 const catalog=await c.catalogReadAll('schools');assert.equal(catalog.length,1002);assert.deepEqual(ranges,[[0,499],[500,999],[1000,1499]]);
 console.log('PASS: phone normalization, locked demo cleanup, provider-disabled state, failed send/OTP do not log in, resend cooldown, verified session, catalog beyond 1000 rows');
})().catch(e=>{console.error(e);process.exitCode=1});
