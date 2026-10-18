const assert=require('assert/strict'),{createHostPacer}=require('../scripts/collect-national-staff.cjs');
(async()=>{let time=1000,sleeping=0,maxSleeping=0;const waits=[],starts=[],pace=createHostPacer({now:()=>time,pause:async ms=>{sleeping++;maxSleeping=Math.max(maxSleeping,sleeping);waits.push(ms);await Promise.resolve();time+=ms;sleeping--}});
await Promise.all([pace('shared.example',200).then(()=>starts.push(time)),pace('shared.example',200).then(()=>starts.push(time)),pace('shared.example',200).then(()=>starts.push(time))]);assert.deepEqual(starts,[1200,1400,1600]);assert.equal(maxSleeping,1,'One host sequences actual request starts rather than releasing overdue timers together');
await pace('other.example',200);assert.equal(waits.at(-1),200,'Independent hosts retain separate limits');
await pace('shared.example',1000);const first=time;await pace('shared.example',200);assert.equal(time-first,1000,'A longer published crawl delay remains enforced for the shared host');
console.log('PASS: shared-host concurrency retains globally spaced request starts and the longest published crawl delay');})().catch(e=>{console.error(e);process.exitCode=1});
