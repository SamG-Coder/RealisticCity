import {chromium} from 'playwright';
import fs from 'node:fs/promises';
import assert from 'node:assert/strict';
import {createServer} from '../server.mjs';
const label=process.argv[2]||'candidate',server=createServer();await new Promise(r=>server.listen(0,'127.0.0.1',r));let browser;
try{
 browser=await chromium.launch({channel:'msedge',headless:true,args:['--enable-unsafe-webgpu']});const page=await browser.newPage({viewport:{width:1440,height:900}});page.on('pageerror',e=>console.error(e));const start=Date.now();await page.goto(`http://127.0.0.1:${server.address().port}/?test`);await page.waitForFunction(()=>window.__ready||window.__error,null,{timeout:180000});assert.equal(await page.evaluate(()=>window.__error),undefined);console.log('Ready',Date.now()-start,'ms');
 const report=await page.evaluate(async()=>{
  const e=engine,device=e.device,hash=async array=>Array.from(new Uint8Array(await crypto.subtle.digest('SHA-256',array))).map(x=>x.toString(16).padStart(2,'0')).join('');
  if(!device.features.has('timestamp-query'))throw Error('GPU timestamp queries required for this benchmark');
  const query=device.createQuerySet({type:'timestamp',count:4}),resolve=device.createBuffer({size:32,usage:GPUBufferUsage.QUERY_RESOLVE|GPUBufferUsage.COPY_SRC}),read=device.createBuffer({size:32,usage:GPUBufferUsage.MAP_READ|GPUBufferUsage.COPY_DST});
  const scenes=[];await e.resize(1920,1080);
  for(const scene of [{name:'exterior',view:1,seed:240921},{name:'lobby',view:2,seed:240921},{name:'flight',view:1,seed:240921},{name:'room-seed17',view:3,seed:17}]){
   const buildStart=performance.now();await e.build(scene.seed,0,0);const buildMs=performance.now()-buildStart;await e.view(scene.view);if(scene.name==='flight')e.setCamera([0,100,-120,.15,-.32,0,0,0,...Array(8).fill(0)]);const camera=await e.camera();
   const geometryHash=await hash(await e.runtime.read(e.buffers.s,Float32Array,(32+e.shapes*16)*4));
   const far=[],shading=[];for(let i=0;i<12;i++){
    e.setCamera(camera);e.runtime.batch({timestampWrites:{querySet:query,beginningOfPassWriteIndex:0,endOfPassWriteIndex:1}}).dispatch(e.bind('farVisibility',{w:e.width,h:e.height}),[e.width/64,e.height]).submit();
    e.runtime.batch().dispatch(e.bind('movingShadows',{w:e.width,h:e.height,enabled:1}),[e.width/64,e.height]).submit();
    e.runtime.batch({timestampWrites:{querySet:query,beginningOfPassWriteIndex:2,endOfPassWriteIndex:3}}).dispatch(e.bind('render',{w:e.width,h:e.height,quality:1}),[e.width/64,e.height]).submit();
    const encoder=device.createCommandEncoder();encoder.resolveQuerySet(query,0,4,resolve,0);encoder.copyBufferToBuffer(resolve,0,read,0,32);device.queue.submit([encoder.finish()]);await read.mapAsync(GPUMapMode.READ);const times=new BigUint64Array(read.getMappedRange());if(i>=2){far.push(Number(times[1]-times[0])/1e6);shading.push(Number(times[3]-times[2])/1e6);}read.unmap();
   }
   e.setCamera(camera);for(let i=0;i<8;i++)e.draw();await e.runtime.idle();const pixelsHash=await hash(await e.pixels()),historyHash=await hash(await e.runtime.read(e.buffers.history));
   const frameTimes=[];for(let i=0;i<12;i++){e.setCamera(camera);const t=performance.now();e.draw();await e.runtime.idle();if(i>=2)frameTimes.push(performance.now()-t);}
   const median=a=>a.sort((a,b)=>a-b)[Math.floor(a.length/2)];scenes.push({name:scene.name,buildMs,features:e.shapes,farGpuMs:median(far),shadeGpuMs:median(shading),frameMs:median(frameTimes),geometryHash,pixelsHash,historyHash});
  }
  query.destroy();resolve.destroy();read.destroy();return {adapter:e.runtime.describe(),resolution:[e.width,e.height],quality:1,scenes,errors:e.errors};
 });assert.deepEqual(report.errors,[]);await fs.mkdir('captures',{recursive:true});await fs.writeFile(`captures/performance-${label}.json`,JSON.stringify(report,null,2));console.log(JSON.stringify(report.scenes,null,2));
 if(label!=='baseline'){const baseline=JSON.parse(await fs.readFile('captures/performance-baseline.json','utf8'));for(let i=0;i<report.scenes.length;i++){for(const field of ['geometryHash','pixelsHash','historyHash'])assert.equal(report.scenes[i][field],baseline.scenes[i][field],`${report.scenes[i].name}: ${field} changed`);}console.log('PASS exact geometry, pixels and accumulation history match baseline');}
}finally{await browser?.close();await new Promise(r=>server.close(r));}
