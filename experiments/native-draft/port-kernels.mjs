// One-time migration of the authored CUDA scene to the portable flat-buffer ABI.
// Runtime uses kernels/building.cu directly; this is not a JS scene generator.
import fs from 'node:fs/promises';
const native=await fs.readFile(new URL('../native/building.cu',import.meta.url),'utf8');
const pre=`#define CAP 4096
#define PI 3.14159265359f
#define PLASTER 0
#define BRICK 1
#define WOOD 2
#define CONCRETE 3
#define METAL 4
#define FABRIC 5
#define GLASS 6
#define LIGHT 7
#define TILE 8
#define LEAF 9
#define ASPHALT 10
struct Shape { float3 lo; float3 hi; float3 color; unsigned int id; int mat; int solid; };
struct Node { float3 lo; float3 hi; int shape; };
struct Camera { float3 foot; float yaw; float pitch; float vy; int grounded; float distance; };
struct Input { float forward; float side; float dx; float dy; int sprint; int jump; };
__device__ float dot(float3 a,float3 b){return a.x*b.x+a.y*b.y+a.z*b.z;}
__device__ float3 cross(float3 a,float3 b){return make_float3(a.y*b.z-a.z*b.y,a.z*b.x-a.x*b.z,a.x*b.y-a.y*b.x);}
__device__ float3 norm(float3 a){return a*(1.0f/sqrtf(fmaxf(0.000000000001f,dot(a,a))));}
__device__ float3 vmin(float3 a,float3 b){return make_float3(fminf(a.x,b.x),fminf(a.y,b.y),fminf(a.z,b.z));}
__device__ float3 vmax(float3 a,float3 b){return make_float3(fmaxf(a.x,b.x),fmaxf(a.y,b.y),fmaxf(a.z,b.z));}
__device__ float clamp(float x,float a=0.0f,float b=1.0f){return fminf(b,fmaxf(a,x));}
__device__ float3 lerp(float3 a,float3 b,float t){return a*(1.0f-t)+b*t;}
__device__ unsigned int mix(unsigned int x){x^=x>>16;x*=2146121005u;x^=x>>15;x*=2221713035u;return x^(x>>16);}
__device__ float randf(unsigned int x){return (float)(mix(x)&16777215u)/16777216.0f;}
__device__ float fract(float x){return x-floorf(x);}
__device__ Shape readShape(const float* s,int index){int b=16+index*16;Shape o;o.lo=make_float3(s[b],s[b+1],s[b+2]);o.hi=make_float3(s[b+3],s[b+4],s[b+5]);o.color=make_float3(s[b+6],s[b+7],s[b+8]);o.mat=(int)s[b+9];o.solid=(int)s[b+10];o.id=mix((unsigned int)s[1]^(unsigned int)index);return o;}
__device__ void box(float* s,float3 p,float3 half,int mat,float3 color,bool solid=true){int i=(int)s[0];if(i>=CAP){s[2]=1.0f;return;}s[0]=(float)(i+1);int b=16+i*16;float3 lo=p-half,hi=p+half;s[b]=lo.x;s[b+1]=lo.y;s[b+2]=lo.z;s[b+3]=hi.x;s[b+4]=hi.y;s[b+5]=hi.z;s[b+6]=color.x;s[b+7]=color.y;s[b+8]=color.z;s[b+9]=(float)mat;s[b+10]=solid?1.0f:0.0f;}
__device__ Node readNode(const float* nodes,int i){int b=i*8;Node n;n.lo=make_float3(nodes[b],nodes[b+1],nodes[b+2]);n.hi=make_float3(nodes[b+3],nodes[b+4],nodes[b+5]);n.shape=(int)nodes[b+6];return n;}
__device__ void writeNode(float* nodes,int i,Node n){int b=i*8;nodes[b]=n.lo.x;nodes[b+1]=n.lo.y;nodes[b+2]=n.lo.z;nodes[b+3]=n.hi.x;nodes[b+4]=n.hi.y;nodes[b+5]=n.hi.z;nodes[b+6]=(float)n.shape;}
__device__ Camera readCam(const float* C){Camera c;c.foot=make_float3(C[0],C[1],C[2]);c.yaw=C[3];c.pitch=C[4];c.vy=C[5];c.grounded=(int)C[6];c.distance=C[7];return c;}
__device__ void writeCam(float* C,Camera c){C[0]=c.foot.x;C[1]=c.foot.y;C[2]=c.foot.z;C[3]=c.yaw;C[4]=c.pitch;C[5]=c.vy;C[6]=(float)c.grounded;C[7]=c.distance;}
`;
let geometry=native.slice(native.indexOf('__device__ void between'),native.indexOf('HD U spread'));
geometry=geometry.replace('s->count=0;s->overflow=0;s->seed=seed;','s[0]=0;s[2]=0;s[1]=(float)seed;');
const accel=`
__device__ unsigned int spread(unsigned int x){x&=1023u;x=(x|(x<<16))&0x030000ffu;x=(x|(x<<8))&0x0300f00fu;x=(x|(x<<4))&0x030c30c3u;x=(x|(x<<2))&0x09249249u;return x;}
__global__ void morton(const float* s,unsigned int* keys){int i=(int)(blockIdx.x*blockDim.x+threadIdx.x);if(i>=CAP)return;keys[i*2+1]=(unsigned int)i;if(i>=(int)s[0]){keys[i*2]=4294967295u;return;}Shape o=readShape(s,i);float3 p=(o.lo+o.hi)*0.5f;unsigned int x=(unsigned int)(clamp((p.x+20.0f)/40.0f)*1023.0f),y=(unsigned int)(clamp((p.y+1.0f)/12.0f)*1023.0f),z=(unsigned int)(clamp((p.z+25.0f)/45.0f)*1023.0f);keys[i*2]=spread(x)|(spread(y)<<1)|(spread(z)<<2);}
__global__ void sortPairs(unsigned int* keys,int stage,int stride){int i=(int)(blockIdx.x*blockDim.x+threadIdx.x);int j=i^stride;if(i>=CAP||j<=i)return;bool up=(i&stage)==0;unsigned int a=keys[i*2],b=keys[j*2],ai=keys[i*2+1],bi=keys[j*2+1];bool greater=a>b||(a==b&&ai>bi);if(greater==up){keys[i*2]=b;keys[i*2+1]=bi;keys[j*2]=a;keys[j*2+1]=ai;}}
__global__ void leaves(const float* s,const unsigned int* keys,float* nodes){int i=(int)(blockIdx.x*blockDim.x+threadIdx.x);if(i>=CAP)return;int j=(int)keys[i*2+1];Node n;if(j<(int)s[0]){Shape o=readShape(s,j);n.lo=o.lo;n.hi=o.hi;n.shape=j;}else{n.lo=make_float3(1e20f,1e20f,1e20f);n.hi=make_float3(-1e20f,-1e20f,-1e20f);n.shape=-1;}writeNode(nodes,CAP+i,n);}
__global__ void parents(float* nodes,int start){int i=(int)(blockIdx.x*blockDim.x+threadIdx.x);if(i>=start)return;int j=start+i;Node a=readNode(nodes,j*2),b=readNode(nodes,j*2+1),n;n.lo=vmin(a.lo,b.lo);n.hi=vmax(a.hi,b.hi);n.shape=-1;writeNode(nodes,j,n);}
`;
let rendering=native.slice(native.indexOf('__device__ float bound'),native.indexOf('// Player is'));
rendering=rendering.replace('const Camera* camera,U* pixels,V* history','const float* C,unsigned int* pixels,float* history').replace('Camera cam=*camera;','Camera cam=readCam(C);');
rendering=rendering.replace('Hit hit{maxT,-1,V()};','Hit hit;hit.t=maxT;hit.id=-1;hit.n=V(0,0,0);');
rendering=rendering.replace('if(sample>0)color=lerp(history[i],color,1.f/(sample+1));history[i]=color;','if(sample>0)color=lerp(make_float3(history[i*4],history[i*4+1],history[i*4+2]),color,1.f/(sample+1));history[i*4]=color.x;history[i*4+1]=color.y;history[i*4+2]=color.z;');
rendering=rendering.replace('0xff000000u|(bytes[0]<<16)|(bytes[1]<<8)|bytes[2]','0xff000000u|bytes[0]|(bytes[1]<<8)|(bytes[2]<<16)');
let physics=native.slice(native.indexOf('__device__ bool overlap'),native.indexOf('struct Engine{'));
physics=physics.replace('void horizontal(const Scene* s,Camera& c','Camera horizontal(const Scene* s,Camera c');
physics=physics.replaceAll('return;','return c;');
physics=physics.replace('if(freeBody(s,target))c.foot=target;','if(freeBody(s,target))c.foot=target;return c;');
physics=physics.replace('Camera* cam,Input input,int steps','float* C,const float* I,int steps');
physics=physics.replace('if(threadIdx.x||blockIdx.x)return c;Camera c=*cam;','if(threadIdx.x||blockIdx.x)return;Camera c=readCam(C);Input input;input.forward=I[0];input.side=I[1];input.dx=I[2];input.dy=I[3];input.sprint=(int)I[4];input.jump=(int)I[5];');
physics=physics.replace('horizontal(s,c,d.x,0);horizontal(s,c,d.z,2);','c=horizontal(s,c,d.x,0);c=horizontal(s,c,d.z,2);').replace('}*cam=c;','}writeCam(C,c);');
physics=physics.replace('constexpr float dt=1.f/120;','float dt=1.f/120;');
const init=`
__global__ void initCamera(float* C,int view){if(threadIdx.x||blockIdx.x)return;for(int i=0;i<16;++i)C[i]=0.0f;C[2]=-15.0f;
if(view==1){C[0]=15;C[1]=3;C[2]=-22;C[3]=-.65f;C[4]=.04f;}
if(view==2){C[0]=.2f;C[2]=-7;C[3]=.08f;C[4]=.02f;}
if(view==3){C[0]=-2.6f;C[2]=-6.5f;C[3]=-.87f;C[4]=-.06f;}
if(view==4){C[0]=-.3f;C[2]=3.8f;C[3]=.03f;C[4]=.18f;}
if(view==5){C[2]=4.7f;C[1]=6.4f;C[3]=PI;C[4]=-.03f;}}
`;
let code=geometry+accel+rendering+physics+init;
code=code.replaceAll('const Scene*','const float*').replaceAll('Scene*','float*').replaceAll('const Node*','const float*').replaceAll('s->seed','((unsigned int)s[1])').replaceAll('s->count','((int)s[0])');
code=code.replace(/s->objects\[([^\]]+)\]/g,'readShape(s,$1)').replace(/nodes\[([^\]]+)\]/g,'readNode(nodes,$1)');
code=code.replace(/\bU\b/g,'unsigned int').replace(/\bV\(/g,'make_float3(').replace(/\bV\b/g,'float3').replace(/static_cast<int>\(([^()]*)\)/g,'(int)($1)').replace(/static_cast<unsigned int>\(([^()]*)\)/g,'(unsigned int)($1)');
// Constructor-style local vector declarations -> CUDA built-in vector constructors.
code=code.replace(/(?<!__device__ )\bfloat3\s+([A-Za-z_][\w]*)\(/g,'float3 $1=make_float3(');
// Handle multiple vector declarations in a single statement explicitly.
for(const name of ['brick','floorWood','dark','right','inv','b','c','h','v','f','up'])code=code.replace(new RegExp(',('+name+')\\(','g'),',$1=make_float3(');
code=code.replaceAll('make_float3()','make_float3(0,0,0)');
code=code.replace('roundf((p.z+6)/3.5f)','floorf((p.z+6)/3.5f+0.5f)');
await fs.mkdir(new URL('../kernels/',import.meta.url),{recursive:true});await fs.writeFile(new URL('../kernels/building.cu',import.meta.url),pre+code);
