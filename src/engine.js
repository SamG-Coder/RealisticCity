import {GpuRuntime} from '../vendor/cuda-webshader/src/runtime/runtime.js';
export class BuildingEngine{
 constructor(canvas){this.canvas=canvas;this.kernels={};this.invocations={};this.buffers={};this.sample=0;this.errors=[];this.seed=240921;this.lotX=0;this.lotZ=0;this.resident=true;this.rebuilds=0;this.radius=5;this.flying=false;this.flySpeed=12;this.width=0;this.height=0;this.quality=1;this.cacheEnabled=true;this.temporalEnabled=true;this.shadowBlurEnabled=true;}
 set sample(value){this._sample=value;if(value===0&&this.buffers?.C){this.runtime.write(this.buffers.C,new Float32Array([0]),9*4);if(this.buffers.MotionHistory)this.runtime.write(this.buffers.MotionHistory,new Float32Array([0]),(this.width*this.height*4+16)*4);}}
 get sample(){return this._sample;}
 async init(progress=()=>{}){
  this.runtime=await GpuRuntime.create({onError:e=>this.errors.push(String(e?.message||e))});this.device=this.runtime.device;this.context=this.canvas.getContext('webgpu');
  this.device.lost.then(info=>{this.errors.push('Device lost: '+info.message);window.dispatchEvent(new CustomEvent('gpu-error',{detail:info.message}));});
  const names=['prepareDistricts','generateScene','probeOutdoor','probeRay','probeStreet','describeLayout','morton','sortPairs','leaves','parents','initCamera','simulate','accumulate','farVisibility','movingShadows','render','temporalResolve','rememberFrame'];
  for(let i=0;i<names.length;i++){const n=names[i];progress(`Preparing ${n} · ${i+1}/${names.length}`);const response=await fetch(`generated/${n}.json`);if(!response.ok)throw Error('Run npm run build first: missing '+n);const a=await response.json();this.kernels[n]=await this.runtime.kernel(a);}
  for(const [name,floats]of Object.entries({s:32+262144*16,nodes:524288*8,keys:524288,C:16,I:16,Plan:64,Districts:16384*8}))this.buffers[name]=this.runtime.createBuffer(floats*4,{label:name});
  await this.resize(1920,1080);progress('Generating rooms and stairs…');await this.build(this.seed);await this.view(1);return this;
 }
 // Dispatch snapshots scalar values; reuse bindings even across BVH sort stages.
 bind(name,scalars={}){let invocation=this.invocations[name];if(!invocation){invocation=this.kernels[name].bind(Object.fromEntries(this.kernels[name].artifact.metadata.bindings.map(b=>[b.name,this.buffers[b.name]])),scalars);this.invocations[name]=invocation;}else if(Object.keys(scalars).length)invocation.setScalars(scalars);return invocation;}
 async build(seed,lotX=this.lotX,lotZ=this.lotZ,resident=true){if(![lotX,lotZ].every(v=>Number.isInteger(v)&&Math.abs(v)<=1000000))throw Error("Lot coordinates must be integers between -1000000 and 1000000.");if(!Number.isInteger(seed)||seed<0||seed>16777215)throw Error('Seed must be an integer from 0 to 16777215.');await this.runtime.idle();this.seed=seed;this.lotX=lotX;this.lotZ=lotZ;this.resident=resident;this.rebuilds++;
  if(this.cacheEnabled)this.runtime.batch().dispatch(this.bind('prepareDistricts',{seed,centerX:lotX,centerZ:lotZ}),[256]).submit();
  this.runtime.batch().dispatch(this.bind('generateScene',{seed,lotX,lotZ,resident:resident?1:0,radius:this.radius,cacheEnabled:this.cacheEnabled?1:0}),[1]).dispatch(this.bind('describeLayout'),[1]).submit();
  const state=await this.runtime.read(this.buffers.s,Float32Array,128,0);this.hasBuilding=state[8]>0;this.resident=resident&&this.hasBuilding;this.shapes=state[0];this.collisionShapes=state[1];if(state[2])throw Error('Building geometry capacity exceeded');
  const capacity=2**Math.ceil(Math.log2(this.shapes));this.runtime.write(this.buffers.s,new Float32Array([capacity]),23*4);
  const batch=this.runtime.batch();batch.dispatch(this.bind('morton'),[capacity/64]);for(let stage=2;stage<=capacity;stage*=2)for(let stride=stage/2;stride;stride>>=1)batch.dispatch(this.bind('sortPairs',{stage,stride}),[capacity/64]);batch.dispatch(this.bind('leaves'),[capacity/64]);for(let start=capacity/2;start;start>>=1)batch.dispatch(this.bind('parents',{start}),[Math.ceil(start/64)]);batch.submit();await this.runtime.idle();
  this.layout=Array.from(await this.runtime.read(this.buffers.Plan));this.sample=0;
 }
 async stream(camera=null){
  const c=camera??await this.camera(),dx=Math.floor((c[0]+20)/40),dz=Math.floor((c[2]+20)/40);
  const x=this.lotX+dx,z=this.lotZ+dz;if(Math.abs(x)>1000000||Math.abs(z)>1000000)return false;
  const px=c[0]-dx*40,pz=c[2]-dz*40;
  // Conservative envelope for every footprint; hysteresis avoids churn at the boundary.
  const distance=Math.hypot(Math.max(0,Math.abs(px)-10.5),Math.max(0,Math.abs(pz-1.5)-11));
  const resident=(dx!==0||dz!==0||this.hasBuilding)&&c[1]<20&&distance<(this.resident&&!dx&&!dz?11:8);
  if(!dx&&!dz&&resident===this.resident)return false;
  await this.build(this.seed,x,z,resident);c[0]=px;c[2]=pz;this.setCamera(c);return true;
 }
 async setFly(enabled){if(enabled===this.flying)return;if(!enabled){await this.stream();if(!this.resident)await this.build(this.seed,this.lotX,this.lotZ,true);const c=await this.camera();c[5]=0;c[6]=0;this.setCamera(c);}this.flying=enabled;}
 async setDistance(radius){if(![2,5,10].includes(radius))throw Error('Unsupported view distance');this.radius=radius;await this.build(this.seed,this.lotX,this.lotZ,this.resident);}
 async resize(width,height){width=Math.ceil(width/64)*64;height=Math.max(64,Math.round(height));if(width===this.width&&height===this.height)return;await this.runtime.idle();
  // Bind groups retain buffer references, so resizing invalidates the cache.
  this.invocations={};
  for(const n of ['pixels','history','Far','Glass','MotionHistory','MotionSurface','Shadows'])if(this.buffers[n])this.runtime.destroyBuffer(this.buffers[n]);
  this.width=width;this.height=height;this.buffers.Shadows=this.runtime.createBuffer(width*height*4);this.buffers.MotionHistory=this.runtime.createBuffer((width*height*4+32)*4);this.buffers.MotionSurface=this.runtime.createBuffer(width*height*32);this.buffers.Far=this.runtime.createBuffer(width*height*64);this.buffers.Glass=this.runtime.createBuffer(width*height*16);this.buffers.pixels=this.runtime.createBuffer(width*height*4);this.buffers.history=this.runtime.createBuffer(width*height*16);
  this.canvas.width=width;this.canvas.height=height;this.context.configure({device:this.device,format:'rgba8unorm',usage:GPUTextureUsage.COPY_DST|GPUTextureUsage.RENDER_ATTACHMENT,alphaMode:'opaque'});this.sample=0;
 }
 async view(view){this.runtime.batch().dispatch(this.bind('initCamera',{view}),[1]).submit();await this.runtime.idle();this.sample=0;}
 async camera(){return Array.from(await this.runtime.read(this.buffers.C));}
 setCamera(values){this.runtime.write(this.buffers.C,new Float32Array(values));this.sample=0;}
 step(input,steps){const values=new Float32Array(16);values.set(input);values[6]=this.flying?1:0;values[7]=this.flySpeed;this.runtime.write(this.buffers.I,values);this.runtime.batch().dispatch(this.bind('simulate',{steps}),[1]).submit();}
 draw(){const b=this.runtime.batch();b.dispatch(this.bind('farVisibility',{w:this.width,h:this.height,cacheEnabled:this.cacheEnabled?1:0}),[Math.ceil(this.width/64),this.height]);b.dispatch(this.bind('movingShadows',{w:this.width,h:this.height,enabled:this.shadowBlurEnabled?1:0}),[Math.ceil(this.width/64),this.height]);b.dispatch(this.bind('render',{w:this.width,h:this.height,quality:this.quality}),[Math.ceil(this.width/64),this.height]).dispatch(this.bind('temporalResolve',{w:this.width,h:this.height,enabled:this.temporalEnabled?1:0}),[Math.ceil(this.width/64),this.height]).dispatch(this.bind('rememberFrame',{w:this.width,h:this.height,enabled:this.temporalEnabled?1:0}),[Math.ceil(this.width*this.height/64)]).dispatch(this.bind('accumulate'),[1]).endPass();b.encoder.copyBufferToTexture({buffer:this.buffers.pixels.gpuBuffer,bytesPerRow:this.width*4,rowsPerImage:this.height},{texture:this.context.getCurrentTexture()},[this.width,this.height]);b.submit();}
 async pixels(){const words=await this.runtime.read(this.buffers.pixels,Uint32Array);return new Uint8Array(words.buffer,words.byteOffset,words.byteLength);}
}
