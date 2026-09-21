import {chromium} from 'playwright';
import fs from 'node:fs/promises';
import assert from 'node:assert/strict';
import {createServer} from '../server.mjs';

const server=createServer();
await new Promise(resolve=>server.listen(0,'127.0.0.1',resolve));
let browser;
try {
  browser=await chromium.launch({channel:'msedge',headless:true,args:['--enable-unsafe-webgpu']});
  const page=await browser.newPage();
  await page.goto(`http://127.0.0.1:${server.address().port}/?test`);
  await page.waitForFunction(()=>window.__ready||window.__error,null,{timeout:180000});
  assert.equal(await page.evaluate(()=>window.__error),undefined);
  const report=await page.evaluate(async()=>{
    const e=engine;
    await e.resize(1920,1080);
    await e.view(1);
    await e.setFly(true);
    const camera=await e.camera();
    const frame=async enabled=>{
      e.setCamera(camera);
      e.temporalEnabled=true;
      e.shadowBlurEnabled=enabled;
      e.draw();await e.runtime.idle();
      // Isolate spatial filtering from the separate temporal color filter.
      e.temporalEnabled=false;
      e.step([0,1,1,0,0,0],1);
      e.draw();await e.runtime.idle();
      return {pixels:await e.pixels(),shadows:await e.runtime.read(e.buffers.Shadows)};
    };
    const raw=await frame(false),blur=await frame(true);
    let changed=0,unfiltered=0,active=0;
    for(let i=0;i<blur.shadows.length;i++){
      const differs=[0,1,2].some(k=>raw.pixels[i*4+k]!==blur.pixels[i*4+k]);
      if(blur.shadows[i]>=0)active++;
      else {unfiltered++;if(differs)throw Error('Filter modified a non-shadow receiver');}
      if(differs)changed++;
    }
    if(changed<100||active<100)throw Error('Moving shadow filter did not activate');
    e.draw();await e.runtime.idle();
    const stopped=await e.runtime.read(e.buffers.Shadows);
    if(stopped.some(v=>v>=0))throw Error('Filter remained active after stopping');
    const encode=pixels=>{const c=document.createElement('canvas');c.width=e.width;c.height=e.height;c.getContext('2d').putImageData(new ImageData(new Uint8ClampedArray(pixels),c.width,c.height),0,0);return c.toDataURL('image/png').split(',')[1];};
    window.__shadowImages=[encode(raw.pixels),encode(blur.pixels)];
    e.temporalEnabled=true;
    const timings={};
    for(const enabled of [false,true]){
      e.shadowBlurEnabled=enabled;e.setCamera(camera);e.draw();await e.runtime.idle();
      const times=[];
      for(let i=0;i<14;i++){e.step([0,1,1,0,0,0],1);const start=performance.now();e.draw();await e.runtime.idle();if(i>=4)times.push(performance.now()-start);}
      timings[enabled?'blurMs':'rawMs']=times.sort((a,b)=>a-b)[5];
    }
    return {resolution:[e.width,e.height],changedShadowPixels:changed,activeReceivers:active,unchangedExcludedPixels:unfiltered,disabledWhenStopped:true,...timings,errors:e.errors};
  });
  assert.deepEqual(report.errors,[]);
  await fs.mkdir('captures',{recursive:true});
  const images=await page.evaluate(()=>window.__shadowImages);
  for(let i=0;i<images.length;i++)await fs.writeFile(`captures/shadows-${i?'blur':'raw'}.png`,Buffer.from(images[i],'base64'));
  await fs.writeFile('captures/shadow-blur-validation.json',JSON.stringify(report,null,2));
  console.log(report);
} finally {
  await browser?.close();
  await new Promise(resolve=>server.close(resolve));
}
