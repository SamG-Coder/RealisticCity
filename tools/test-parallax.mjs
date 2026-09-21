import {chromium} from 'playwright';
import fs from 'node:fs/promises';
import assert from 'node:assert/strict';
import {createServer} from '../server.mjs';
const server=createServer();await new Promise(r=>server.listen(0,'127.0.0.1',r));let browser;
try {
 browser=await chromium.launch({channel:'msedge',headless:true,args:['--enable-unsafe-webgpu']});
 const page=await browser.newPage();page.on('pageerror',e=>console.error(e));
 const startup=Date.now();await page.goto(`http://127.0.0.1:${server.address().port}/?test`);
 await page.waitForFunction(()=>window.__ready||window.__error,null,{timeout:240000});
 assert.equal(await page.evaluate(()=>window.__error),undefined);
 const startupMs=Date.now()-startup;console.log('Ready',startupMs,'ms');
 const report=await page.evaluate(async()=>{
  const e=engine;await e.resize(1920,1080);const shots=[],scenes=[];
  const world=(x,z,angle)=>[Math.cos(angle)*x+Math.sin(angle)*z,-Math.sin(angle)*x+Math.cos(angle)*z];
  const camera=(x,y,z,yaw,pitch=0)=>{const a=e.layout[13],[wx,wz]=world(x,z,a);return [wx,y,wz,yaw+a,pitch,0,0,0,...Array(8).fill(0)];};
  const capture=async name=>{for(let i=0;i<8;i++){e.draw();await e.runtime.idle();}const p=await e.pixels(),c=document.createElement('canvas');c.width=e.width;c.height=e.height;c.getContext('2d').putImageData(new ImageData(new Uint8ClampedArray(p),c.width,c.height),0,0);shots.push({name,png:c.toDataURL('image/png').split(',')[1]});};
  for(const view of ['exterior','window','entrance','flight','lobby','room']){
   for(const mode of ['legacy','virtual','physical']){
    if(view==='flight'&&mode==='physical')continue;
    if((view==='lobby'||view==='room')&&mode==='virtual')continue;
    e.parallaxEnabled=mode!=='legacy';
    const begin=performance.now();await e.build(240921,0,0,mode!=='virtual'&&view!=='flight');const buildMs=performance.now()-begin;
    let c=camera(22,2,-25,-.55,-.03);
    if(view==='window')c=camera(13*e.layout[0],.2,e.layout[17],-Math.PI/2,0);
    if(view==='entrance')c=camera(.3,0,-18,0,0);
    if(view==='flight')c=[0,100,-120,.15,-.32,0,0,0,...Array(8).fill(0)];
    if(view==='lobby'||view==='room'){await e.view(view==='lobby'?2:3);c=await e.camera();}
    const times=[];
    for(let i=0;i<14;i++){e.setCamera(c);const t=performance.now();e.draw();await e.runtime.idle();if(i>=4)times.push(performance.now()-t);}
    e.setCamera(c);await capture(`${view}-${mode}`);
    scenes.push({view,mode,features:e.shapes,buildMs,frameMs:times.sort((a,b)=>a-b)[5]});
   }
  }
  e.parallaxEnabled=true;
  const cases=[];
  for(const [seed,x,z] of [[240921,0,0],[17,-2,3],[0,7,-4]]){
   await e.build(seed,x,z,false);
   if(!e.hasBuilding)continue;
   const plan=[...e.layout],sx=plan[0],sz=plan[1];
   e.setCamera(camera(10.5*sx,0,plan[16],-Math.PI/2));await e.stream();if(e.resident)throw Error('Side window loaded interior');
   e.setCamera(camera(0,0,-8.1*sz-6,Math.PI));await e.stream();if(e.resident)throw Error('Looking away loaded a distant entrance');
   e.setCamera(camera(0,0,-8.1*sz-2,Math.PI));await e.stream();if(!e.resident)throw Error('Backwards entrance did not preload');
   e.step([-1,0,0,0,0,0],144);const backwards=await e.camera(),a=e.layout[13],localZ=Math.sin(a)*backwards[0]+Math.cos(a)*backwards[2];if(localZ<-8.1*sz+.2)throw Error('Backwards entry was blocked');
   e.setCamera(camera(16,0,0,0));await e.stream();if(e.resident)throw Error('Exit did not evict');
   e.setCamera(camera(0,0,-8.1*sz-7,0));await e.stream();if(!e.resident)throw Error('Entrance did not preload');
   if(plan.slice(0,7).some((v,i)=>v!==e.layout[i])||plan.slice(8,44).some((v,i)=>v!==e.layout[i+8]))throw Error('Room layout changed at transition');
   const before=await e.camera();e.step([1,0,0,0,0,0],120);const after=await e.camera();if(after[7]<=before[7]+1)throw Error('Entrance blocked');
   e.setCamera(camera(0,0,0,0));await e.stream();if(!e.resident)throw Error('Inside room was evicted');
   e.setCamera(camera(16,0,0,0));await e.stream();if(e.resident)throw Error('Departed interior retained');
   const first=Array.from(await e.runtime.read(e.buffers.s,Float32Array,(32+e.shapes*16)*4));await e.build(seed,x,z,false);const second=await e.runtime.read(e.buffers.s,Float32Array,(32+e.shapes*16)*4);if(first.some((v,i)=>v!==second[i]))throw Error('Virtual geometry not deterministic');
   cases.push({seed,x,z});
  }
  // Angular group rejection must be an exact optimization, not a detail cutoff.
  await e.resize(640,360);let angleComparisons=0;
  for(const {seed,x,z} of cases){await e.build(seed,x,z,false);for(const side of [-1,1])for(const turn of [-.4,.4]){
   const c=camera(side*13*e.layout[0],.2,e.layout[side<0?16:17],-side*Math.PI/2+turn,turn*.5);
   e.angleCullingEnabled=false;e.setCamera(c);e.draw();await e.runtime.idle();const reference=await e.pixels();
   e.angleCullingEnabled=true;e.setCamera(c);e.draw();await e.runtime.idle();const culled=await e.pixels();
   if(reference.some((v,i)=>v!==culled[i]))throw Error('Angle culling changed visible pixels');angleComparisons++;
  }}
  window.__parallaxShots=shots;return {scenes,entranceAndSideWindowCases:cases,angleComparisons,angleCullingExact:true,backwardsEntry:true,deterministic:true,errors:e.errors};
 });
 assert.deepEqual(report.errors,[]);await fs.mkdir('captures/parallax',{recursive:true});
 const shots=await page.evaluate(()=>window.__parallaxShots);for(const shot of shots)await fs.writeFile(`captures/parallax/${shot.name}.png`,Buffer.from(shot.png,'base64'));
 await fs.writeFile('captures/parallax/report.json',JSON.stringify({...report,startupMs},null,2));console.log(JSON.stringify({...report,startupMs},null,2));
}finally{await browser?.close();await new Promise(r=>server.close(r));}
