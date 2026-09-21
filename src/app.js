import {BuildingEngine} from './engine.js';
import {createWalkControls} from './walk-controls.js';
const $=id=>document.getElementById(id),canvas=$('world'),params=new URLSearchParams(location.search);let paused=params.has('test'),entered=false,busy=true,acc=0,previous=performance.now(),fps=0,lastHud=0;
function fail(error){console.error(error);$('error').hidden=false;$('error').textContent=error.stack||String(error);$('status').textContent='ERROR';window.__error=String(error);}
window.addEventListener('gpu-error',event=>fail(Error(event.detail)));
const engine=window.engine=new BuildingEngine(canvas);
function describe(){ $('economy').textContent=`${engine.hasBuilding?'Home':'Land'} value · ${Math.round(engine.layout[15]*100)} / 100 · District ${'$'.repeat(engine.layout[14]<.35?1:engine.layout[14]>.65?3:2)}`; $('lot-x').value=engine.lotX;$('lot-z').value=engine.lotZ;$('building-kind').textContent=engine.hasBuilding?`${engine.layout[2]} FLOORS · ${['RESIDENTIAL','WORKSPACE','MIXED USE'][engine.layout[4]]}`:'DISTRICT OPEN SPACE';$('residency').textContent=!engine.hasBuilding?`Open land · ${(engine.radius*2+1)**2} plots cached`:engine.resident?`${engine.layout[2]*4} rooms resident · ${(engine.radius*2+1)**2} cached`:`Interiors evicted · ${(engine.radius*2+1)**2} cached`;}
try{
 await engine.init(message=>$('loading').textContent=message);if(params.has('seed'))await engine.build(Number(params.get('seed')));$('seed').value=engine.seed;describe();
 const resize=async()=>{const width=Number($('resolution').value);await engine.resize(width,Math.round(width*innerHeight/innerWidth));};
 if(params.has('resolution'))$('resolution').value=params.get('resolution');if(paused)await engine.resize(640,360);else await resize();
 $('enter').disabled=false;$('enter').innerHTML='Walk inside <span>↗</span>';$('loading').textContent='Click to enter · Esc releases your pointer';$('status').textContent='READY';busy=false;window.__ready=true;
 const hint=document.createElement('div');hint.id='control-hint';hint.setAttribute('role','status');hint.hidden=true;document.body.append(hint);
 const controls=createWalkControls(canvas,mode=>{
  document.body.classList.toggle('walking',entered);$('crosshair').hidden=mode==='paused';
  hint.hidden=mode==='locked';hint.textContent=mode==='drag'?'Mouse capture unavailable · WASD to walk · Hold left mouse and drag to look · Esc to pause':'Paused · Click the scene to resume';
 },delta=>{if(engine.flying){engine.flySpeed=Math.max(1,Math.min(240,engine.flySpeed*Math.exp(-Math.max(-240,Math.min(240,delta))*.002)));$('speed').textContent=`${engine.flySpeed.toFixed(1)} m/s · wheel adjusts`;}});
 async function enter(){if(busy)return;controls.enter();if(!entered){busy=true;try{await engine.view(0);entered=true;document.body.classList.add('walking');}finally{busy=false;}}}
 $('enter').onclick=()=>enter().catch(fail);canvas.onclick=()=>enter().catch(fail);
 document.addEventListener('keydown',event=>{if(event.target.matches('input,select'))return;if(event.code==='KeyH'&&!event.repeat)document.body.classList.toggle('hide-ui');if(event.code==='KeyF'&&!event.repeat)$('fly').click();if(event.code==='KeyR'&&!event.repeat)$('entrance').click();});
 $('regenerate').onclick=async()=>{if(busy)return;busy=true;$('status').textContent='GENERATING';try{await engine.build(Number($('seed').value),Number($('lot-x').value),Number($('lot-z').value));describe();await engine.view(entered?0:1);$('status').textContent='READY';}catch(e){fail(e);}finally{busy=false;}};
 $('entrance').onclick=async()=>{if(busy)return;await engine.view(0);entered=true;document.body.classList.add('walking');};
 $('fly').onclick=async()=>{if(busy)return;busy=true;try{await engine.setFly(!engine.flying);$('fly').textContent=engine.flying?'Fly mode · F → Drop':'Walk mode · F → Fly';$('speed').textContent=engine.flying?engine.flySpeed.toFixed(1)+' m/s · wheel adjusts':'Gravity and collisions';describe();}catch(e){fail(e);}finally{busy=false;}};
 $('distance').onchange=async()=>{if(busy)return;busy=true;try{await engine.setDistance(Number($('distance').value));describe();}catch(e){fail(e);}finally{busy=false;}};
 $('resolution').onchange=async()=>{busy=true;try{await resize();}catch(e){fail(e);}finally{busy=false;}};
 $('lighting').onchange=()=>{engine.quality=$('lighting').checked?1:0;engine.sample=0;};
 $('fullscreen').onclick=()=>{if(document.fullscreenElement)document.exitFullscreen();else document.documentElement.requestFullscreen();};
 let resizeTimer;window.addEventListener('resize',()=>{clearTimeout(resizeTimer);resizeTimer=setTimeout(()=>$('resolution').onchange(),250);});
 $('capture').onclick=async()=>{try{await engine.runtime.idle();const data=await engine.pixels(),out=document.createElement('canvas');out.width=engine.width;out.height=engine.height;out.getContext('2d').putImageData(new ImageData(new Uint8ClampedArray(data),out.width,out.height),0,0);out.toBlob(blob=>{const url=URL.createObjectURL(blob),a=document.createElement('a');a.href=url;a.download=`stratum-${engine.seed}.png`;a.click();setTimeout(()=>URL.revokeObjectURL(url),1000);});}catch(e){fail(e);}};
 async function frame(time){if(paused)return;try{const dt=Math.min(.10,(time-previous)/1000);previous=time;if(!busy){if(controls.active){acc+=dt;const steps=Math.min(12,Math.floor(acc*120));acc-=steps/120;engine.step(controls.input(steps),steps);}else acc=0;engine.draw();await engine.runtime.idle();fps=fps*.92+(1/Math.max(.001,dt))*.08;if(time-lastHud>200){lastHud=time;const c=await engine.camera();if(entered&&await engine.stream(c))describe();let floor=1;for(let f=1;f<engine.layout[2];f++)if(c[1]+.05>=engine.layout[8+f])floor=f+1;$('floor').textContent=engine.flying?`Flying · ${Math.round(c[1])} m`:entered?(engine.hasBuilding?`Floor ${floor} / ${engine.layout[2]}`:"Open district land"):'Exterior';$('fps').textContent=`${Math.round(fps)} fps`;}}requestAnimationFrame(frame);}catch(e){fail(e);}}
 if(!paused)requestAnimationFrame(frame);
}catch(e){fail(e);}
