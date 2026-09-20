import {chromium} from 'playwright';import fs from 'node:fs/promises';import {createServer} from '../server.mjs';
const server=createServer();await new Promise(r=>server.listen(0,'127.0.0.1',r));let browser;const captures=`captures/run-${Date.now()}`;await fs.mkdir(captures,{recursive:true});
try{browser=await chromium.launch({channel:'msedge',headless:true,args:['--enable-unsafe-webgpu']});const page=await browser.newPage({viewport:{width:1440,height:900}});page.on('console',m=>{if(m.type()==='error')console.error(m.text());});page.on('pageerror',e=>console.error(e));
 await page.goto(`http://127.0.0.1:${server.address().port}/?test`);await page.waitForFunction(()=>window.__ready||window.__error,null,{timeout:180000});const error=await page.evaluate(()=>window.__error);if(error)throw Error(error);
 console.log(await page.evaluate(()=>({shapes:engine.shapes,adapter:engine.runtime.describe()})));
 const route=await page.evaluate(async()=>{
  const e=engine;let targets=0;let sx=e.layout[0],sz=e.layout[1],floors=e.layout[2];
  async function walk(x,z){x*=sx;z*=sz;for(let i=0;i<500;i++){const c=await e.camera(),dx=x-c[0],dz=z-c[2];if(dx*dx+dz*dz<.012){targets++;return;}c[3]=Math.atan2(dx,dz);e.setCamera(c);e.step([1,0,0,0,0,0],4);}throw Error(`Blocked toward ${x},${z}: ${await e.camera()}`);}
  await e.view(0);e.step([],120);let c=await e.camera();if(Math.abs(c[1])>.03)throw Error('Grounding failed');
  async function rooms(f){for(let r=0;r<4;r++){const z=e.layout[16+f*4+r]/sz;await walk(0,z);await walk((r%2?1:-1)*3.1,z);await walk(0,z);}}
  await rooms(0);
  for(let f=0;f<floors-1;f++){await walk(0,5);await walk(-.94,5);await walk(-.94,9.2);await walk(.94,9.2);await walk(.94,5.1);c=await e.camera();if(Math.abs(c[1]-e.layout[9+f])>.1)throw Error('Stair height: '+c);await rooms(f+1);}
  for(let f=floors-1;f>0;f--){await walk(.94,5.1);await walk(.94,9.2);await walk(-.94,9.2);await walk(-.94,5);await walk(0,4.7);e.step([],60);c=await e.camera();if(Math.abs(c[1]-e.layout[7+f])>.1)throw Error('Stair descent: '+c);}
  await walk(0,-12);e.step([0,0,0,0,0,1],15);c=await e.camera();if(c[1]<.1)throw Error('Jump failed');e.step([],180);if(Math.abs((await e.camera())[1])>.03)throw Error('Landing failed');
  e.setCamera([4*sx,0,-10*sz,0,0,0,1,0,...Array(8).fill(0)]);e.step([1,0,0,0,1,0],240);c=await e.camera();if(c[2]>-8.26*sz-.25)throw Error('Facade penetration');
  const hash=async()=>{const data=await e.runtime.read(e.buffers.s);return Array.from(data.slice(0,32+e.shapes*16));};
  const original=await hash();await e.build(240921);const repeated=await hash();if(JSON.stringify(original)!==JSON.stringify(repeated))throw Error('Seed reconstruction mismatch');
  await e.build(17);const alternative=await hash();if(JSON.stringify(original)===JSON.stringify(alternative))throw Error('Seed variation missing');await e.build(240921);
  // Stream away, evict, and reconstruct the same address without growing buffers.
  const allocation=e.buffers.s.gpuBuffer.size;const before=await hash();const oldShapes=e.shapes;
  e.setCamera([19,0,-19,0,0,0,1,0,...Array(8).fill(0)]);await e.stream();
  if(e.resident)throw Error('Far interior was not evicted');if(e.shapes>=oldShapes)throw Error('Interior geometry was not removed');
  e.setCamera([40,0,-14,0,0,0,1,0,...Array(8).fill(0)]);await e.stream();if(e.lotX!==1||!e.resident)throw Error('Neighbor did not load');
  e.setCamera([-40,0,-14,0,0,0,1,0,...Array(8).fill(0)]);await e.stream();if(e.lotX!==0||!e.resident)throw Error('Return did not load');
  if(JSON.stringify(before)!==JSON.stringify(await hash()))throw Error('Streaming reconstruction differs');
  if(e.buffers.s.gpuBuffer.size!==allocation)throw Error('Streaming grew allocation');
  // A neighbor and an active nonresident lot enumerate identical exterior features.
  const records=async(ox,oz)=>{const d=await e.runtime.read(e.buffers.s),out=[];for(let i=0;i<e.shapes;i++){const b=32+i*16;if(d[b+13]===ox&&d[b+14]===oz){const a=Array.from(d.slice(b,b+13));a[0]-=ox;a[3]-=ox;a[2]-=oz;a[5]-=oz;out.push(a);}}return out;};
  const neighbor=await records(40,0);await e.build(240921,1,0,false);const active=await records(0,0);active.shift(); // common ground plane
  if(neighbor.length!==active.length||neighbor.some((a,i)=>a.some((v,j)=>Math.abs(v-active[i][j])>0.0001)))throw Error('Near/far exterior grammar mismatch');
  const variants=[];for(const [x,z]of [[1,0],[-2,3],[7,-4]]){
    await e.build(240921,x,z);sx=e.layout[0];sz=e.layout[1];floors=e.layout[2];variants.push({x,z,floors,roof:e.layout[3],use:e.layout[4]});await e.view(0);e.step([],120);await rooms(0);
    for(let f=0;f<floors-1;f++){await walk(0,5);await walk(-.94,5);await walk(-.94,9.2);await walk(.94,9.2);await walk(.94,5.1);if(Math.abs((await e.camera())[1]-e.layout[9+f])>.1)throw Error('Variant stairs failed');await rooms(f+1);}
  }
  await e.build(240921,0,0);sx=e.layout[0];sz=e.layout[1];floors=e.layout[2];
  // Accumulation survives stationary physics and resets during actual motion.
  await e.view(0);e.step([],120);e.draw();e.step([],1);e.draw();await e.runtime.idle();if((await e.camera())[9]!==2)throw Error('Stationary accumulation resets');e.step([1,0,0,0,0,0],1);if((await e.camera())[9]!==0)throw Error('Moving accumulation fails to reset');
  return {targets,variants,exteriorConsistency:true,rooms:floors*4+variants.reduce((n,v)=>n+v.floors*4,0),camera:c,errors:e.errors,streamingEviction:true,streamingReturn:true,boundedAllocation:true,seedRegeneration:true,seedVariation:true,accumulation:true};
 });console.log('Walkthrough:',route);
 const timings={};
 for(const [name,view]of [['exterior',1],['lobby',2],['room',3],['stairs',4],['upper',5]]){
  const timing=await page.evaluate(async(view)=>{await engine.view(view);await engine.resize(1920,1080);document.body.classList.add('hide-ui');const begin=performance.now();for(let i=0;i<24;i++){engine.draw();await engine.runtime.idle();}return (performance.now()-begin)/24;},view);
  const png=await page.evaluate(async()=>{const data=await engine.pixels(),out=document.createElement('canvas');out.width=engine.width;out.height=engine.height;out.getContext('2d').putImageData(new ImageData(new Uint8ClampedArray(data),out.width,out.height),0,0);return out.toDataURL('image/png').split(',')[1];});await fs.writeFile(`${captures}/${name}.png`,Buffer.from(png,'base64'));timings[name]=timing;console.log(name,'ms/frame',timing);
 }
 // Exercise actual browser UI and pointer-lock input, beyond direct kernel calls.
 const ui=await browser.newPage({viewport:{width:1366,height:768}});await ui.goto(`http://127.0.0.1:${server.address().port}/?resolution=1280`);await ui.waitForFunction(()=>window.__ready||window.__error);if(await ui.evaluate(()=>window.__error))throw Error(await ui.evaluate(()=>window.__error));await ui.locator('#enter').click();await ui.waitForFunction(()=>document.pointerLockElement!==null);await ui.keyboard.down('KeyW');await new Promise(r=>setTimeout(r,700));await ui.keyboard.up('KeyW');const moved=await ui.evaluate(()=>engine.camera());if(moved[7]<.3)throw Error('Actual WASD input failed');await ui.keyboard.press('Escape');await ui.waitForFunction(()=>document.pointerLockElement===null);await ui.locator('#resolution').selectOption('2560');await ui.waitForFunction(()=>engine.width===2560);await new Promise(r=>setTimeout(r,400));if(await ui.evaluate(()=>window.__error))throw Error(await ui.evaluate(()=>window.__error));
 await ui.screenshot({path:`${captures}/interface.png`});await ui.close();
 const report={...route,timings,captureResolution:[1920,1080],actualBrowserInput:true,ultraResolution:true,captures};await fs.writeFile(`${captures}/validation.json`,JSON.stringify(report,null,2));await fs.writeFile('captures/latest.json',JSON.stringify(report,null,2));console.log('Browser walkthrough and images PASS',captures);
}finally{await browser?.close();await new Promise(r=>server.close(r));}

