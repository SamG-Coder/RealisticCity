// Pointer capture is optional: embedded browsers can reject it even with a click.
export function createWalkControls(canvas,onMode,onSpeed=()=>{}){
 const keys=new Set();let active=false,pending=false,fallback=false,dragging=false,dx=0,dy=0,jump=false,lastX=0,lastY=0;
 canvas.tabIndex=0;
 const locked=()=>document.pointerLockElement===canvas;
 const clear=()=>{keys.clear();dx=dy=0;jump=false;dragging=false;};
 function notify(){onMode(active?(fallback?'drag':'locked'):'paused');}
 function denied(){if(!pending||!active)return;pending=false;fallback=true;clear();canvas.focus({preventScroll:true});notify();}
 function pause(){active=false;pending=false;clear();if(locked())document.exitPointerLock();notify();}
 function enter(){
  if(active)return;
  active=true;clear();canvas.focus({preventScroll:true});
  if(fallback){notify();return;}
  pending=true;
  // Call synchronously inside the user's click, before any GPU work is awaited.
  try{const request=canvas.requestPointerLock();request?.catch(denied);}catch{denied();}
 }
 document.addEventListener('pointerlockerror',denied);
 document.addEventListener('pointerlockchange',()=>{
  if(locked()){pending=false;fallback=false;active=true;clear();notify();}
  else if(!pending&&!fallback){active=false;clear();notify();}
 });
 canvas.addEventListener('mousedown',event=>{if(active&&fallback&&event.button===0){dragging=true;lastX=event.clientX;lastY=event.clientY;canvas.focus({preventScroll:true});event.preventDefault();}});
 document.addEventListener('mouseup',()=>{dragging=false;});
 document.addEventListener('mousemove',event=>{
  if(!active)return;
  if(locked()){dx+=event.movementX;dy+=event.movementY;}
  else if(fallback&&dragging){dx+=event.clientX-lastX;dy+=event.clientY-lastY;lastX=event.clientX;lastY=event.clientY;}
 });
 document.addEventListener('keydown',event=>{
  if(event.code==='Escape'){pause();return;}
  if(!active||event.target!==canvas&&!locked())return;
  if(['KeyW','KeyA','KeyS','KeyD','ShiftLeft','ShiftRight','Space','KeyE','KeyQ','ControlLeft'].includes(event.code)){
   keys.add(event.code);if(event.code==='Space'&&!event.repeat)jump=true;event.preventDefault();
  }
 });
 canvas.addEventListener('wheel',event=>{if(active){event.preventDefault();onSpeed(event.deltaY);}}, {passive:false});
 document.addEventListener('keyup',event=>keys.delete(event.code));
 canvas.addEventListener('blur',()=>{clear();});
 window.addEventListener('blur',pause);
 document.addEventListener('visibilitychange',()=>{if(document.hidden)pause();});
 return {enter,pause,get active(){return active;},input(steps){
  const down=k=>keys.has(k)?1:0;
  const value=[down('KeyW')-down('KeyS'),down('KeyD')-down('KeyA'),dx,dy,down('ShiftLeft')||down('ShiftRight'),jump?1:0,0,0,Math.max(down('Space'),down('KeyE'))-Math.max(down('KeyQ'),down('ControlLeft'))];
  dx=dy=0;if(steps>0)jump=false;return value;
 }};
}
