import {GpuRuntime} from '../vendor/cuda-webshader/src/runtime/runtime.js';
export class BuildingEngine{
 constructor(canvas){this.canvas=canvas;this.kernels={};this.buffers={};this.sample=0;this.errors=[];this.seed=240921;this.lotX=0;this.lotZ=0;this.resident=true;this.rebuilds=0;this.width=0;this.height=0;this.quality=1;}
 set sample(value){this._sample=value;if(value===0&&this.buffers?.C)this.runtime.write(this.buffers.C,new Float32Array([0]),9*4);}
 get sample(){return this._sample;}
 async init(progress=()=>{}){
  this.runtime=await GpuRuntime.create({onError:e=>this.errors.push(String(e?.message||e))});this.device=this.runtime.device;this.context=this.canvas.getContext('webgpu');
  this.device.lost.then(info=>{this.errors.push('Device lost: '+info.message);window.dispatchEvent(new CustomEvent('gpu-error',{detail:info.message}));});
  const names=['generateScene','describeLayout','morton','sortPairs','leaves','parents','initCamera','simulate','accumulate','render'];
  for(let i=0;i<names.length;i++){const n=names[i];progress(`Preparing ${n} · ${i+1}/${names.length}`);const response=await fetch(`generated/${n}.json`);if(!response.ok)throw Error('Run npm run build first: missing '+n);const a=await response.json();this.kernels[n]=await this.runtime.kernel(a);}
  for(const [name,floats]of Object.entries({s:32+32768*16,nodes:65536*8,keys:65536,C:16,I:8,Plan:64}))this.buffers[name]=this.runtime.createBuffer(floats*4,{label:name});
  await this.resize(1920,1080);progress('Generating rooms and stairs…');await this.build(this.seed);await this.view(1);return this;
 }
 bind(name,scalars={}){return this.kernels[name].bind(Object.fromEntries(this.kernels[name].artifact.metadata.bindings.map(b=>[b.name,this.buffers[b.name]])),scalars);}
 async build(seed,lotX=this.lotX,lotZ=this.lotZ,resident=true){if(![lotX,lotZ].every(v=>Number.isInteger(v)&&Math.abs(v)<=1000000))throw Error("Lot coordinates must be integers between -1000000 and 1000000.");if(!Number.isInteger(seed)||seed<0||seed>16777215)throw Error('Seed must be an integer from 0 to 16777215.');await this.runtime.idle();this.seed=seed;this.lotX=lotX;this.lotZ=lotZ;this.resident=resident;this.rebuilds++;
  this.runtime.batch().dispatch(this.bind('generateScene',{seed,lotX,lotZ,resident:resident?1:0}),[1]).dispatch(this.bind('describeLayout'),[1]).dispatch(this.bind('morton'),[512]).submit();
  const batch=this.runtime.batch();for(let stage=2;stage<=32768;stage*=2)for(let stride=stage/2;stride;stride>>=1)batch.dispatch(this.bind('sortPairs',{stage,stride}),[512]);batch.dispatch(this.bind('leaves'),[512]);for(let start=16384;start;start>>=1)batch.dispatch(this.bind('parents',{start}),[Math.ceil(start/64)]);batch.submit();await this.runtime.idle();
  const state=await this.runtime.read(this.buffers.s,Float32Array,16,0);this.shapes=state[0];this.collisionShapes=state[1];this.layout=Array.from(await this.runtime.read(this.buffers.Plan));if(state[2])throw Error('Building geometry capacity exceeded');this.sample=0;
 }
 async stream(){
  const c=await this.camera(),dx=Math.floor((c[0]+20)/40),dz=Math.floor((c[2]+20)/40);
  const x=this.lotX+dx,z=this.lotZ+dz;if(Math.abs(x)>1000000||Math.abs(z)>1000000)return false;
  const px=c[0]-dx*40,pz=c[2]-dz*40;
  // Conservative envelope for every footprint; hysteresis avoids churn at the boundary.
  const distance=Math.hypot(Math.max(0,Math.abs(px)-10.5),Math.max(0,Math.abs(pz-1.5)-11));
  const resident=distance<(this.resident&&!dx&&!dz?11:8);
  if(!dx&&!dz&&resident===this.resident)return false;
  await this.build(this.seed,x,z,resident);c[0]=px;c[2]=pz;this.setCamera(c);return true;
 }
 async resize(width,height){width=Math.ceil(width/64)*64;height=Math.max(64,Math.round(height));if(width===this.width&&height===this.height)return;await this.runtime.idle();
  for(const n of ['pixels','history'])if(this.buffers[n])this.runtime.destroyBuffer(this.buffers[n]);
  this.width=width;this.height=height;this.buffers.pixels=this.runtime.createBuffer(width*height*4);this.buffers.history=this.runtime.createBuffer(width*height*16);
  this.canvas.width=width;this.canvas.height=height;this.context.configure({device:this.device,format:'rgba8unorm',usage:GPUTextureUsage.COPY_DST|GPUTextureUsage.RENDER_ATTACHMENT,alphaMode:'opaque'});this.sample=0;
 }
 async view(view){this.runtime.batch().dispatch(this.bind('initCamera',{view}),[1]).submit();await this.runtime.idle();this.sample=0;}
 async camera(){return Array.from(await this.runtime.read(this.buffers.C));}
 setCamera(values){this.runtime.write(this.buffers.C,new Float32Array(values));this.sample=0;}
 step(input,steps){this.runtime.write(this.buffers.I,new Float32Array([...input,...Array(8-input.length).fill(0)]));this.runtime.batch().dispatch(this.bind('simulate',{steps}),[1]).submit();}
 draw(){const b=this.runtime.batch();b.dispatch(this.bind('render',{w:this.width,h:this.height,quality:this.quality}),[Math.ceil(this.width/64),this.height]).dispatch(this.bind('accumulate'),[1]).endPass();b.encoder.copyBufferToTexture({buffer:this.buffers.pixels.gpuBuffer,bytesPerRow:this.width*4,rowsPerImage:this.height},{texture:this.context.getCurrentTexture()},[this.width,this.height]);b.submit();}
 async pixels(){const words=await this.runtime.read(this.buffers.pixels,Uint32Array);return new Uint8Array(words.buffer,words.byteOffset,words.byteLength);}
}
