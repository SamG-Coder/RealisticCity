import {chromium} from 'playwright';
import fs from 'node:fs/promises';
import assert from 'node:assert/strict';
import {createServer} from '../server.mjs';
const server=createServer();await new Promise(r=>server.listen(0,'127.0.0.1',r));let browser;
try{
 browser=await chromium.launch({channel:'msedge',headless:true,args:['--enable-unsafe-webgpu']});const page=await browser.newPage();
 await page.goto('http://127.0.0.1:'+server.address().port+'/?test');await page.waitForFunction(()=>window.__ready||window.__error,null,{timeout:240000});assert.equal(await page.evaluate(()=>window.__error),undefined);
 const result=await page.evaluate(async()=>{
  const e=engine,types=new Set(),finishes=new Set(),plans=[],shots=[],captured=new Set(),floorShots=new Set();await e.resize(1280,720);
  const capture=async name=>{for(let i=0;i<12;i++){e.draw();await e.runtime.idle();}const c=document.createElement('canvas');c.width=e.width;c.height=e.height;c.getContext('2d').putImageData(new ImageData(new Uint8ClampedArray(await e.pixels()),c.width,c.height),0,0);shots.push({name,png:c.toDataURL('image/png').split(',')[1]});};
  for(const seed of [240921,17,0,71,821,2026]){
   await e.build(seed,0,0,true);if(!e.hasBuilding)continue;const p=[...e.layout];plans.push({seed,width:p[0],depth:p[1],floors:p[2],rooms:p.slice(32,32+p[2]*4)});
   const geometry=await e.runtime.read(e.buffers.s,Float32Array,(32+e.shapes*16)*4);if(geometry[2])throw Error('Geometry overflow');for(let i=0;i<e.shapes;i++){const b=32+i*16;for(let a=0;a<3;a++)if(!Number.isFinite(geometry[b+a])||geometry[b+a]>geometry[b+3+a])throw Error('Invalid bounds');}
   for(let f=0;f<p[2];f++)for(let r=0;r<4;r++){
    const type=p[32+f*4+r],finish=p[48+f*4+r];types.add(type);finishes.add(finish);if((type===8||type===9)&&![19,20,22].includes(finish))throw Error("Wet room has unsuitable flooring");const z=p[16+f*4+r]/p[1],split=r<2?2*z+8:2*z-5.4;if(split < -3.251 || split>.651)throw Error('Room depth outside safe range');
    {const side=r%2?1:-1,a=p[13],x=side*3.35*p[0],zz=p[16+f*4+r];e.runtime.write(e.buffers.I,new Float32Array([Math.cos(a)*x+Math.sin(a)*zz,p[8+f]+.25,-Math.sin(a)*x+Math.cos(a)*zz,0,-1,0]));e.runtime.batch().dispatch(e.bind('probeRay'),[1]).submit();const hit=await e.runtime.read(e.buffers.Plan,Float32Array,12,56*4);if(hit[2]!==finish)throw Error('Rendered room floor does not match its seed: '+hit[2]+' / '+finish);}
    if(!floorShots.has(finish)){floorShots.add(finish);const side=r%2?1:-1,a=p[13],x=side*3.3*p[0],zz=p[16+f*4+r]-1.7*p[1];e.setCamera([Math.cos(a)*x+Math.sin(a)*zz,p[8+f],-Math.sin(a)*x+Math.cos(a)*zz,a+side*.9,-.55,0,0,0,...Array(8).fill(0)]);await capture('floor-'+finish);}
    if([8,9,10,11].includes(type)&&!captured.has(type)){
     captured.add(type);const side=r%2?1:-1,a=p[13],x=side*3.55*p[0],zz=p[16+f*4+r]-1.45*p[1];e.setCamera([Math.cos(a)*x+Math.sin(a)*zz,p[8+f],-Math.sin(a)*x+Math.cos(a)*zz,a+side*.85,-.12,0,0,0,...Array(8).fill(0)]);await capture('room-'+type);
    }
   }
   if(plans.length<=3){await e.view(1);await capture('house-'+seed);}
   await e.build(seed,0,0,false);const unloaded=[...e.layout];await e.build(seed,0,0,true);if(p.some((v,i)=>v!==e.layout[i]))throw Error('Resident seed changed');if(p.some((v,i)=>i!==7&&v!==unloaded[i]))throw Error('Virtual plan mismatch');
  }
  return {plans,finishes:[...finishes].sort((a,b)=>a-b),types:[...types].sort((a,b)=>a-b),shots,errors:e.errors};
 });
 assert.deepEqual(result.errors,[]);assert.deepEqual(result.finishes,[17,18,19,20,21,22]);for(const type of [0,1,3,4,5,8,9,10,11])assert.ok(result.types.includes(type),'Missing room type '+type);assert.ok(new Set(result.plans.map(p=>p.width.toFixed(2)+','+p.depth.toFixed(2))).size>=3);
 await fs.mkdir('captures/variance',{recursive:true});for(const shot of result.shots)await fs.writeFile('captures/variance/'+shot.name+'.png',Buffer.from(shot.png,'base64'));
 const labels={'floor-17':'Timber boards','floor-18':'Parquet','floor-19':'Tiles','floor-20':'Checker tiles','floor-21':'Carpet','floor-22':'Terrazzo','room-8':'Bathroom','room-9':'Utility / laundry','room-10':'Library','room-11':'Studio'};await fs.writeFile('captures/variance/review.html','<!doctype html><meta charset="utf-8"><title>Seeded building variation</title><style>body{background:#182022;color:#eee;font:16px system-ui;margin:32px}main{display:grid;grid-template-columns:repeat(2,minmax(0,1fr));gap:24px}img{width:100%}h1{font-weight:500}figure{margin:0}figcaption{padding:12px 0}</style><h1>Seeded building variation</h1><p>Same building shader. Address-derived proportions, room assignments and facade details.</p><main>'+result.shots.map(s=>'<figure><img src="'+s.name+'.png"><figcaption>'+(labels[s.name]||s.name)+'</figcaption></figure>').join('')+'</main>');delete result.shots;await fs.writeFile('captures/variance/report.json',JSON.stringify(result,null,2));console.log(JSON.stringify(result,null,2));
}finally{await browser?.close();await new Promise(r=>server.close(r));}
