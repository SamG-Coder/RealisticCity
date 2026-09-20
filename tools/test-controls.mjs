import {chromium} from 'playwright';
import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import {createServer} from '../server.mjs';
const server=createServer();await new Promise(r=>server.listen(0,'127.0.0.1',r));
let browser;
await fs.mkdir('captures',{recursive:true});
try{
 browser=await chromium.launch({channel:'msedge',headless:true,args:['--enable-unsafe-webgpu']});
 for(const failure of ['none','promise','event','throw']){
  const page=await browser.newPage({viewport:{width:1000,height:700}}),errors=[];
  page.on('pageerror',e=>errors.push(String(e)));
  await page.addInitScript(failure=>{
   const original=HTMLCanvasElement.prototype.requestPointerLock;
   HTMLCanvasElement.prototype.requestPointerLock=function(){
    window.captureHadActivation=navigator.userActivation.isActive;
    if(failure==='none')return original.call(this);
    const error=new DOMException('If you see this error we have a bug. Please report this bug to chromium.','UnknownError');
    if(failure==='promise')return Promise.reject(error);
    if(failure==='throw')throw error;
    setTimeout(()=>document.dispatchEvent(new Event('pointerlockerror')),0);
   };
  },failure);
  await page.goto(`http://127.0.0.1:${server.address().port}/?resolution=1280`);
  await page.waitForFunction(()=>window.__ready||window.__error,null,{timeout:120000});
  assert.equal(await page.evaluate(()=>window.__error),undefined);
  await page.locator('#enter').click();
  await page.waitForFunction(()=>document.body.classList.contains('walking'));
  assert.equal(await page.evaluate(()=>window.captureHadActivation),true,'Capture needs the original click activation');
  if(failure==='none')await page.waitForFunction(()=>document.pointerLockElement!==null);
  else await page.waitForFunction(()=>document.querySelector('#control-hint').textContent.includes('drag to look'));
  const start=await page.evaluate(()=>engine.camera());
  await page.keyboard.down('KeyW');
  await page.waitForFunction(distance=>engine.camera().then(c=>c[7]>distance+.4),start[7]);
  await page.keyboard.up('KeyW');
  if(failure!=='none'){
   const yaw=(await page.evaluate(()=>engine.camera()))[3];
   await page.mouse.move(480,540);await page.mouse.down();await page.mouse.move(580,540,{steps:8});await page.mouse.up();
   await page.waitForFunction(yaw=>engine.camera().then(c=>c[3]>yaw+.15),yaw);
   // Editing the seed must not move the player in fallback mode.
   await page.locator('#seed').focus();const before=(await page.evaluate(()=>engine.camera()))[7];
   await page.keyboard.down('KeyW');await page.waitForTimeout(200);await page.keyboard.up('KeyW');
   assert.ok(Math.abs((await page.evaluate(()=>engine.camera()))[7]-before)<.02);
  }
  await page.keyboard.press('Escape');
  await page.waitForFunction(()=>document.pointerLockElement===null&&document.querySelector('#control-hint').textContent.startsWith('Paused'));
  const stopped=(await page.evaluate(()=>engine.camera()))[7];
  await page.keyboard.down('KeyW');await page.waitForTimeout(200);await page.keyboard.up('KeyW');
  assert.ok(Math.abs((await page.evaluate(()=>engine.camera()))[7]-stopped)<.02,'Escape must stop walking');
  await page.mouse.click(480,540);
  await page.keyboard.down('KeyW');await page.waitForFunction(distance=>engine.camera().then(c=>c[7]>distance+.3),stopped);await page.keyboard.up('KeyW');
  assert.equal(await page.evaluate(()=>window.__error),undefined);assert.deepEqual(errors,[]);
  assert.equal(await page.locator('#error').isVisible(),false);
  if(failure==='promise')await page.screenshot({path:'captures/pointer-fallback.png'});
  console.log('PASS controls:',failure==='none'?'real pointer lock':`${failure} rejection → drag fallback`);
  await page.close();
 }
}finally{await browser?.close();await new Promise(r=>server.close(r));}
