#define CAP 262144
#define GROUND 11
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
#define VIRTUAL_WINDOW 12
#define VIRTUAL_DOOR 13
#define UPHOLSTERY 14
#define CERAMIC 15
#define BASIN 16
#define FLOOR_WOOD 17
#define FLOOR_PARQUET 18
#define FLOOR_TILE 19
#define FLOOR_CHECK 20
#define FLOOR_CARPET 21
#define FLOOR_TERRAZZO 22
struct Shape { float3 lo; float3 hi; float3 color; float3 origin; float angle; unsigned int id; int mat; int solid; };
struct Hit{float t;int id;float3 n;Shape feature;float visibility;};
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
// World address -> building DNA -> independent floor/room/property channels.
// The full 32-bit key is stored as two exact 16-bit float words.
__device__ unsigned int buildingKey(float* s){return (unsigned int)s[3]|((unsigned int)s[4]<<16);}
__device__ float floorBase(float* s,int floor){return s[10+floor];}
__device__ unsigned int roomKey(float* s,int floor,int side,int back){return mix(buildingKey(s)^mix((unsigned int)floor*101u+(side<0?17u:29u)+(unsigned int)back*43u));}
// Address-derived proportions are shared by geometry, residency and virtual rooms.
__device__ float houseWidth(unsigned int key,float value){int form=(int)(mix(key^811u)%3u);return (form==0?.92f:(form==1?1.06f:.98f))+.035f*value+.025f*randf(key^101u);}
__device__ float houseDepth(unsigned int key,float value){int form=(int)(mix(key^811u)%3u);return (form==0?1.08f:(form==1?.93f:1.0f))+.025f*value+.025f*randf(key^102u);}
__device__ float3 roomAccent(unsigned int key){int palette=(int)(mix(key^817u)%5u);float3 c=palette==0?make_float3(.23f,.36f,.44f):(palette==1?make_float3(.38f,.44f,.28f):(palette==2?make_float3(.53f,.28f,.22f):(palette==3?make_float3(.61f,.47f,.27f):make_float3(.55f,.51f,.44f))));return c*(.88f+.24f*randf(key));}
__device__ float roomSplit(float* s,int floor,int side){return -3.25f+randf(roomKey(s,floor,side,0)^713u)*3.9f;}
__device__ float roomZ(float* s,int floor,int side,int back){float split=roomSplit(s,floor,side);return back?(split+5.4f)*.5f:(-8.0f+split)*.5f;}
__device__ int roomType(float* s,int floor,int side,int back){unsigned int key=buildingKey(s);int slot=back*2+(side>0?1:0);slot=(slot+(int)(mix(key^9821u)%4u))%4;int use=(int)s[7];if(use==1)return slot==0?2:(slot==1?11:(slot==2?8:1));if(floor==0)return slot==0?0:(slot==1?1:(slot==2?3:8));if(slot==0)return 4;if(slot==1)return floor==1?5:9;if(slot==2)return 8;return (mix(roomKey(s,floor,side,back)^991u)%2u)==0u?10:11;}
// Floor finishes are independent of furnishing and facade randomness.
__device__ int floorFinish(unsigned int key,int type){unsigned int choice=mix(key^0x464C4F52u);if(type==8||type==9)return (choice%3u)==0u?FLOOR_TERRAZZO:((choice%3u)==1u?FLOOR_TILE:FLOOR_CHECK);if(type==4||type==5)return (choice%4u)<3u?FLOOR_CARPET:FLOOR_WOOD;if(type==1)return (choice%2u)==0u?FLOOR_TILE:FLOOR_WOOD;return FLOOR_WOOD+(int)(choice%5u);}
__device__ float3 floorColor(unsigned int key,int finish){int palette=(int)(mix(key^0x434F4C52u)%4u);if(finish==FLOOR_WOOD||finish==FLOOR_PARQUET)return palette==0?make_float3(.42f,.25f,.12f):(palette==1?make_float3(.23f,.12f,.065f):(palette==2?make_float3(.61f,.46f,.29f):make_float3(.37f,.31f,.25f)));if(finish==FLOOR_CARPET)return palette==0?make_float3(.25f,.31f,.33f):(palette==1?make_float3(.40f,.34f,.28f):(palette==2?make_float3(.28f,.32f,.22f):make_float3(.39f,.22f,.20f)));return palette==0?make_float3(.61f,.58f,.49f):(palette==1?make_float3(.29f,.34f,.36f):(palette==2?make_float3(.60f,.49f,.39f):make_float3(.42f,.46f,.40f)));}
__device__ void buildingDNA(float* s,unsigned int key,float value,unsigned int style){s[3]=(float)(key&65535u);s[4]=(float)(key>>16);s[5]=houseWidth(key,value);s[6]=houseDepth(key,value);s[7]=randf(key^103u)<.8f?0:(float)(1u+mix(key^103u)%2u);s[8]=(float)(value<.35f?3+(int)(mix(key^104u)%2u):(value>.65f?2:2+(int)(mix(key^104u)%2u)));s[9]=(float)(randf(key^105u)<.8f?mix(style^105u)%3u:mix(key^105u)%3u);s[10]=0.0f;for(int f=1;f<=4;++f)s[10+f]=s[9+f]+3.08f+.27f*randf(mix(key^(unsigned int)f)^106u);}
// Disjoint seed namespaces: region terrain and shared road edges never depend on house DNA.
__device__ unsigned int regionKey(unsigned int seed,int x,int z){return mix(seed^294731u^mix((unsigned int)x*1597334677u)^mix((unsigned int)z*3812015801u));}
__device__ float3 rotateY(float3 p,float a){float c=cosf(a),v=sinf(a);return make_float3(c*p.x+v*p.z,p.y,-v*p.x+c*p.z);}
// Rounded furniture stays one BVH primitive, with bounded local intersections.
__device__ float furnitureDistance(float3 p,float3 radius,int mat){
 if(mat==BASIN){float3 a=make_float3(p.x/radius.x,p.y/radius.y,p.z/radius.z);float outer=(sqrtf(dot(a,a))-1)*fminf(radius.x,fminf(radius.y,radius.z));float3 inner=make_float3(radius.x*.81f,radius.y*.93f,radius.z*.81f);float3 b=make_float3(p.x/inner.x,(p.y-radius.y*.42f)/inner.y,p.z/inner.z);float cavity=(sqrtf(dot(b,b))-1)*fminf(inner.x,fminf(inner.y,inner.z));return fmaxf(outer,-cavity);}
 float r=fminf(mat==UPHOLSTERY?.105f:.035f,fminf(radius.x,fminf(radius.y,radius.z))*.65f);float3 q=make_float3(fabsf(p.x)-radius.x+r,fabsf(p.y)-radius.y+r,fabsf(p.z)-radius.z+r),outside=vmax(q,make_float3(0,0,0));return sqrtf(dot(outside,outside))+fminf(fmaxf(q.x,fmaxf(q.y,q.z)),0)-r;
}
// Shared exact primitive intersection for resident BVH leaves and procedural queries.
__device__ Hit intersectShape(Shape o,float3 ro,float3 rd,float limit,bool shadow){
 Hit h;h.id=-1;h.t=limit;h.n=make_float3(0,0,0);if(shadow&&(o.mat==GLASS||o.mat==LIGHT||o.mat==VIRTUAL_WINDOW||o.mat==VIRTUAL_DOOR))return h;
 float3 lr=rotateY(ro-o.origin,-o.angle)+o.origin,ld=rotateY(rd,-o.angle);
 if(o.mat==VIRTUAL_WINDOW||o.mat==VIRTUAL_DOOR){float cx=((o.lo.x+o.hi.x)*.5f-o.origin.x)/o.color.y;float3 outward=fabsf(cx)>8?make_float3(cx>0?1.f:-1.f,0,0):make_float3(0,0,-1);if(dot(ld,outward)>=-1e-7f)return h;}
 float3 inv=make_float3(1/(fabsf(ld.x)<1e-8f?(ld.x<0?-1e-8f:1e-8f):ld.x),1/(fabsf(ld.y)<1e-8f?(ld.y<0?-1e-8f:1e-8f):ld.y),1/(fabsf(ld.z)<1e-8f?(ld.z<0?-1e-8f:1e-8f):ld.z));
 float3 a=(o.lo-lr)*inv,b=(o.hi-lr)*inv,mn=vmin(a,b),mx=vmax(a,b);float near=fmaxf(mn.x,fmaxf(mn.y,mn.z)),far=fminf(mx.x,fminf(mx.y,mx.z));if(far<fmaxf(near,.001f))return h;float t=near>.001f?near:far;
 float3 center=(o.lo+o.hi)*.5f,radius=(o.hi-o.lo)*.5f;
 if(o.mat==LEAF){float3 q=make_float3((lr.x-center.x)/radius.x,(lr.y-center.y)/radius.y,(lr.z-center.z)/radius.z),d=make_float3(ld.x/radius.x,ld.y/radius.y,ld.z/radius.z);float aa=dot(d,d),bb=dot(q,d),cc=dot(q,q)-1,disc=bb*bb-aa*cc;if(disc<0)return h;t=(-bb-sqrtf(disc))/aa;if(t<.001f)t=(-bb+sqrtf(disc))/aa;}
 if(o.mat==UPHOLSTERY||o.mat==CERAMIC||o.mat==BASIN){t=fmaxf(near,.0011f);bool found=false;for(int step=0;step<48;++step){float distance=furnitureDistance(lr+ld*t-center,radius,o.mat);if(fabsf(distance)<.00025f){found=true;break;}t+=fmaxf(fabsf(distance),.00015f);if(t>far||t>=limit)break;}if(!found)return h;}
 if(t<=.001f||t>=limit)return h;float3 p=lr+ld*t,v=make_float3((p.x-center.x)/fmaxf(.00001f,radius.x),(p.y-center.y)/fmaxf(.00001f,radius.y),(p.z-center.z)/fmaxf(.00001f,radius.z));
 if(fabsf(v.x)>fabsf(v.y)&&fabsf(v.x)>fabsf(v.z))h.n=make_float3(v.x>0?1.f:-1.f,0,0);else if(fabsf(v.y)>fabsf(v.z))h.n=make_float3(0,v.y>0?1.f:-1.f,0);else h.n=make_float3(0,0,v.z>0?1.f:-1.f);
 if(o.mat==LEAF)h.n=norm(make_float3((p.x-center.x)/(radius.x*radius.x),(p.y-center.y)/(radius.y*radius.y),(p.z-center.z)/(radius.z*radius.z)));
 if(o.mat==UPHOLSTERY||o.mat==CERAMIC||o.mat==BASIN){float3 local=p-center;float e=.0004f;h.n=norm(make_float3(furnitureDistance(local+make_float3(e,0,0),radius,o.mat)-furnitureDistance(local-make_float3(e,0,0),radius,o.mat),furnitureDistance(local+make_float3(0,e,0),radius,o.mat)-furnitureDistance(local-make_float3(0,e,0),radius,o.mat),furnitureDistance(local+make_float3(0,0,e),radius,o.mat)-furnitureDistance(local-make_float3(0,0,e),radius,o.mat)));}
 h.n=rotateY(h.n,o.angle);h.t=t;h.id=0;h.feature=o;return h;
}
// Fixed domain tags keep independent random groups from rerolling each other.
// Economic values are procedural design indices, not real currency prices.
__device__ int highwayOffset(unsigned int seed){return (int)(mix(seed^0x48575953u)%64u);}
__device__ unsigned int highwayGroup(unsigned int seed,int x,int z){return regionKey(seed^0x48574752u,(int)floorf((float)(x-highwayOffset(seed))/64),(int)floorf((float)z/64));}
__device__ unsigned int districtKey(unsigned int seed,int x,int z){return regionKey(highwayGroup(seed,x,z)^0x45434F4Eu,(int)floorf((float)(x-highwayOffset(seed))/32),(int)floorf((float)z/32));}
__device__ float districtValue(unsigned int seed,int x,int z){return .1f+.8f*randf(districtKey(seed,x,z));}
// Smooth value field: adjacent addresses sample the same seeded anchors.
__device__ float economicAnchor(unsigned int seed,int x,int z){return clamp(districtValue(seed,x*8+highwayOffset(seed),z*8)+(randf(regionKey(seed^0x56414C55u,x,z))-.5f)*.12f);}
__device__ float highwayDistance(unsigned int seed,int x){float phase=fract(((float)(x-highwayOffset(seed))+.5f)/64.0f)*64.0f;return fminf(phase,64.0f-phase)*40.0f;}
__device__ float neighbourhoodValue(unsigned int seed,int x,int z){float gx=(float)(x-highwayOffset(seed))/8.0f,gz=(float)z/8.0f;int ix=(int)floorf(gx),iz=(int)floorf(gz);float u=fract(gx),v=fract(gz);u=u*u*(3-2*u);v=v*v*(3-2*v);float a=economicAnchor(seed,ix,iz)*(1-u)+economicAnchor(seed,ix+1,iz)*u,b=economicAnchor(seed,ix,iz+1)*(1-u)+economicAnchor(seed,ix+1,iz+1)*u;return clamp(a*(1-v)+b*v-.12f*clamp(1-highwayDistance(seed,x)/200.0f));}
__device__ float propertyValue(unsigned int seed,int x,int z){return clamp(neighbourhoodValue(seed,x,z)+(randf(regionKey(seed^0x50524943u,x,z))-.5f)*.03f);}
__device__ unsigned int neighbourhoodKey(unsigned int seed,int x,int z){int nx=(int)floorf((float)(x-highwayOffset(seed))/8),nz=(int)floorf((float)z/8);unsigned int region=districtKey(seed,x,z);return regionKey(region^0x4E454947u,nx,nz);}
struct Street {float3 a;float3 b;float3 control;float3 end;float width;int active;int kind;int terminal;};
__device__ float3 roadNode(unsigned int seed,int x,int z){unsigned int k=regionKey(neighbourhoodKey(seed,x,z)^87139u,x,z);return make_float3((x-.5f)*40.0f+(randf(k)-.5f)*7.0f,0,(z-.5f)*40.0f+(randf(k^781u)-.5f)*7.0f);}
// 0 connector, 1 local street, 2 lane, 3 court, 4 crescent, 5 loop, 6 highway.
// A road group owns an entire access street, not one 40m address edge.
// Courts branch off a local street, run through several plots, and end once.
__device__ Street street(unsigned int seed,int x,int z,int axis){Street r;r.a=roadNode(seed,x,z);r.b=roadNode(seed,x+(axis==0?1:0),z+(axis==1?1:0));r.end=r.b;r.terminal=0;
 int lx=x-highwayOffset(seed),mx=lx-(int)floorf((float)lx/8)*8,mz=z-(int)floorf((float)z/4)*4;
 int groupX=(int)floorf((float)lx/4),groupZ=(int)floorf((float)z/4);unsigned int group=neighbourhoodKey(seed,x,z),k=regionKey(group^0x524F4144u,groupX,groupZ);
 bool major=axis==1&&lx%64==0,collector=(axis==1&&mx==0)||(axis==0&&z%16==0),local=axis==0&&mz==0;
 int preferred=2+(int)(mix(group^0x54595045u)%4u);int family=preferred;
 r.kind=major?6:(collector?0:(local?1:family));r.active=major||collector||local?1:0;
 if(axis==1&&mx%4==2){r.active=1;if(family==3){bool reverse=randf(k^0x454E5452u)>.5f;r.active=reverse?(mz>0?1:0):(mz<3?1:0);r.terminal=reverse?(mz==1?1:0):(mz==2?1:0);if(reverse){float3 a=r.a;r.a=r.b;r.b=a;r.end=r.b;}}}
 // Local roads do not each get a highway entrance. District connectors own access.
 int highwayPhase=lx-(int)floorf((float)lx/64)*64;
 int corridor=highwayPhase==63?x+1:x;int entry=(int)(mix(seed^(unsigned int)corridor^0x454E5459u)%2u)*16;int entryPhase=z-(int)floorf((float)z/32)*32;
 if(axis==0&&(highwayPhase==0||highwayPhase==63)&&entryPhase!=entry)r.active=0;
 r.width=r.kind==6?5.0f:(r.kind==0?3.6f:(r.kind==2?1.55f:(r.kind==3?2.25f:(r.kind==5?1.65f:2.65f))));
 unsigned int sizeGroup=regionKey(seed^0x53495A45u,r.kind==6?x:groupX,r.kind==6?0:groupZ);r.width+=randf(sizeGroup)*.4f;
 if(r.terminal){bool reverse=randf(k^0x454E5452u)>.5f;r.b=r.a+(r.b-r.a)*(.7f+randf(k^71u)*.15f);r.end=roadNode(seed,x,z-mz+(reverse?0:4));}
 float3 d=norm(r.b-r.a),normal=make_float3(d.z,0,-d.x);r.control=(r.a+r.b)*.5f+normal*(r.kind==4?4.0f:0.0f);return r;}
__device__ float3 streetPoint(Street r,float t){return r.a*((1-t)*(1-t))+r.control*(2*t*(1-t))+r.b*(t*t);}
__device__ float3 closestSegment(float3 a,float3 b,float3 p){float3 d=b-a;return a+d*clamp(dot(p-a,d)/fmaxf(.0001f,dot(d,d)));}
__device__ float3 closestStreet(Street r,float3 p){float best=1e20f;float3 closest=r.a;for(int j=0;j<6;++j){float3 q=closestSegment(streetPoint(r,j/6.0f),streetPoint(r,(j+1)/6.0f),p);float dd=dot(q-p,q-p);if(dd<best){best=dd;closest=q;}}return closest;}
__device__ Street frontage(unsigned int seed,int x,int z){Street best=street(seed,x,z,0);float score=1e9f;float3 center=make_float3(x*40.0f,0,z*40.0f);for(int dz=-1;dz<=2;++dz)for(int dx=-1;dx<=2;++dx)for(int axis=0;axis<2;++axis){Street r=street(seed,x+dx,z+dz,axis);if(!r.active||r.kind==6)continue;float3 q=closestStreet(r,center);float rank=dot(q-center,q-center);if(rank<score){score=rank;best=r;}}return best;}
__device__ bool buildablePlot(unsigned int seed,int x,int z){Street r=frontage(seed,x,z);float3 center=make_float3(x*40.0f,0,z*40.0f),d=closestStreet(r,center)-center;return r.active&&r.kind!=6&&dot(d,d)<35.0f*35.0f;}
__device__ float buildingAngle(unsigned int seed,int x,int z){Street r=frontage(seed,x,z);float3 center=make_float3(x*40.0f,0,z*40.0f),normal=norm(closestStreet(r,center)-center);return atan2f(-normal.x,-normal.z);}
// Persistent exact plot descriptors; direct-mapped world addresses retain entries on rebasing.
struct Plot {float angle;float value;int available;};
__device__ Plot describePlot(unsigned int seed,int x,int z){Street access=frontage(seed,x,z);float3 center=make_float3(x*40.0f,0,z*40.0f),delta=closestStreet(access,center)-center,normal=norm(delta);Plot p;p.angle=atan2f(-normal.x,-normal.z);p.value=propertyValue(seed,x,z);p.available=access.active&&access.kind!=6&&dot(delta,delta)<35.0f*35.0f?1:0;return p;}
__device__ int plotSlot(int x,int z){return ((x%128+128)%128)+((z%128+128)%128)*128;}
__device__ Plot cachedPlot(const float* Districts,unsigned int seed,int x,int z,int enabled){int b=plotSlot(x,z)*8;if(enabled&&Districts[b+3]==1&&Districts[b]==(float)x&&Districts[b+1]==(float)z&&Districts[b+2]==(float)seed){Plot p;p.angle=Districts[b+4];p.value=Districts[b+5];p.available=(int)Districts[b+6];return p;}return describePlot(seed,x,z);}
__global__ void prepareDistricts(float* Districts,unsigned int seed,int centerX,int centerZ){int i=(int)(blockIdx.x*blockDim.x+threadIdx.x);if(i>=16384)return;int x=centerX+i%128-64,z=centerZ+i/128-64,b=plotSlot(x,z)*8;if(Districts[b+3]==1&&Districts[b]==(float)x&&Districts[b+1]==(float)z&&Districts[b+2]==(float)seed)return;Plot p=describePlot(seed,x,z);Districts[b]=(float)x;Districts[b+1]=(float)z;Districts[b+2]=(float)seed;Districts[b+4]=p.angle;Districts[b+5]=p.value;Districts[b+6]=(float)p.available;Districts[b+7]+=1;Districts[b+3]=1;}
__device__ float3 regionColor(unsigned int seed,int x,int z){float v=randf(regionKey(seed,x,z));return lerp(make_float3(.19f,.26f,.105f),make_float3(.38f,.36f,.20f),v);}
__device__ float3 outdoorMaterial(float* s,float3 p,float footprint){
    unsigned int seed=(unsigned int)s[22];float wx=p.x+s[20]*40.0f,wz=p.z+s[21]*40.0f;float3 point=make_float3(wx,0,wz);
    int cx=(int)floorf((wx+20)/40),cz=(int)floorf((wz+20)/40);
    float gx=wx/320.0f,gz=wz/320.0f;int ix=(int)floorf(gx),iz=(int)floorf(gz);float u=fract(gx),v=fract(gz);u=u*u*(3-2*u);v=v*v*(3-2*v);
    float3 color=lerp(lerp(regionColor(seed,ix,iz),regionColor(seed,ix+1,iz),u),lerp(regionColor(seed,ix,iz+1),regionColor(seed,ix+1,iz+1),u),v);
    float noise=randf((unsigned int)(int)floorf(wx*70)*73856093u^(unsigned int)(int)floorf(wz*70)*19349663u^seed),micro=clamp(1-footprint*35);
    float best=1e9f,dist=0,along=0,length=0,width=0;int kind=0,edgeX=0,edgeZ=0,edgeAxis=0;bool pedestrian=false;
    for(int dz=-1;dz<=1;++dz)for(int dx=-1;dx<=1;++dx)for(int axis=0;axis<2;++axis){Street r=street(seed,cx+dx,cz+dz,axis);if(!r.active)continue;float3 d=r.b-r.a;float len=sqrtf(dot(d,d)),t=clamp(dot(point-r.a,d)/(len*len));float3 q=closestStreet(r,point);float dd=sqrtf(dot(point-q,point-q)),w=r.width;if(r.terminal&&dot(point-r.b,point-r.b)<64.0f){dd=sqrtf(dot(point-r.b,point-r.b));w=8.0f;}if(dd-w<best){best=dd-w;dist=dd;along=t*len;length=len;width=w;kind=r.kind;edgeX=cx+dx;edgeZ=cz+dz;edgeAxis=axis;}if(r.terminal){float3 pathPoint=closestSegment(r.b,r.end,point);if(dot(point-pathPoint,point-pathPoint)<.8f*.8f)pedestrian=true;}}
    bool path=false;Street front=frontage(seed,cx,cz);float3 center=make_float3(cx*40.0f,0,cz*40.0f),delta=closestStreet(front,center)-center;float len=sqrtf(dot(delta,delta));float longitudinal=dot(point-center,delta)/len,lateral=fabsf((point.x-center.x)*delta.z-(point.z-center.z)*delta.x)/len;path=len<35&&longitudinal>7&&longitudinal<len&&lateral<1.35f;
    if(best<0){color=make_float3(.105f,.12f,.125f);
        Street pa=street(seed,edgeX,edgeZ,1-edgeAxis),pb=street(seed,edgeX-(edgeAxis==1?1:0),edgeZ-(edgeAxis==0?1:0),1-edgeAxis);
        int bx=edgeX+(edgeAxis==0?1:0),bz=edgeZ+(edgeAxis==1?1:0);Street qa=street(seed,bx,bz,1-edgeAxis),qb=street(seed,bx-(edgeAxis==1?1:0),bz-(edgeAxis==0?1:0),1-edgeAxis);
        bool atStart=pa.active||pb.active,atEnd=qa.active||qb.active,junction=(atStart&&along<5)||(atEnd&&along>length-5);
        if((kind<2||kind==6)&&!junction&&((dist<.07f&&fract(along/5)<.5f)||fabsf(dist-(width-.23f))<.045f))color=make_float3(.81f,.79f,.65f);
        if(kind==6){if(dist<.12f)color=make_float3(.85f,.69f,.29f);else if(fabsf(dist-width*.5f)<.045f&&fract(along/7)<.55f)color=make_float3(.82f,.82f,.74f);}
        if(kind<2&&((atStart&&fabsf(along-6)<.65f)||(atEnd&&fabsf(along-(length-6))<.65f))&&fract(dist/.8f)<.5f)color=make_float3(.82f,.82f,.74f);
    }else if(best<2||path||pedestrian){color=make_float3(.57f,.56f,.50f);float seam=fminf(fminf(fract(wx/.8f),1-fract(wx/.8f)),fminf(fract(wz/.8f),1-fract(wz/.8f)));if(seam<.016f&&footprint<.04f)color=color*.73f;}
    return color*(1+(noise-.5f)*.15f*micro);
}
__device__ Shape readShape(float* s,int index){int b=32+index*16;Shape o;o.lo=make_float3(s[b],s[b+1],s[b+2]);o.hi=make_float3(s[b+3],s[b+4],s[b+5]);o.color=make_float3(s[b+6],s[b+7],s[b+8]);o.mat=(int)s[b+9];o.solid=(int)s[b+10];o.origin=make_float3(s[b+13],0,s[b+14]);o.angle=s[b+15];o.id=(unsigned int)s[b+11]^((unsigned int)s[b+12]<<16);return o;}
__device__ void box(float* s,float3 p,float3 half,int mat,float3 color,bool solid=true){
 int i=(int)s[0];if(i>=CAP){s[2]=1;return;}s[0]=(float)(i+1);p.x=p.x*s[5]+s[16];p.z=p.z*s[6]+s[17];half.x*=s[5];half.z*=s[6];float3 lo=p-half,hi=p+half;int b=32+i*16;

 s[b]=lo.x;s[b+1]=lo.y;s[b+2]=lo.z;s[b+3]=hi.x;s[b+4]=hi.y;s[b+5]=hi.z;s[b+6]=color.x;s[b+7]=color.y;s[b+8]=color.z;s[b+9]=(float)mat;s[b+10]=solid&&s[26]<.5f?1:0;s[b+11]=s[3];s[b+12]=s[4];s[b+13]=s[16];s[b+14]=s[17];s[b+15]=s[18];
}

__device__ Node readNode(const float* nodes,int i){int b=i*8;Node n;n.lo=make_float3(nodes[b],nodes[b+1],nodes[b+2]);n.hi=make_float3(nodes[b+3],nodes[b+4],nodes[b+5]);n.shape=(int)nodes[b+6];return n;}
__device__ void writeNode(float* nodes,int i,Node n){int b=i*8;nodes[b]=n.lo.x;nodes[b+1]=n.lo.y;nodes[b+2]=n.lo.z;nodes[b+3]=n.hi.x;nodes[b+4]=n.hi.y;nodes[b+5]=n.hi.z;nodes[b+6]=(float)n.shape;}
__device__ Camera readCam(const float* C){Camera c;c.foot=make_float3(C[0],C[1],C[2]);c.yaw=C[3];c.pitch=C[4];c.vy=C[5];c.grounded=(int)C[6];c.distance=C[7];return c;}
__device__ void writeCam(float* C,Camera c){C[0]=c.foot.x;C[1]=c.foot.y;C[2]=c.foot.z;C[3]=c.yaw;C[4]=c.pitch;C[5]=c.vy;C[6]=(float)c.grounded;C[7]=c.distance;}
__device__ void between(float* s,float3 lo,float3 hi,int mat,float3 c,bool solid=true){box(s,(lo+hi)*.5f,(hi-lo)*.5f,mat,c,solid);}
__device__ void leg(float* s,float x,float y,float z,float height){box(s,make_float3(x,y+height*.5f,z),make_float3(.035f,height*.5f,.035f),METAL,make_float3(.11f,.13f,.13f));}
__device__ void table(float* s,float x,float y,float z,float width,float depth){
    box(s,make_float3(x,y+.76f,z),make_float3(width*.5f,.045f,depth*.5f),WOOD,make_float3(.55f,.32f,.15f));
    for(int a=-1;a<=1;a+=2)for(int b=-1;b<=1;b+=2)leg(s,x+a*(width*.5f-.12f),y,z+b*(depth*.5f-.12f),.72f);
}
__device__ void chair(float* s,float x,float y,float z,float3 col,int face=1){
    box(s,make_float3(x,y+.45f,z),make_float3(.24f,.055f,.23f),UPHOLSTERY,col);
    box(s,make_float3(x,y+.77f,z+face*.20f),make_float3(.24f,.28f,.05f),UPHOLSTERY,col);
    for(int a=-1;a<=1;a+=2)for(int b=-1;b<=1;b+=2)leg(s,x+a*.18f,y,z+b*.17f,.42f);
}
__device__ void plant(float* s,float x,float y,float z,float size=1){
    box(s,make_float3(x,y+.2f*size,z),make_float3(.18f*size,.2f*size,.18f*size),CONCRETE,make_float3(.68f,.58f,.44f));
    box(s,make_float3(x,y+.7f*size,z),make_float3(.025f,.5f*size,.025f),WOOD,make_float3(.2f,.16f,.07f),false);
    for(int i=0;i<7;++i){float a=i*2.4f;box(s,make_float3(x+cosf(a)*.16f*size,y+(.6f+i*.08f)*size,z+sinf(a)*.16f*size),make_float3(.22f*size,.055f*size,.15f*size),LEAF,make_float3(.13f,.27f,.09f),false);}
}
__device__ void art(float* s,float x,float y,float z,int side,unsigned int seed){
    box(s,make_float3(x,y,z),make_float3(.045f,.62f,.83f),WOOD,make_float3(.2f,.12f,.07f),false);
    box(s,make_float3(x-side*.05f,y,z),make_float3(.015f,.56f,.77f),PLASTER,make_float3(.88f,.83f,.73f),false);
    for(int i=0;i<4;++i)box(s,make_float3(x-side*.07f,y+(randf(seed+i)-.5f)*.65f,z+(randf(seed+20+i)-.5f)*.9f),make_float3(.01f,.1f+randf(seed+40+i)*.16f,.1f+randf(seed+80+i)*.18f),PLASTER,make_float3(.15f+randf(seed+i)*.35f,.24f+randf(seed+60+i)*.2f,.22f),false);
}
__device__ void specialRoom(float* s,int type,int side,float y,float z,unsigned int key,float3 accent){
    if(type==8){
        // Bath rim, recessed basin, vanity and toilet. Keep the doorway clear.
        box(s,make_float3(side*7.25f,y+.08f,z-.65f),make_float3(.75f,.08f,1.20f),CERAMIC,make_float3(.82f,.84f,.79f));
        for(int edge=-1;edge<=1;edge+=2){box(s,make_float3(side*7.25f+edge*.67f,y+.32f,z-.65f),make_float3(.08f,.20f,1.20f),CERAMIC,make_float3(.82f,.84f,.79f));box(s,make_float3(side*7.25f,y+.32f,z-.65f+edge*1.12f),make_float3(.59f,.20f,.08f),CERAMIC,make_float3(.82f,.84f,.79f));}
        box(s,make_float3(side*7.25f,y+.18f,z-.65f),make_float3(.58f,.015f,1.02f),CERAMIC,make_float3(.49f,.62f,.62f));
        box(s,make_float3(side*4.65f,y+.42f,z+1.35f),make_float3(.65f,.42f,.43f),WOOD,accent);
        box(s,make_float3(side*4.65f,y+.88f,z+1.35f),make_float3(.69f,.04f,.47f),CERAMIC,make_float3(.89f,.89f,.84f));
        box(s,make_float3(side*6.6f,y+.18f,z+1.52f),make_float3(.19f,.18f,.25f),CERAMIC,make_float3(.72f,.75f,.73f));
        box(s,make_float3(side*6.6f,y+.43f,z+1.38f),make_float3(.34f,.18f,.44f),BASIN,make_float3(.84f,.86f,.82f));
        box(s,make_float3(side*6.6f,y+.67f,z+1.72f),make_float3(.34f,.23f,.16f),CERAMIC,make_float3(.88f,.88f,.83f));
        box(s,make_float3(side*4.65f,y+.99f,z+1.35f),make_float3(.42f,.15f,.32f),BASIN,make_float3(.84f,.86f,.82f));
        box(s,make_float3(side*4.65f,y+1.12f,z+1.68f),make_float3(.025f,.15f,.025f),METAL,make_float3(.42f,.46f,.47f));
        box(s,make_float3(side*4.65f,y+1.26f,z+1.56f),make_float3(.025f,.025f,.14f),METAL,make_float3(.42f,.46f,.47f));
        for(int door=-1;door<=1;door+=2){box(s,make_float3(side*4.65f+door*.32f,y+.45f,z+.90f),make_float3(.30f,.34f,.025f),WOOD,accent*.72f);box(s,make_float3(side*4.65f+door*.11f,y+.63f,z+.865f),make_float3(.055f,.012f,.015f),METAL,make_float3(.2f,.23f,.24f));}
    }else if(type==9){
        for(int j=0;j<2;++j){float zz=z-.65f+j*1.25f;
            box(s,make_float3(side*7.3f,y+.48f,zz),make_float3(.60f,.48f,.56f),PLASTER,make_float3(.79f,.81f,.78f));
            box(s,make_float3(side*6.68f,y+.43f,zz),make_float3(.025f,.29f,.31f),METAL,make_float3(.14f,.20f,.22f));}
        box(s,make_float3(side*7.3f,y+1.01f,z),make_float3(.66f,.05f,1.3f),WOOD,accent);
        box(s,make_float3(side*4.6f,y+.35f,z+1.35f),make_float3(.47f,.35f,.45f),FABRIC,make_float3(.51f,.43f,.31f));
    }else if(type==10){
        for(int end=-1;end<=1;end+=2){
            box(s,make_float3(side*6.2f,y+1.05f,z+end*1.99f),make_float3(1.8f,1.05f,.035f),WOOD,make_float3(.22f,.14f,.08f));
            for(int edge=-1;edge<=1;edge+=2)box(s,make_float3(side*6.2f+edge*1.77f,y+1.05f,z+end*1.8f),make_float3(.035f,1.05f,.23f),WOOD,make_float3(.32f,.22f,.13f));
            for(int shelf=0;shelf<=3;++shelf)box(s,make_float3(side*6.2f,y+.10f+shelf*.61f,z+end*1.8f),make_float3(1.8f,.025f,.23f),WOOD,make_float3(.35f,.24f,.14f));
            for(int row=0;row<3;++row)for(int j=0;j<28;++j)box(s,make_float3(side*(4.65f+j*.11f),y+.225f+row*.61f+.07f*randf(key+j+row*7),z+end*1.54f),make_float3(.025f+.018f*randf(key+j),.10f+.07f*randf(key+j+row*7),.08f),FABRIC,lerp(accent,make_float3(.49f,.21f,.12f),randf(key+j+row*13)));}
        for(int leg=-1;leg<=1;leg+=2)for(int end=-1;end<=1;end+=2)box(s,make_float3(side*6.0f+leg*.42f,y+.15f,z+end*.45f),make_float3(.035f,.15f,.035f),WOOD,make_float3(.22f,.13f,.07f));
        box(s,make_float3(side*6.0f,y+.40f,z),make_float3(.56f,.13f,.59f),UPHOLSTERY,accent);
        box(s,make_float3(side*6.48f,y+.81f,z),make_float3(.13f,.47f,.59f),UPHOLSTERY,accent*.8f);
        for(int arm=-1;arm<=1;arm+=2)box(s,make_float3(side*6.0f,y+.67f,z+arm*.53f),make_float3(.54f,.11f,.10f),UPHOLSTERY,accent*.85f);
    }else if(type==11){
        box(s,make_float3(side*7.0f,y+.80f,z),make_float3(.72f,.06f,1.70f),WOOD,make_float3(.55f,.36f,.19f));
        for(int j=-1;j<=1;j+=2)box(s,make_float3(side*7.0f,y+.38f,z+j*1.35f),make_float3(.55f,.38f,.07f),METAL,make_float3(.16f,.18f,.17f));
        box(s,make_float3(side*7.0f,y+.89f,z-.8f),make_float3(.46f,.025f,.55f),PLASTER,make_float3(.85f,.81f,.69f));
        box(s,make_float3(side*4.7f,y+.32f,z+1.4f),make_float3(.55f,.32f,.50f),WOOD,accent);
    }
}
__device__ void room(float* s,int floor,int side,int back){
    float y=floorBase(s,floor),storey=floorBase(s,floor+1)-y,x=side*5.2f,z=roomZ(s,floor,side,back);unsigned int key=roomKey(s,floor,side,back);
    float3 accent=roomAccent(key);
    int type=roomType(s,floor,side,back);
    int finish=floorFinish(key,type);float split=roomSplit(s,floor,side),nearZ=back?split:-8.0f,farZ=back?5.4f:split;
    box(s,make_float3(side*5.35f,y+.007f,z),make_float3(3.43f,.007f,(farZ-nearZ)*.5f-.11f),finish,floorColor(key,finish),false);
    specialRoom(s,type,side,y,z,key,accent);
    // Common details, ceiling fixtures, rug, art, power outlets.
    box(s,make_float3(x,y+storey-.18f,z),make_float3(.68f,.035f,.035f),LIGHT,make_float3(1,.81f,.51f),false);
    if(type==0||type==4||type==5||type==10)box(s,make_float3(x,y+.025f,z),make_float3(1.55f,.009f,1.55f),FABRIC,accent*.70f,false);
    art(s,side*8.67f,y+1.65f,z-2.05f,side,key);
    for(int j=0;j<2;++j)box(s,make_float3(side*1.84f,y+.35f,z+(j?1.5f:-1.6f)),make_float3(.025f,.06f,.09f),PLASTER,make_float3(.86f,.84f,.77f),false);
    plant(s,side*7.8f,y,z+1.7f,.9f);
    if(type==0 || type==7){
        // Sofa at the outer side, low table, lounge chair.
        box(s,make_float3(side*7.1f,y+.30f,z-.15f),make_float3(.62f,.23f,1.22f),UPHOLSTERY,accent);
        box(s,make_float3(side*7.55f,y+.76f,z-.15f),make_float3(.18f,.5f,1.22f),UPHOLSTERY,accent*.8f);
        for(int j=-1;j<=1;j+=2)box(s,make_float3(side*7.1f,y+.56f,z+j*1.1f-.15f),make_float3(.63f,.22f,.14f),UPHOLSTERY,accent*.8f);
        for(int j=0;j<3;++j)box(s,make_float3(side*6.95f,y+.58f,z-.85f+j*.7f),make_float3(.40f,.08f,.31f),UPHOLSTERY,accent*1.15f);
        box(s,make_float3(side*4.85f,y+.36f,z),make_float3(.58f,.055f,.9f),WOOD,make_float3(.39f,.23f,.12f));
        leg(s,side*4.85f,y,z-.6f,.32f);leg(s,side*4.85f,y,z+.6f,.32f);
        box(s,make_float3(side*4.85f,y+.43f,z-.3f),make_float3(.21f,.025f,.3f),PLASTER,make_float3(.70f,.46f,.28f),false);
        chair(s,side*4.7f,y,z+1.8f,make_float3(.53f,.47f,.35f));
    }else if(type==1){
        // Kitchen cabinets with separate doors and handles, counter and hob.
        for(int j=0;j<4;++j){float cz=z-1.5f+j*.9f;
            box(s,make_float3(side*7.85f,y+.44f,cz),make_float3(.65f,.44f,.43f),WOOD,make_float3(.34f,.27f,.18f));
            box(s,make_float3(side*7.17f,y+.45f,cz),make_float3(.025f,.40f,.4f),PLASTER,make_float3(.68f,.68f,.58f));
            box(s,make_float3(side*7.12f,y+.68f,cz),make_float3(.028f,.015f,.17f),METAL,make_float3(.08f,.09f,.085f));
        }
        box(s,make_float3(side*7.8f,y+.92f,z-.15f),make_float3(.76f,.05f,1.88f),TILE,make_float3(.84f,.81f,.71f));
        box(s,make_float3(side*7.7f,y+.979f,z-.9f),make_float3(.49f,.012f,.42f),METAL,make_float3(.07f,.085f,.085f));
        for(int j=0;j<4;++j)box(s,make_float3(side*7.7f+(j%2-.5f)*.45f,y+.993f,z-.9f+(j/2-.5f)*.40f),make_float3(.13f,.012f,.13f),METAL,make_float3(.16f,.17f,.16f),false);
        table(s,side*4.4f,y,z,1.6f,1.0f);chair(s,side*4.4f,y,z+1.0f,accent);chair(s,side*4.4f,y,z-1.0f,accent,-1);
    }else if(type==2 || type==6){
        table(s,side*6.9f,y,z,1.25f,2.1f);chair(s,side*5.8f,y,z,accent);
        box(s,make_float3(side*6.9f,y+1.12f,z),make_float3(.04f,.3f,.47f),METAL,make_float3(.09f,.1f,.11f));
        box(s,make_float3(side*6.84f,y+1.12f,z),make_float3(.015f,.26f,.42f),GLASS,make_float3(.18f,.30f,.32f),false);
        box(s,make_float3(side*7.8f,y+1.1f,z+1.9f),make_float3(.50f,1.1f,.27f),WOOD,make_float3(.4f,.24f,.12f));
        for(int row=0;row<4;++row){box(s,make_float3(side*7.8f,y+.25f+row*.5f,z+1.61f),make_float3(.47f,.025f,.04f),WOOD,make_float3(.65f,.43f,.23f));
            for(int j=0;j<5;++j)box(s,make_float3(side*7.8f+(j-2)*.15f,y+.42f+row*.5f,z+1.72f),make_float3(.055f,.15f,.13f),FABRIC,make_float3(.2f+randf(key+j+row*10)*.45f,.24f,.18f),false);}
    }else if(type==3){
        table(s,x,y,z,2.2f,1.2f);for(int j=-1;j<=1;j+=2){chair(s,x+j*.65f,y,z+1,accent);chair(s,x+j*.65f,y,z-1,accent,-1);}
        box(s,make_float3(x,y+.86f,z),make_float3(.25f,.055f,.25f),CONCRETE,make_float3(.64f,.57f,.44f),false);
    }else if(type==4 || type==5){
        // Bedroom or guest room. Keep corridor-side approach clear.
        box(s,make_float3(side*6.1f,y+.24f,z),make_float3(1.15f,.2f,type==5?.72f:1.12f),WOOD,make_float3(.28f,.17f,.1f));
        box(s,make_float3(side*6.1f,y+.51f,z),make_float3(1.14f,.16f,type==5?.70f:1.10f),UPHOLSTERY,make_float3(.86f,.81f,.69f));
        box(s,make_float3(side*7.18f,y+.86f,z),make_float3(.10f,.58f,type==5?.76f:1.16f),UPHOLSTERY,accent);
        box(s,make_float3(side*5.7f,y+.69f,z),make_float3(.64f,.035f,type==5?.68f:1.08f),UPHOLSTERY,accent);
        for(int j=-1;j<=1;j+=2){box(s,make_float3(side*6.8f,y+.73f,z+j*(type==5?.30f:.52f)),make_float3(.28f,.12f,.42f),UPHOLSTERY,make_float3(.93f,.89f,.80f));
            box(s,make_float3(side*7.0f,y+.37f,z+j*1.65f),make_float3(.40f,.36f,.35f),WOOD,make_float3(.46f,.28f,.14f));
            box(s,make_float3(side*7.0f,y+.85f,z+j*1.65f),make_float3(.12f,.12f,.12f),LIGHT,make_float3(1,.70f,.38f),false);}
    }
}

__device__ void sideWindow(float* s,float x,float y,float z){
    box(s,make_float3(x,y+1.8f,z),make_float3(.025f,.80f,1.05f),s[15]<.5f&&s[25]>.5f?VIRTUAL_WINDOW:GLASS,s[15]<.5f&&s[25]>.5f?make_float3(s[19],s[5],s[6]):make_float3(.79f,.86f,.88f));
    for(int j=-1;j<=1;j+=2){box(s,make_float3(x,y+1.8f+j*.84f,z),make_float3(.14f,.055f,1.14f),METAL,make_float3(.16f,.18f,.18f));
        box(s,make_float3(x,y+1.8f,z+j*1.10f),make_float3(.14f,.88f,.045f),METAL,make_float3(.16f,.18f,.18f));}
    box(s,make_float3(x,y+1.8f,z),make_float3(.13f,.84f,.028f),METAL,make_float3(.16f,.18f,.18f));
    box(s,make_float3(x,y+.92f,z),make_float3(.3f,.06f,1.18f),CONCRETE,make_float3(.65f,.64f,.57f));
}
__device__ void emitBuilding(float* s,const float* Districts,unsigned int seed,int lotX,int lotZ,int resident,float offsetX,float offsetZ,int cacheEnabled=1,int virtualEnabled=1){
    Plot plot=cachedPlot(Districts,seed,lotX,lotZ,cacheEnabled);
    s[16]=offsetX;s[17]=offsetZ;s[18]=plot.angle;s[26]=0;unsigned int key=regionKey(neighbourhoodKey(seed,lotX,lotZ)^0x484F5553u,lotX,lotZ);
    s[15]=(float)resident;s[3]=(float)(key&65535u);s[4]=(float)(key>>16);
    float value=plot.value;s[19]=value;s[25]=(float)virtualEnabled;unsigned int style=neighbourhoodKey(seed,lotX,lotZ);
    buildingDNA(s,key,value,style);
    if(!plot.available){s[8]=0;s[15]=0;for(int f=0;f<=4;++f)s[10+f]=0;return;}
    int floors=(int)s[8];
    float3 plaster=lerp(make_float3(.64f,.63f,.57f),make_float3(.87f,.85f,.79f),value),brick=make_float3(.40f,.20f,.115f),floorWood=make_float3(.52f,.32f,.17f),dark=make_float3(.13f,.16f,.15f);
    int facade=(int)s[7]==1?CONCRETE:(value>.65f?PLASTER:BRICK);brick=lerp(make_float3(.29f,.12f,.07f),make_float3(.49f,.35f,.22f),randf(key^107u));if(facade==CONCRETE)brick=make_float3(.56f,.58f,.54f);if(facade==PLASTER)brick=plaster;else brick=brick*(.85f+.25f*value);



    for(int f=0;f<=floors;++f){float y=floorBase(s,f),storey=f==floors?3.2f:floorBase(s,f+1)-y;
        if(f==0||f==floors)box(s,make_float3(0,y-.12f,1.5f),make_float3(9.2f,.12f,9.7f),f==0?WOOD:CONCRETE,f==0?floorWood:plaster);
        else {between(s,make_float3(-9.2f,y-.20f,-8.2f),make_float3(9.2f,y,5.5f),WOOD,floorWood);
            between(s,make_float3(-9.2f,y-.20f,5.5f),make_float3(-1.8f,y,11.2f),WOOD,floorWood);
            between(s,make_float3(1.8f,y-.20f,5.5f),make_float3(9.2f,y,11.2f),WOOD,floorWood);
            between(s,make_float3(-1.8f,y-.20f,10.2f),make_float3(1.8f,y,11.2f),WOOD,floorWood);}
        if(f==floors)break;
        // Front facade has an open entrance below, a broad glazed bay above.
        box(s,make_float3(-5.2f,y+storey*.5f,-8.1f),make_float3(3.8f,storey*.5f,.16f),facade,brick);box(s,make_float3(5.2f,y+storey*.5f,-8.1f),make_float3(3.8f,storey*.5f,.16f),facade,brick);
        box(s,make_float3(0,y+(2.7f+storey)*.5f,-8.1f),make_float3(1.4f,(storey-2.7f)*.5f,.16f),CONCRETE,plaster);
        if(f>0){box(s,make_float3(0,y+.5f,-8.1f),make_float3(1.4f,.5f,.16f),facade,brick);box(s,make_float3(0,y+1.85f,-8.1f),make_float3(1.38f,.85f,.025f),!resident&&virtualEnabled?VIRTUAL_WINDOW:GLASS,!resident&&virtualEnabled?make_float3(value,s[5],s[6]):make_float3(.8f,.9f,.9f));}
        box(s,make_float3(0,y+storey*.5f,11.1f),make_float3(9.1f,storey*.5f,.15f),facade,brick);
        for(int side=-1;side<=1;side+=2){
            // Side facade uses actual apertures, with solid sills and lintels.
            box(s,make_float3(side*9,y+.45f,1.5f),make_float3(.16f,.45f,9.5f),facade,brick);
            box(s,make_float3(side*9,y+(2.7f+storey)*.5f,1.5f),make_float3(.16f,(storey-2.7f)*.5f,9.5f),facade,brick);
            float last=-8;for(int j=0;j<3;++j){float z=j<2?roomZ(s,f,side,j):8.1f;float start=z-1.12f;
                if(start>last)box(s,make_float3(side*9,y+1.8f,(start+last)*.5f),make_float3(.16f,.9f,(start-last)*.5f),facade,brick);
                sideWindow(s,side*9,y,z);last=z+1.12f;}
            box(s,make_float3(side*9,y+1.8f,(last+11)*.5f),make_float3(.16f,.9f,(11-last)*.5f),facade,brick);
            if(resident){
            // Shared hallway wall: two real door openings per side.
            float start=-8;for(int r=0;r<2;++r){float z=roomZ(s,f,side,r);
                box(s,make_float3(side*1.7f,y+storey*.5f,(start+z-.72f)*.5f),make_float3(.11f,storey*.5f,(z-.72f-start)*.5f),PLASTER,plaster);
                box(s,make_float3(side*1.7f,y+(2.4f+storey)*.5f,z),make_float3(.11f,(storey-2.4f)*.5f,.72f),PLASTER,plaster);
                for(int j=-1;j<=1;j+=2)box(s,make_float3(side*1.7f,y+1.2f,z+j*.76f),make_float3(.16f,1.2f,.045f),WOOD,make_float3(.30f,.20f,.12f));
                box(s,make_float3(side*1.7f,y+2.43f,z),make_float3(.16f,.045f,.80f),WOOD,make_float3(.30f,.20f,.12f));
                // Open door leaf sits alongside the room-side wall.
                box(s,make_float3(side*2.39f,y+1.17f,z+.79f),make_float3(.65f,1.17f,.04f),WOOD,make_float3(.47f,.30f,.17f));
                box(s,make_float3(side*2.93f,y+1.0f,z+.73f),make_float3(.075f,.025f,.04f),METAL,dark,false);
                start=z+.72f;room(s,f,side,r);
            }
            box(s,make_float3(side*1.7f,y+storey*.5f,(start+5.4f)*.5f),make_float3(.11f,storey*.5f,(5.4f-start)*.5f),PLASTER,plaster);
            box(s,make_float3(side*5.35f,y+storey*.5f,roomSplit(s,f,side)),make_float3(3.55f,storey*.5f,.10f),PLASTER,plaster);
            box(s,make_float3(side*5.35f,y+storey*.5f,5.4f),make_float3(3.55f,storey*.5f,.10f),PLASTER,plaster);
            // Skirting and ceiling trim, separated around door openings.
            for(int seg=0;seg<3;++seg){float a=seg==0?-8:(seg==1?roomZ(s,f,side,0)+.8f:roomZ(s,f,side,1)+.8f),b=seg==0?roomZ(s,f,side,0)-.8f:(seg==1?roomZ(s,f,side,1)-.8f:5.4f);
                box(s,make_float3(side*1.55f,y+.075f,(a+b)*.5f),make_float3(.035f,.075f,(b-a)*.5f),WOOD,make_float3(.45f,.32f,.20f),false);}
            box(s,make_float3(side*1.53f,y+storey-.23f,-1.3f),make_float3(.09f,.065f,6.6f),PLASTER,make_float3(.89f,.86f,.76f),false);
            plant(s,side*3.0f,y,9.5f,1.2f);
            }
        }
        if(resident)for(int j=0;j<4;++j){if(j==0){unsigned int hallKey=mix(key^(unsigned int)f^0x48414C4Cu);int finish=floorFinish(hallKey,0);box(s,make_float3(0,y+.007f,-1.3f),make_float3(1.58f,.007f,6.7f),finish,floorColor(hallKey,finish),false);}float z=-6+j*3.5f;box(s,make_float3(0,y+storey-.24f,z),make_float3(.45f,.028f,.05f),LIGHT,make_float3(1,.83f,.57f),false);}
        if(resident&&f<floors-1){
            // Two flights, ten address-derived risers each, with a broad intermediate landing.
            for(int i=0;i<10;++i){float height=(i+1)*storey/20.0f;
                box(s,make_float3(-.94f,y+height-.08f,5.65f+i*.30f),make_float3(.73f,.08f,.15f),CONCRETE,make_float3(.60f,.58f,.51f));
                box(s,make_float3(-.94f,y+height+.009f,5.65f+i*.30f),make_float3(.73f,.009f,.15f),WOOD,make_float3(.43f,.28f,.16f));
                float upper=storey*.5f+height;
                box(s,make_float3(.94f,y+upper-.08f,8.35f-i*.30f),make_float3(.73f,.08f,.15f),CONCRETE,make_float3(.60f,.58f,.51f));
                box(s,make_float3(.94f,y+upper+.009f,8.35f-i*.30f),make_float3(.73f,.009f,.15f),WOOD,make_float3(.43f,.28f,.16f));
                for(int side=-1;side<=1;side+=2){float xx=side*1.73f,top=side<0?height:upper;
                    box(s,make_float3(xx,y+top+.5f,side<0?5.65f+i*.30f:8.35f-i*.30f),make_float3(.025f,.50f,.025f),METAL,dark);
                    box(s,make_float3(xx,y+top+1.01f,side<0?5.65f+i*.30f:8.35f-i*.30f),make_float3(.045f,.04f,.18f),WOOD,make_float3(.34f,.21f,.10f));}
            }
            box(s,make_float3(0,y+storey*.5f-.1f,9.35f),make_float3(1.78f,.10f,.85f),CONCRETE,make_float3(.59f,.57f,.5f));
            box(s,make_float3(0,y+storey*.5f+.01f,9.35f),make_float3(1.78f,.01f,.85f),WOOD,make_float3(.43f,.28f,.16f));
            box(s,make_float3(0,y+storey*.5f+.52f,10.18f),make_float3(1.8f,.50f,.035f),GLASS,make_float3(.83f,.90f,.89f));
        }
    }
    if(!resident&&virtualEnabled)box(s,make_float3(0,1.35f,-8.12f),make_float3(1.38f,1.35f,.015f),VIRTUAL_DOOR,make_float3(value,s[5],s[6]),false);
    // Entrance portal, canopy, facade bands and planted setbacks.
    for(int side=-1;side<=1;side+=2){box(s,make_float3(side*1.48f,1.4f,-8.4f),make_float3(.12f,1.4f,.33f),CONCRETE,make_float3(.68f,.64f,.55f));
        box(s,make_float3(side*2.2f,1.85f,-8.29f),make_float3(.065f,.22f,.055f),LIGHT,make_float3(1,.7f,.35f),false);}
    box(s,make_float3(0,2.84f,-8.7f),make_float3(2.1f,.10f,.90f),CONCRETE,make_float3(.65f,.62f,.54f));
    for(int f=1;f<=floors;++f){box(s,make_float3(0,floorBase(s,f),-8.27f),make_float3(9.3f,.10f,.12f),CONCRETE,make_float3(.59f,.57f,.49f));
        for(int side=-1;side<=1;side+=2)box(s,make_float3(side*9.2f,floorBase(s,f),1.5f),make_float3(.10f,.10f,9.7f),CONCRETE,make_float3(.59f,.57f,.49f));}
    // Facade families remain exact geometry even for distant query buildings.
    int character=(int)(mix(key^814u)%3u);
    if(character==0){for(int side=-1;side<=1;side+=2)for(int f=0;f<floors;++f)for(int r=0;r<2;++r){float wz=roomZ(s,f,side,r),yy=floorBase(s,f);for(int edge=-1;edge<=1;edge+=2)box(s,make_float3(side*9.22f,yy+1.8f,wz+edge*1.40f),make_float3(.06f,.78f,.23f),WOOD,dark);}}
    if(character==1){for(int side=-1;side<=1;side+=2)for(int col=0;col<2;++col)box(s,make_float3(side*(col?8.7f:3.5f),floorBase(s,floors)*.5f,-8.32f),make_float3(.18f,floorBase(s,floors)*.5f,.19f),CONCRETE,plaster);}
    if(character==2){for(int side=-1;side<=1;side+=2)box(s,make_float3(side*1.9f,1.38f,-9.35f),make_float3(.09f,1.38f,.09f),WOOD,dark);box(s,make_float3(0,2.84f,-9.15f),make_float3(2.1f,.10f,.55f),WOOD,dark);}
    float roofY=floorBase(s,floors);int roof=(int)s[9];
    if(character!=1)box(s,make_float3(-6.8f,roofY+1.05f,7.5f),make_float3(.46f,1.05f,.55f),BRICK,brick);
    if(roof==0){for(int side=-1;side<=1;side+=2){box(s,make_float3(side*9.05f,roofY+.3f,1.5f),make_float3(.10f,.3f,9.65f),CONCRETE,plaster);box(s,make_float3(0,roofY+.3f,1.5f+side*9.55f),make_float3(9.1f,.3f,.10f),CONCRETE,plaster);}for(int j=0;j<4;++j)plant(s,-7+j*4.5f,roofY,9.3f,1.25f);}
    if(roof==1){for(int j=0;j<48;++j){float x=-9.4f+(j+.5f)*18.8f/48.0f,height=.25f+(1-fabsf(x)/9.4f)*2.1f;box(s,make_float3(x,roofY+height,1.5f),make_float3(18.8f/96.0f,.06f,9.95f),METAL,make_float3(.19f,.22f,.21f));for(int side=-1;side<=1;side+=2)box(s,make_float3(x,roofY+height*.5f,1.5f+side*9.55f),make_float3(18.8f/96.0f,height*.5f,.1f),facade,brick);}}
    if(roof==2){for(int j=0;j<3;++j)box(s,make_float3(0,roofY+j*.38f+.19f,1.5f),make_float3(7.9f-j*1.6f,.19f,8.1f-j*1.6f),CONCRETE,plaster);for(int j=0;j<3;++j)box(s,make_float3(-3.4f+j*3.0f,roofY+1.25f,1.3f),make_float3(.9f,.1f,1.6f),GLASS,make_float3(.15f,.24f,.28f));}
}
// Outdoor geometry has its own region seed. Shared edge widths match the analytic ground.
__device__ void emitOutdoors(float* s,unsigned int seed,int x,int z,float ox,float oz){
 s[5]=1;s[6]=1;s[26]=1;unsigned int key=regionKey(seed,(int)floorf((float)x/8),(int)floorf((float)z/8));s[3]=(float)(key&65535u);s[4]=(float)(key>>16);
 for(int axis=0;axis<2;++axis){Street r=street(seed,x,z,axis);if(!r.active)continue;for(int j=0;j<6;++j){float3 a=streetPoint(r,j/6.0f),b=streetPoint(r,(j+1)/6.0f),delta=b-a;float length=sqrtf(dot(delta,delta));s[16]=(a.x+b.x)*.5f-x*40+ox;s[17]=(a.z+b.z)*.5f-z*40+oz;s[18]=atan2f(delta.x,delta.z);if(j>0&&j<5)for(int side=-1;side<=1;side+=2)box(s,make_float3(side*(r.width+.10f),.04f,0),make_float3(.1f,.04f,length*.5f),CONCRETE,make_float3(.65f,.64f,.57f),false);}
 if(r.terminal)for(int j=0;j<20;++j){float a=j*2*PI/20.0f;if(dot(make_float3(cosf(a),0,sinf(a)),norm(r.a-r.b))>.8f)continue;s[16]=r.b.x-x*40+ox+cosf(a)*8.1f;s[17]=r.b.z-z*40+oz+sinf(a)*8.1f;s[18]=-a;box(s,make_float3(0,.04f,0),make_float3(.10f,.04f,1.30f),CONCRETE,make_float3(.65f,.64f,.57f),false);}
 }
 s[16]=ox;s[17]=oz;s[18]=0;unsigned int parcel=mix(key^mix((unsigned int)x)^mix((unsigned int)z*739u));if(randf(parcel)>.25f)plant(s,-13,0,-2,1.3f);if(randf(parcel^29u)>.35f)plant(s,13,0,3,1.3f);
}
// A bounded residency window enumerates the SAME exterior grammar at every address.
// No proxy facade or different distant roof. Only hidden interior allocation changes.
__global__ void generateScene(float* s,const float* Districts,unsigned int seed,int lotX,int lotZ,int resident,int radius,int cacheEnabled=1,int virtualEnabled=1){
    if(threadIdx.x||blockIdx.x)return;s[0]=0;s[2]=0;s[5]=1;s[6]=1;s[16]=0;s[17]=0;s[3]=0;s[4]=0;s[18]=0;s[26]=0;s[27]=0;s[20]=(float)lotX;s[21]=(float)lotZ;s[22]=(float)seed;s[24]=(float)radius;
    box(s,make_float3(0,-.2f,0),make_float3(20000,.2f,20000),GROUND,make_float3(.26f,.28f,.25f));
    emitOutdoors(s,seed,lotX,lotZ,0,0);
    emitBuilding(s,Districts,seed,lotX,lotZ,resident,0,0,cacheEnabled,virtualEnabled);s[1]=s[0];float header[19];for(int i=1;i<19;++i)header[i]=s[i];
    for(int dz=-radius;dz<=radius;++dz)for(int dx=-radius;dx<=radius;++dx){if(dx!=0||dz!=0){emitOutdoors(s,seed,lotX+dx,lotZ+dz,dx*40.0f,dz*40.0f);emitBuilding(s,Districts,seed,lotX+dx,lotZ+dz,0,dx*40.0f,dz*40.0f,cacheEnabled,virtualEnabled);}}
    float overflow=s[2];for(int i=1;i<19;++i)s[i]=header[i];s[2]=overflow;
}

__global__ void describeLayout(float* s,float* Plan){if(threadIdx.x||blockIdx.x)return;for(int i=0;i<64;++i)Plan[i]=0;Plan[0]=s[5];Plan[1]=s[6];Plan[2]=s[8];Plan[3]=s[9];Plan[4]=s[7];Plan[5]=s[3];Plan[6]=s[4];Plan[7]=s[15];Plan[13]=s[18];Plan[14]=districtValue((unsigned int)s[22],(int)s[20],(int)s[21]);Plan[15]=propertyValue((unsigned int)s[22],(int)s[20],(int)s[21]);for(int f=0;f<=4;++f)Plan[8+f]=floorBase(s,f);for(int f=0;f<(int)s[8];++f)for(int r=0;r<4;++r){int side=r%2?1:-1;Plan[16+f*4+r]=roomZ(s,f,side,r/2)*s[6];Plan[32+f*4+r]=(float)roomType(s,f,side,r/2);Plan[48+f*4+r]=(float)floorFinish(roomKey(s,f,side,r/2),roomType(s,f,side,r/2));}}


__device__ unsigned int spread(unsigned int x){x&=1023u;x=(x|(x<<16))&0x030000ffu;x=(x|(x<<8))&0x0300f00fu;x=(x|(x<<4))&0x030c30c3u;x=(x|(x<<2))&0x09249249u;return x;}
__global__ void morton(float* s,unsigned int* keys){int i=(int)(blockIdx.x*blockDim.x+threadIdx.x);if(i>=(int)s[23])return;keys[i*2+1]=(unsigned int)i;if(i>=(int)s[0]){keys[i*2]=4294967295u;return;}Shape o=readShape(s,i);float3 p=rotateY((o.lo+o.hi)*0.5f-o.origin,o.angle)+o.origin;unsigned int x=(unsigned int)(clamp((p.x+(s[24]+1)*40.0f)/((s[24]+1)*80.0f))*1023.0f),y=(unsigned int)(clamp((p.y+1.0f)/18.0f)*1023.0f),z=(unsigned int)(clamp((p.z+(s[24]+1)*40.0f)/((s[24]+1)*80.0f))*1023.0f);keys[i*2]=spread(x)|(spread(y)<<1)|(spread(z)<<2);}
__global__ void sortPairs(float* s,unsigned int* keys,int stage,int stride){int i=(int)(blockIdx.x*blockDim.x+threadIdx.x);int j=i^stride;if(i>=(int)s[23]||j<=i)return;bool up=(i&stage)==0;unsigned int a=keys[i*2],b=keys[j*2],ai=keys[i*2+1],bi=keys[j*2+1];bool greater=a>b||(a==b&&ai>bi);if(greater==up){keys[i*2]=b;keys[i*2+1]=bi;keys[j*2]=a;keys[j*2+1]=ai;}}
__global__ void leaves(float* s,const unsigned int* keys,float* nodes){int i=(int)(blockIdx.x*blockDim.x+threadIdx.x);if(i>=(int)s[23])return;int j=(int)keys[i*2+1];Node n;if(j<(int)s[0]){Shape o=readShape(s,j);float3 center=rotateY((o.lo+o.hi)*.5f-o.origin,o.angle)+o.origin,half=(o.hi-o.lo)*.5f;float cs=fabsf(cosf(o.angle)),sn=fabsf(sinf(o.angle));float3 extent=make_float3(cs*half.x+sn*half.z,half.y,sn*half.x+cs*half.z);n.lo=center-extent;n.hi=center+extent;n.shape=j;}else{n.lo=make_float3(1e20f,1e20f,1e20f);n.hi=make_float3(-1e20f,-1e20f,-1e20f);n.shape=-1;}writeNode(nodes,(int)s[23]+i,n);}
__global__ void parents(float* nodes,int start){int i=(int)(blockIdx.x*blockDim.x+threadIdx.x);if(i>=start)return;int j=start+i;Node a=readNode(nodes,j*2),b=readNode(nodes,j*2+1),n;n.lo=vmin(a.lo,b.lo);n.hi=vmax(a.hi,b.hi);n.shape=-1;writeNode(nodes,j,n);}
__device__ float bound(float3 ro,float3 inv,float3 lo,float3 hi,float maxT){if(lo.x>hi.x||lo.y>hi.y||lo.z>hi.z)return 1e30f;float3 a=(lo-ro)*inv,b=(hi-ro)*inv;float3 mn=vmin(a,b),mx=vmax(a,b);float near=fmaxf(mn.x,fmaxf(mn.y,mn.z)),far=fminf(mx.x,fminf(mx.y,mx.z));return far>=fmaxf(near,.001f)&&near<maxT?fmaxf(near,.001f):1e30f;}

__device__ void queryBox(float* s,float3 p,float3 half,int mat,float3 color,bool solid=true){
 p.x=p.x*s[5]+s[16];p.z=p.z*s[6]+s[17];half.x*=s[5];half.z*=s[6];Shape o;o.lo=p-half;o.hi=p+half;o.color=color;o.origin=make_float3(s[16],0,s[17]);o.angle=s[18];o.id=buildingKey(s);o.mat=mat;o.solid=solid?1:0;
 Hit h=intersectShape(o,make_float3(s[48],s[49],s[50]),make_float3(s[51],s[52],s[53]),s[28],s[54]>.5f);if(h.id<0)return;
 s[28]=h.t;s[29]=h.n.x;s[30]=h.n.y;s[31]=h.n.z;s[55]=1;
 s[32]=o.lo.x;s[33]=o.lo.y;s[34]=o.lo.z;s[35]=o.hi.x;s[36]=o.hi.y;s[37]=o.hi.z;s[38]=color.x;s[39]=color.y;s[40]=color.z;s[41]=(float)mat;s[42]=solid?1:0;s[43]=s[3];s[44]=s[4];s[45]=s[16];s[46]=s[17];s[47]=s[18];
}
// QUERY_GRAMMAR_INSERT
__device__ Hit queryLot(float* s,const float* Districts,int x,int z,float3 ro,float3 rd,float limit,bool shadow,int cacheEnabled,int virtualEnabled){float q[64];for(int k=0;k<64;++k)q[k]=0;q[27]=1;q[28]=limit;q[48]=ro.x;q[49]=ro.y;q[50]=ro.z;q[51]=rd.x;q[52]=rd.y;q[53]=rd.z;q[54]=shadow?1:0;
 queryBuilding(q,Districts,(unsigned int)s[22],(int)s[20]+x,(int)s[21]+z,0,x*40.0f,z*40.0f,cacheEnabled,virtualEnabled);
 Hit h;h.id=-1;h.t=limit;h.n=make_float3(0,0,0);if(q[55]>.5f){h.id=CAP;h.t=q[28];h.n=make_float3(q[29],q[30],q[31]);h.feature=readShape(q,0);}return h;}
__device__ Hit distantQuery(float* s,const float* Districts,float3 ro,float3 rd,Hit hit,bool shadow,int cacheEnabled,int virtualEnabled){
 float end=fminf(hit.t,8000.0f),start=.002f;if(ro.y>18){if(rd.y>=0)return hit;start=fmaxf(start,(18-ro.y)/rd.y);}if(ro.y<-.25f){if(rd.y<=0)return hit;start=fmaxf(start,(-.25f-ro.y)/rd.y);}if(rd.y>0)end=fminf(end,(18-ro.y)/rd.y);if(rd.y<0)end=fminf(end,(-.25f-ro.y)/rd.y);if(start>=end)return hit;
 float3 p=ro+rd*start;int x=(int)floorf((p.x+20)/40),z=(int)floorf((p.z+20)/40),stepX=rd.x<0?-1:1,stepZ=rd.z<0?-1:1;
 float tx=fabsf(rd.x)<1e-8f?1e30f:((x*40.0f+stepX*20.0f)-ro.x)/rd.x,tz=fabsf(rd.z)<1e-8f?1e30f:((z*40.0f+stepZ*20.0f)-ro.z)/rd.z,dx=40/fmaxf(1e-8f,fabsf(rd.x)),dz=40/fmaxf(1e-8f,fabsf(rd.z));
 float3 inv=make_float3(1/(fabsf(rd.x)<1e-8f?1e-8f:rd.x),1/(fabsf(rd.y)<1e-8f?1e-8f:rd.y),1/(fabsf(rd.z)<1e-8f?1e-8f:rd.z));
 for(int step=0;step<600&&start<end;++step){if(abs(x)>(int)s[24]||abs(z)>(int)s[24]){float3 lo=make_float3(x*40.0f-19,-.25f,z*40.0f-19),hi=make_float3(x*40.0f+19,18,z*40.0f+19);if(bound(ro,inv,lo,hi,hit.t)<hit.t){Hit q=queryLot(s,Districts,x,z,ro,rd,hit.t,shadow,cacheEnabled,virtualEnabled);if(q.id>=0){hit=q;end=fminf(end,q.t);if(shadow)return hit;}}}
 if(tx<tz){start=tx;tx+=dx;x+=stepX;}else{start=tz;tz+=dz;z+=stepZ;}}
 return hit;
}
__device__ Shape hitShape(float* s,Hit h){if(h.id==CAP)return h.feature;return readShape(s,h.id);}
__device__ Hit trace(float* s,const float* nodes,float3 ro,float3 rd,float maxT=8000,bool shadow=false){
    float3 inv=make_float3(1/(fabsf(rd.x)<1e-8f?1e-8f:rd.x),1/(fabsf(rd.y)<1e-8f?1e-8f:rd.y),1/(fabsf(rd.z)<1e-8f?1e-8f:rd.z));
    int stack[32],top=0;stack[top++]=1;Hit hit;hit.t=maxT;hit.id=-1;hit.n=make_float3(0,0,0);
    while(top){int i=stack[--top];Node n=readNode(nodes,i);if(bound(ro,inv,n.lo,n.hi,hit.t)>=hit.t)continue;
        if(i>=(int)s[23]){if(n.shape<0)continue;Hit test=intersectShape(readShape(s,n.shape),ro,rd,hit.t,shadow);if(test.id>=0){hit=test;hit.id=n.shape;if(shadow)return hit;}
        }else{float a=bound(ro,inv,readNode(nodes,i*2).lo,readNode(nodes,i*2).hi,hit.t),b=bound(ro,inv,readNode(nodes,i*2+1).lo,readNode(nodes,i*2+1).hi,hit.t);
            if(a<b){if(b<hit.t)stack[top++]=i*2+1;if(a<hit.t)stack[top++]=i*2;}else{if(a<hit.t)stack[top++]=i*2;if(b<hit.t)stack[top++]=i*2+1;}}
    }return hit;
}

__device__ float3 surfaceMaterial(Shape o,float3 p,float3 n,float footprint){
    p=rotateY(p-o.origin,-o.angle);n=rotateY(n,-o.angle);float3 c=o.color;float u=fabsf(n.x)>.5f?p.z:p.x,v=fabsf(n.y)>.5f?p.z:p.y;
    if(o.mat==WOOD&&n.y<-.5f&&(o.hi.x-o.lo.x>6.0f||o.hi.z-o.lo.z>6.0f))return make_float3(.80f,.79f,.73f);
    float noise=randf(static_cast<unsigned int>(floorf(p.x*180))*73856093u^static_cast<unsigned int>(floorf(p.y*180))*19349663u^static_cast<unsigned int>(floorf(p.z*180))*83492791u);
    float micro=clamp(1-footprint*80);c=c*(1+(noise-.5f)*.06f*micro);
    if(o.mat==BRICK){float row=floorf(v/.085f);float bx=fract(u/.29f+(int)(row)%2*.5f),by=fract(v/.085f);
        float mortar=clamp(fminf(fminf(bx,1-bx)*.29f,fminf(by,1-by)*.085f)/fmaxf(.003f,footprint));
        float r=randf(static_cast<unsigned int>(floorf(u/.29f+(int)(row)%2*.5f))*1231u^(unsigned int)(row)*919u);
        c=lerp(make_float3(.47f,.43f,.35f),c*(.75f+r*.45f),mortar);}
    if(o.mat==WOOD){float strip=floorf(p.x/.19f),seam=fminf(fract(p.x/.19f),1-fract(p.x/.19f));
        float grain=sinf(p.x*180+sinf(p.z*2.2f)*2+sinf(p.z*11)*.4f)*.04f;
        c=c*(.87f+randf((unsigned int)(strip)^o.id)*.19f+grain*micro);if(n.y>.5f&&seam<.013f&&footprint<.02f)c=c*.7f;}
    if(o.mat==TILE){float fu=fract(u/.45f),fv=fract(v/.45f);if(fminf(fminf(fu,1-fu),fminf(fv,1-fv))<.012f)c=c*.62f;}
    if(o.mat==FABRIC||o.mat==UPHOLSTERY)c=c*(1+.035f*sinf(u*420)*sinf(v*420)*micro);
    if(o.mat==CONCRETE||o.mat==PLASTER)c=c*(.98f+.04f*noise*micro);
    if(o.mat>=FLOOR_WOOD&&o.mat<=FLOOR_TERRAZZO){
        // Stable building-local coordinates and filtered microdetail prevent swimming.
        float x=p.x,z=p.z;unsigned int finishSeed=mix(o.id^0x46494E49u);if((finishSeed&1u)!=0u){float swap=x;x=z;z=swap;}
        if(o.mat==FLOOR_WOOD||o.mat==FLOOR_PARQUET){float width=.14f+randf(finishSeed)*.10f,length=1.15f+randf(finishSeed^31u)*.8f;
            if(o.mat==FLOOR_PARQUET){float bx=floorf(x/.72f),bz=floorf(z/.72f);if(((int)(bx+bz)%2)==0){float swap=x;x=z;z=swap;}width=.12f;length=.72f;}
            float row=floorf(x/width),shift=o.mat==FLOOR_PARQUET?0:randf((unsigned int)row^finishSeed)*length,fu=fract(x/width),fv=fract((z+shift)/length);unsigned int plank=mix((unsigned int)row^mix((unsigned int)floorf((z+shift)/length))^finishSeed);float grain=sinf(x*340+sinf(z*3.7f)*2+sinf(z*17)*.6f);c=c*(.82f+.30f*randf(plank)+grain*.045f*micro);float seam=fminf(fminf(fu,1-fu)*width,fminf(fv,1-fv)*length);c=c*(.55f+.45f*clamp(seam/fmaxf(.0015f,footprint)));}
        else if(o.mat==FLOOR_CARPET){float weave=sinf(x*610)*sinf(z*580),tuft=randf((unsigned int)floorf(x*230)^mix((unsigned int)floorf(z*230)));c=c*(.91f+(.12f*tuft+.055f*weave)*micro);}
        else {float size=.32f+randf(finishSeed)*.38f,tx=floorf(x/size),tz=floorf(z/size),fu=fract(x/size),fv=fract(z/size),seam=fminf(fminf(fu,1-fu),fminf(fv,1-fv))*size;
            if(o.mat==FLOOR_CHECK&&((int)(tx+tz)%2)!=0)c=c*.34f;else c=c*(.94f+.09f*randf((unsigned int)tx^mix((unsigned int)tz)^finishSeed));
            if(o.mat==FLOOR_TERRAZZO){float chip=randf((unsigned int)floorf(x*85)^mix((unsigned int)floorf(z*85))^finishSeed);c=lerp(c,chip>.90f?make_float3(.78f,.73f,.62f):c*.5f,(chip>.90f||chip<.09f)?micro*.6f:0);}
            else c=lerp(c*.42f,c,clamp(seam/fmaxf(.0025f,footprint)));}
    }
    if(o.mat==ASPHALT)c=c*(.92f+.12f*noise);
    return c;
}
__device__ float3 material(float* s,Shape o,float3 p,float3 n,float footprint){if(o.mat==GROUND)return outdoorMaterial(s,p,footprint);return surfaceMaterial(o,p,n,footprint);}
__device__ float3 sky(float3 rd){float t=clamp(rd.y*.7f+.35f);float3 c=lerp(make_float3(.76f,.79f,.76f),make_float3(.28f,.48f,.68f),t);float sun=powf(fmaxf(0,dot(rd,norm(make_float3(-.7f,1,-.5f)))),900);return c+make_float3(6,4.8f,3.1f)*sun;}
// Analytic interior mapping lives beside the physical grammar. No mesh allocation,
// extra shader module, texture atlas, or dependency is needed for a visible opening.
__device__ void virtualDNA(float* q,Shape opening){for(int i=0;i<32;++i)q[i]=0;buildingDNA(q,opening.id,opening.color.x,0);q[5]=opening.color.y;q[6]=opening.color.z;}
__global__ void probeResidency(float* s,const float* Districts,const float* C,float* Plan){if(threadIdx.x||blockIdx.x)return;int dx=(int)floorf((C[0]+20)/40),dz=(int)floorf((C[2]+20)/40),x=(int)s[20]+dx,z=(int)s[21]+dz;unsigned int seed=(unsigned int)s[22],key=regionKey(neighbourhoodKey(seed,x,z)^0x484F5553u,x,z);Plot p=cachedPlot(Districts,seed,x,z,1);float sx=houseWidth(key,p.value),sz=houseDepth(key,p.value);float3 local=rotateY(make_float3(C[0]-dx*40,C[1],C[2]-dz*40),-p.angle);float roof=0;int floors=p.value<.35f?3+(int)(mix(key^104u)%2u):(p.value>.65f?2:2+(int)(mix(key^104u)%2u));for(int f=1;f<=floors;++f)roof+=3.08f+.27f*randf(mix(key^(unsigned int)f)^106u);bool retained=s[15]>.5f&&dx==0&&dz==0;bool inside=fabsf(local.x)<9.2f*sx&&local.z>-8.3f*sz&&local.z<11.3f*sz&&local.y<roof+2;float gap=-8.1f*sz-local.z,yaw=C[3]-p.angle;float3 view=make_float3(sinf(yaw)*cosf(C[4]),sinf(C[4]),cosf(yaw)*cosf(C[4])),toDoor=norm(make_float3(-local.x,-.30f-local.y,gap));bool needed=retained||gap<2.5f||dot(view,toDoor)>.25f;bool entrance=needed&&fabsf(local.x)<(retained?5:3.5f)*sx&&local.z>-8.1f*sz-(retained?11:8)&&local.z<-6.1f*sz&&local.y<3;Plan[46]=p.available&&(inside||entrance)?1:0;}
__device__ Hit virtualBox(float* q,float3 ro,float3 rd,Hit best,float3 center,float3 half,int mat,float3 color){Shape o;center.x*=q[5];center.z*=q[6];half.x*=q[5];half.z*=q[6];o.lo=center-half;o.hi=center+half;o.color=color;o.mat=mat;o.id=buildingKey(q);o.origin=make_float3(0,0,0);o.angle=0;o.solid=0;Hit h=intersectShape(o,ro,rd,best.t,false);return h.id>=0?h:best;}
__device__ bool virtualBounds(float* q,float3 ro,float3 rd,float limit,float3 center,float3 half){center.x*=q[5];center.z*=q[6];half.x*=q[5];half.z*=q[6];float3 inv=make_float3(1/(fabsf(rd.x)<1e-8f?(rd.x<0?-1e-8f:1e-8f):rd.x),1/(fabsf(rd.y)<1e-8f?(rd.y<0?-1e-8f:1e-8f):rd.y),1/(fabsf(rd.z)<1e-8f?(rd.z<0?-1e-8f:1e-8f):rd.z));return bound(ro,inv,center-half,center+half,limit)<limit;}
__device__ Hit virtualChair(float* q,float3 ro,float3 rd,Hit h,float x,float y,float z,float3 accent,int face=1){h=virtualBox(q,ro,rd,h,make_float3(x,y+.45f,z),make_float3(.24f,.055f,.23f),UPHOLSTERY,accent);h=virtualBox(q,ro,rd,h,make_float3(x,y+.77f,z+face*.20f),make_float3(.24f,.28f,.05f),UPHOLSTERY,accent);for(int a=-1;a<=1;a+=2)for(int b=-1;b<=1;b+=2)h=virtualBox(q,ro,rd,h,make_float3(x+a*.18f,y+.21f,z+b*.17f),make_float3(.035f,.21f,.035f),METAL,make_float3(.11f,.13f,.13f));return h;}
__device__ Hit virtualSpecialRoom(float* q,float3 start,float3 direction,Hit h,int type,int side,float y,float z,unsigned int key,float3 accent){
    if(type==8){
        // Bath rim, recessed basin, vanity and toilet. Keep the doorway clear.
        h=virtualBox(q,start,direction,h,make_float3(side*7.25f,y+.08f,z-.65f),make_float3(.75f,.08f,1.20f),CERAMIC,make_float3(.82f,.84f,.79f));
        for(int edge=-1;edge<=1;edge+=2){h=virtualBox(q,start,direction,h,make_float3(side*7.25f+edge*.67f,y+.32f,z-.65f),make_float3(.08f,.20f,1.20f),CERAMIC,make_float3(.82f,.84f,.79f));h=virtualBox(q,start,direction,h,make_float3(side*7.25f,y+.32f,z-.65f+edge*1.12f),make_float3(.59f,.20f,.08f),CERAMIC,make_float3(.82f,.84f,.79f));}
        h=virtualBox(q,start,direction,h,make_float3(side*7.25f,y+.18f,z-.65f),make_float3(.58f,.015f,1.02f),CERAMIC,make_float3(.49f,.62f,.62f));
        h=virtualBox(q,start,direction,h,make_float3(side*4.65f,y+.42f,z+1.35f),make_float3(.65f,.42f,.43f),WOOD,accent);
        h=virtualBox(q,start,direction,h,make_float3(side*4.65f,y+.88f,z+1.35f),make_float3(.69f,.04f,.47f),CERAMIC,make_float3(.89f,.89f,.84f));
        h=virtualBox(q,start,direction,h,make_float3(side*6.6f,y+.18f,z+1.52f),make_float3(.19f,.18f,.25f),CERAMIC,make_float3(.72f,.75f,.73f));
        h=virtualBox(q,start,direction,h,make_float3(side*6.6f,y+.43f,z+1.38f),make_float3(.34f,.18f,.44f),BASIN,make_float3(.84f,.86f,.82f));
        h=virtualBox(q,start,direction,h,make_float3(side*6.6f,y+.67f,z+1.72f),make_float3(.34f,.23f,.16f),CERAMIC,make_float3(.88f,.88f,.83f));
        h=virtualBox(q,start,direction,h,make_float3(side*4.65f,y+.99f,z+1.35f),make_float3(.42f,.15f,.32f),BASIN,make_float3(.84f,.86f,.82f));
        h=virtualBox(q,start,direction,h,make_float3(side*4.65f,y+1.12f,z+1.68f),make_float3(.025f,.15f,.025f),METAL,make_float3(.42f,.46f,.47f));
        h=virtualBox(q,start,direction,h,make_float3(side*4.65f,y+1.26f,z+1.56f),make_float3(.025f,.025f,.14f),METAL,make_float3(.42f,.46f,.47f));
        for(int door=-1;door<=1;door+=2){h=virtualBox(q,start,direction,h,make_float3(side*4.65f+door*.32f,y+.45f,z+.90f),make_float3(.30f,.34f,.025f),WOOD,accent*.72f);h=virtualBox(q,start,direction,h,make_float3(side*4.65f+door*.11f,y+.63f,z+.865f),make_float3(.055f,.012f,.015f),METAL,make_float3(.2f,.23f,.24f));}
    }else if(type==9){
        for(int j=0;j<2;++j){float zz=z-.65f+j*1.25f;
            h=virtualBox(q,start,direction,h,make_float3(side*7.3f,y+.48f,zz),make_float3(.60f,.48f,.56f),PLASTER,make_float3(.79f,.81f,.78f));
            h=virtualBox(q,start,direction,h,make_float3(side*6.68f,y+.43f,zz),make_float3(.025f,.29f,.31f),METAL,make_float3(.14f,.20f,.22f));}
        h=virtualBox(q,start,direction,h,make_float3(side*7.3f,y+1.01f,z),make_float3(.66f,.05f,1.3f),WOOD,accent);
        h=virtualBox(q,start,direction,h,make_float3(side*4.6f,y+.35f,z+1.35f),make_float3(.47f,.35f,.45f),FABRIC,make_float3(.51f,.43f,.31f));
    }else if(type==10){
        for(int end=-1;end<=1;end+=2){
            h=virtualBox(q,start,direction,h,make_float3(side*6.2f,y+1.05f,z+end*1.99f),make_float3(1.8f,1.05f,.035f),WOOD,make_float3(.22f,.14f,.08f));
            for(int edge=-1;edge<=1;edge+=2)h=virtualBox(q,start,direction,h,make_float3(side*6.2f+edge*1.77f,y+1.05f,z+end*1.8f),make_float3(.035f,1.05f,.23f),WOOD,make_float3(.32f,.22f,.13f));
            for(int shelf=0;shelf<=3;++shelf)h=virtualBox(q,start,direction,h,make_float3(side*6.2f,y+.10f+shelf*.61f,z+end*1.8f),make_float3(1.8f,.025f,.23f),WOOD,make_float3(.35f,.24f,.14f));
            for(int row=0;row<3;++row)for(int j=0;j<28;++j)h=virtualBox(q,start,direction,h,make_float3(side*(4.65f+j*.11f),y+.225f+row*.61f+.07f*randf(key+j+row*7),z+end*1.54f),make_float3(.025f+.018f*randf(key+j),.10f+.07f*randf(key+j+row*7),.08f),FABRIC,lerp(accent,make_float3(.49f,.21f,.12f),randf(key+j+row*13)));}
        for(int leg=-1;leg<=1;leg+=2)for(int end=-1;end<=1;end+=2)h=virtualBox(q,start,direction,h,make_float3(side*6.0f+leg*.42f,y+.15f,z+end*.45f),make_float3(.035f,.15f,.035f),WOOD,make_float3(.22f,.13f,.07f));
        h=virtualBox(q,start,direction,h,make_float3(side*6.0f,y+.40f,z),make_float3(.56f,.13f,.59f),UPHOLSTERY,accent);
        h=virtualBox(q,start,direction,h,make_float3(side*6.48f,y+.81f,z),make_float3(.13f,.47f,.59f),UPHOLSTERY,accent*.8f);
        for(int arm=-1;arm<=1;arm+=2)h=virtualBox(q,start,direction,h,make_float3(side*6.0f,y+.67f,z+arm*.53f),make_float3(.54f,.11f,.10f),UPHOLSTERY,accent*.85f);
    }else if(type==11){
        h=virtualBox(q,start,direction,h,make_float3(side*7.0f,y+.80f,z),make_float3(.72f,.06f,1.70f),WOOD,make_float3(.55f,.36f,.19f));
        for(int j=-1;j<=1;j+=2)h=virtualBox(q,start,direction,h,make_float3(side*7.0f,y+.38f,z+j*1.35f),make_float3(.55f,.38f,.07f),METAL,make_float3(.16f,.18f,.17f));
        h=virtualBox(q,start,direction,h,make_float3(side*7.0f,y+.89f,z-.8f),make_float3(.46f,.025f,.55f),PLASTER,make_float3(.85f,.81f,.69f));
        h=virtualBox(q,start,direction,h,make_float3(side*4.7f,y+.32f,z+1.4f),make_float3(.55f,.32f,.50f),WOOD,accent);
    }
return h;}
__device__ float3 virtualInterior(float* s,float3 ro,float3 rd,Hit entry,float pixelScale,int angleCulling){
 Shape opening=hitShape(s,entry);float q[32];virtualDNA(q,opening);float3 origin=rotateY(ro-opening.origin,-opening.angle),direction=rotateY(rd,-opening.angle),start=origin+direction*(entry.t+.07f);float sx=q[5],sz=q[6];int floor=0;for(int f=1;f<(int)q[8];++f)if(start.y>=floorBase(q,f))floor=f;float y=floorBase(q,floor),storey=floorBase(q,floor+1)-y;int side=start.x<0?-1:1;bool corridor=fabsf(start.x/sx)<2||start.z/sz>5.4f;int back=start.z/sz<roomSplit(q,floor,side)?0:1;float z=roomZ(q,floor,side,back),x=side*5.2f;unsigned int key=roomKey(q,floor,side,back);float3 accent=roomAccent(key),plaster=lerp(make_float3(.64f,.63f,.57f),make_float3(.87f,.85f,.79f),opening.color.x);int type=roomType(q,floor,side,back);Hit h;h.id=-1;h.t=80;h.n=make_float3(0,0,0);
 float nearZ=corridor?-8.0f:(back?roomSplit(q,floor,side)+.10f:-7.94f),farZ=corridor?11.0f:(back?5.3f:roomSplit(q,floor,side)-.10f),cx=corridor?0:side*5.25f,hw=corridor?1.59f:3.44f;
 unsigned int floorKey=corridor?mix(buildingKey(q)^(unsigned int)floor^0x48414C4Cu):key;int finish=floorFinish(floorKey,corridor?0:type);
 h=virtualBox(q,start,direction,h,make_float3(cx,y-.043f,(nearZ+farZ)*.5f),make_float3(hw,.057f,(farZ-nearZ)*.5f),finish,floorColor(floorKey,finish));
 h=virtualBox(q,start,direction,h,make_float3(cx,y+storey-.10f,(nearZ+farZ)*.5f),make_float3(hw,.10f,(farZ-nearZ)*.5f),PLASTER,make_float3(.80f,.79f,.73f));
 if(!corridor){
  for(int end=0;end<2;++end){float a=end?z+.72f:nearZ,b=end?farZ:z-.72f;h=virtualBox(q,start,direction,h,make_float3(side*1.7f,y+storey*.5f,(a+b)*.5f),make_float3(.11f,storey*.5f,(b-a)*.5f),PLASTER,plaster);h=virtualBox(q,start,direction,h,make_float3(side*1.7f,y+1.2f,z+(end?.76f:-.76f)),make_float3(.16f,1.2f,.045f),WOOD,make_float3(.30f,.20f,.12f));}
  h=virtualBox(q,start,direction,h,make_float3(side*1.7f,y+(2.4f+storey)*.5f,z),make_float3(.11f,(storey-2.4f)*.5f,.72f),PLASTER,plaster);h=virtualBox(q,start,direction,h,make_float3(side*1.7f,y+2.43f,z),make_float3(.16f,.045f,.80f),WOOD,make_float3(.30f,.20f,.12f));h=virtualBox(q,start,direction,h,make_float3(side*2.39f,y+1.17f,z+.79f),make_float3(.65f,1.17f,.04f),WOOD,make_float3(.47f,.30f,.17f));h=virtualBox(q,start,direction,h,make_float3(-side*8.8f,y+storey*.5f,z),make_float3(.05f,storey*.5f,.72f),PLASTER,plaster*.65f);
  for(int end=0;end<2;++end)h=virtualBox(q,start,direction,h,make_float3(cx,y+storey*.5f,end?farZ:nearZ),make_float3(hw,storey*.5f,.01f),PLASTER,plaster);
  if(type==0||type==4||type==5||type==10)h=virtualBox(q,start,direction,h,make_float3(x,y+.025f,z),make_float3(1.55f,.009f,1.55f),FABRIC,accent*.70f);
  // Major furniture matches the positions, type and palette in room(). Small
  // fittings are deferred until residency; these intersections allocate nothing.
  if(!angleCulling||virtualBounds(q,start,direction,h.t,make_float3(side*5.95f,y+1.11f,z+.05f),make_float3(2.55f,1.12f,2.25f))){
  h=virtualSpecialRoom(q,start,direction,h,type,side,y,z,key,accent);
  if(type==0||type==7){h=virtualBox(q,start,direction,h,make_float3(side*7.1f,y+.30f,z-.15f),make_float3(.62f,.23f,1.22f),UPHOLSTERY,accent);h=virtualBox(q,start,direction,h,make_float3(side*7.55f,y+.76f,z-.15f),make_float3(.18f,.5f,1.22f),UPHOLSTERY,accent*.8f);h=virtualBox(q,start,direction,h,make_float3(side*4.85f,y+.36f,z),make_float3(.58f,.055f,.9f),WOOD,make_float3(.39f,.23f,.12f));}
  if(type==1){h=virtualBox(q,start,direction,h,make_float3(side*7.85f,y+.44f,z-.15f),make_float3(.65f,.44f,1.78f),WOOD,make_float3(.34f,.27f,.18f));h=virtualBox(q,start,direction,h,make_float3(side*7.8f,y+.92f,z-.15f),make_float3(.76f,.05f,1.88f),TILE,make_float3(.84f,.81f,.71f));h=virtualBox(q,start,direction,h,make_float3(side*4.4f,y+.76f,z),make_float3(.8f,.045f,.5f),WOOD,make_float3(.55f,.32f,.15f));}
  if(type==2||type==6){h=virtualBox(q,start,direction,h,make_float3(side*6.9f,y+.76f,z),make_float3(.625f,.045f,1.05f),WOOD,make_float3(.55f,.32f,.15f));h=virtualBox(q,start,direction,h,make_float3(side*6.9f,y+1.12f,z),make_float3(.04f,.3f,.47f),METAL,make_float3(.09f,.1f,.11f));h=virtualBox(q,start,direction,h,make_float3(side*7.8f,y+1.1f,z+1.9f),make_float3(.50f,1.1f,.27f),WOOD,make_float3(.4f,.24f,.12f));}
  if(type==3)h=virtualBox(q,start,direction,h,make_float3(x,y+.76f,z),make_float3(1.1f,.045f,.6f),WOOD,make_float3(.55f,.32f,.15f));
  if(type==4||type==5){h=virtualBox(q,start,direction,h,make_float3(side*6.1f,y+.24f,z),make_float3(1.15f,.2f,type==5?.72f:1.12f),WOOD,make_float3(.28f,.17f,.1f));h=virtualBox(q,start,direction,h,make_float3(side*6.1f,y+.51f,z),make_float3(1.14f,.16f,type==5?.70f:1.10f),UPHOLSTERY,make_float3(.86f,.81f,.69f));h=virtualBox(q,start,direction,h,make_float3(side*7.18f,y+.86f,z),make_float3(.10f,.58f,type==5?.76f:1.16f),UPHOLSTERY,accent);h=virtualBox(q,start,direction,h,make_float3(side*5.7f,y+.69f,z),make_float3(.64f,.035f,type==5?.68f:1.08f),UPHOLSTERY,accent);}
  if(type==0||type==7){for(int leg=-1;leg<=1;leg+=2)h=virtualBox(q,start,direction,h,make_float3(side*4.85f,y+.16f,z+leg*.6f),make_float3(.035f,.16f,.035f),METAL,make_float3(.11f,.13f,.13f));h=virtualChair(q,start,direction,h,side*4.7f,y,z+1.8f,make_float3(.53f,.47f,.35f));}
  if(type==1||type==2||type==3||type==6){float tx=type==1?side*4.4f:(type==3?x:side*6.9f),width=type==1?1.6f:(type==3?2.2f:1.25f),depth=type==1?1:(type==3?1.2f:2.1f);for(int a=-1;a<=1;a+=2)for(int b=-1;b<=1;b+=2)h=virtualBox(q,start,direction,h,make_float3(tx+a*(width*.5f-.12f),y+.36f,z+b*(depth*.5f-.12f)),make_float3(.035f,.36f,.035f),METAL,make_float3(.11f,.13f,.13f));if(type==3)for(int j=-1;j<=1;j+=2){h=virtualChair(q,start,direction,h,x+j*.65f,y,z+1,accent);h=virtualChair(q,start,direction,h,x+j*.65f,y,z-1,accent,-1);}else if(type==1){h=virtualChair(q,start,direction,h,tx,y,z+1,accent);h=virtualChair(q,start,direction,h,tx,y,z-1,accent,-1);}else h=virtualChair(q,start,direction,h,side*5.8f,y,z,accent);}
  }
  h=virtualBox(q,start,direction,h,make_float3(x,y+storey-.18f,z),make_float3(.68f,.035f,.035f),LIGHT,make_float3(1,.81f,.51f));
 }else{
  for(int sideWall=-1;sideWall<=1;sideWall+=2){if(angleCulling&&!virtualBounds(q,start,direction,h.t,make_float3(sideWall*2.4f,y+storey*.5f,-1.3f),make_float3(1.0f,storey*.5f,6.75f)))continue;float last=-8;for(int r=0;r<2;++r){float door=roomZ(q,floor,sideWall,r);h=virtualBox(q,start,direction,h,make_float3(sideWall*1.7f,y+storey*.5f,(last+door-.72f)*.5f),make_float3(.11f,storey*.5f,(door-.72f-last)*.5f),PLASTER,plaster);h=virtualBox(q,start,direction,h,make_float3(sideWall*1.7f,y+(2.4f+storey)*.5f,door),make_float3(.11f,(storey-2.4f)*.5f,.72f),PLASTER,plaster);h=virtualBox(q,start,direction,h,make_float3(sideWall*2.39f,y+1.17f,door+.79f),make_float3(.65f,1.17f,.04f),WOOD,make_float3(.47f,.30f,.17f));h=virtualBox(q,start,direction,h,make_float3(sideWall*3.2f,y+1.2f,door),make_float3(.02f,1.2f,.72f),PLASTER,plaster*.6f);for(int edge=-1;edge<=1;edge+=2)h=virtualBox(q,start,direction,h,make_float3(sideWall*1.7f,y+1.2f,door+edge*.76f),make_float3(.16f,1.2f,.045f),WOOD,make_float3(.30f,.20f,.12f));h=virtualBox(q,start,direction,h,make_float3(sideWall*1.7f,y+2.43f,door),make_float3(.16f,.045f,.80f),WOOD,make_float3(.30f,.20f,.12f));last=door+.72f;}h=virtualBox(q,start,direction,h,make_float3(sideWall*1.53f,y+storey-.23f,-1.3f),make_float3(.09f,.065f,6.6f),PLASTER,make_float3(.89f,.86f,.76f));h=virtualBox(q,start,direction,h,make_float3(sideWall*1.7f,y+storey*.5f,(last+5.4f)*.5f),make_float3(.11f,storey*.5f,(5.4f-last)*.5f),PLASTER,plaster);}
  h=virtualBox(q,start,direction,h,make_float3(0,y+storey*.5f,11.0f),make_float3(1.8f,storey*.5f,.10f),PLASTER,plaster);
  if(floor<(int)q[8]-1&&(!angleCulling||virtualBounds(q,start,direction,h.t,make_float3(-.94f,y+storey*.25f,7.0f),make_float3(.73f,storey*.25f+.16f,1.5f))))for(int j=0;j<10;++j){float height=(j+1)*storey/20.0f;h=virtualBox(q,start,direction,h,make_float3(-.94f,y+height-.08f,5.65f+j*.30f),make_float3(.73f,.08f,.15f),WOOD,make_float3(.43f,.28f,.16f));}
  for(int j=0;j<4;++j)h=virtualBox(q,start,direction,h,make_float3(0,y+storey-.24f,-6+j*3.5f),make_float3(.45f,.028f,.05f),LIGHT,make_float3(1,.83f,.57f));
 }
 float3 color=plaster*.25f;if(h.id>=0){float3 p=start+direction*h.t;Shape o=h.feature;float3 lamp=make_float3((corridor?0:x)*sx,y+storey-.3f,(corridor?floorf((p.z/sz+6)/3.5f+.5f)*3.5f-6:z)*sz);float3 delta=lamp-p;float light=.30f+.80f*clamp(dot(h.n,norm(delta)))/(1+dot(delta,delta)*.035f);color=surfaceMaterial(o,p,h.n,(entry.t+h.t)*pixelScale)*make_float3(light*.96f,light*.98f,light);if(o.mat==LIGHT)color=o.color*3;}
 if(opening.mat==VIRTUAL_WINDOW){float fresnel=.035f+.65f*powf(1-fabsf(dot(rd,entry.n)),5);color=lerp(color*make_float3(.94f,.98f,.98f),sky(rd-entry.n*(2*dot(rd,entry.n))),fresnel);}return color;
}
__device__ float3 shade(float* s,const float* nodes,float3 ro,float3 rd,Hit h,unsigned int rng,float pixelScale,bool detailed,float filteredSun=-1){
    if(h.id<0)return sky(rd);Shape o=hitShape(s,h);float3 p=ro+rd*h.t,n=h.n,c=material(s,o,p,n,h.t*pixelScale);
    if(o.mat==VIRTUAL_WINDOW||o.mat==VIRTUAL_DOOR)return make_float3(.3f,.3f,.3f);
    if(o.mat==LIGHT)return o.color*3;
    float3 localP=rotateY(p,-s[18]);float sx=s[5],sz=s[6];int floor=0;for(int f=1;f<(int)s[8];++f)if(p.y+.05f>=floorBase(s,f))floor=f;float base=floorBase(s,floor),ceiling=floorBase(s,floor+1);
    bool indoors=fabsf(localP.x)<9.15f*sx&&localP.z>-8.25f*sz&&localP.z<11.2f*sz&&p.y<floorBase(s,(int)s[8])-.1f;
    float ambient=indoors?.20f:.40f;float3 illumination=make_float3(ambient*.9f,ambient*.95f,ambient);
    float3 sun=norm(make_float3(-.7f,1,-.5f));float nd=clamp(dot(n,sun));
    if(nd>0){if(filteredSun>=0)illumination=illumination+make_float3(2.4f,2.05f,1.55f)*(nd*filteredSun);else{float3 jitter=make_float3(randf(rng)-.5f,randf(rng+1)-.5f,randf(rng+2)-.5f)*.025f;float3 l=norm(sun+jitter);bool visible=false;if(h.id==CAP)visible=h.visibility>.5f;else{Hit sh=trace(s,nodes,p+n*.003f,l,80,true);visible=sh.id<0;}if(visible)illumination=illumination+make_float3(2.4f,2.05f,1.55f)*nd;}}
    if(indoors){
        int side=localP.x<0?-1:1,back=localP.z/sz<roomSplit(s,floor,side)?0:1;float rz=roomZ(s,floor,side,back)*sz;
        float3 lamp;if(fabsf(localP.x)<1.85f*sx)lamp=make_float3(0,ceiling-.35f,(floorf((localP.z/sz+6)/3.5f+.5f)*3.5f-6)*sz);else lamp=make_float3(side*5.2f*sx,ceiling-.3f,rz);
        if(localP.z>5.4f*sz)lamp=make_float3(0,ceiling-.2f,8.8f*sz);
        lamp=rotateY(lamp,s[18]);
        float3 delta=lamp-p;float dist=sqrtf(dot(delta,delta));float3 l=delta/fmaxf(.01f,dist);float cosine=clamp(dot(n,l));
        if(cosine>0){Hit sh=trace(s,nodes,p+n*.005f,l,dist-.08f,true);if(sh.id<0)illumination=illumination+make_float3(1.0f,.81f,.59f)*(cosine*5.5f/(1+dist*dist*.55f));}
        // Broad diffuse fill from the nearest real window.
        float3 window=make_float3(side*8.9f*sx,base+1.85f,rz);window=rotateY(window,s[18]);float3 wl=norm(window-p);
        float facing=clamp(dot(n,wl));illumination=illumination+make_float3(.43f,.51f,.59f)*(facing/(1+fabsf(window.x-p.x)*.12f));
    }
    if(detailed){float3 random=norm(make_float3(randf(rng+3)*2-1,randf(rng+4)*2-1,randf(rng+5)*2-1));float3 ao=norm(n+random);if(dot(ao,n)<.01f)ao=n;
        Hit occ=trace(s,nodes,p+n*.004f,ao,1.1f,true);if(occ.id>=0)illumination=illumination*(.6f+.4f*clamp(occ.t/1.1f));}
    return c*illumination;
}
// Read only the surface attributes needed to keep a shadow filter on its receiver.
__device__ Hit shadowSurface(float* s,const float* Far,int i){int b=i*16;Hit h;h.id=(int)(-Far[b])-2;h.t=Far[b+1];h.n=make_float3(Far[b+2],Far[b+3],Far[b+4]);if(Far[b]>0){h.id=CAP;h.t=Far[b];h.n=make_float3(Far[b+1],Far[b+2],Far[b+3]);h.feature.mat=(int)Far[b+7];h.feature.id=(unsigned int)Far[b+8]|((unsigned int)Far[b+9]<<16);}else if(h.id>=0)h.feature=readShape(s,h.id);return h;}
// One existing sun ray per opaque receiver, moved out of shade only during motion.
__global__ void movingShadows(float* s,const float* nodes,const float* C,const float* Far,const float* Glass,const float* MotionHistory,float* Shadows,int w,int h,int enabled=1){
 int x=(int)(blockIdx.x*blockDim.x+threadIdx.x),y=(int)blockIdx.y;if(x>=w||y>=h||C[9]>=64)return;int i=y*w+x,old=w*h*4;Shadows[i]=-1;if(!enabled||C[9]!=0||MotionHistory[old+16]<.5f)return;
 float movement=0;for(int k=0;k<5;++k)movement+=fabsf(C[k]-MotionHistory[old+k]);if(movement<1e-7f)return;
 Hit hit=shadowSurface(s,Far,i);if(hit.id<0||Glass[i*4+3]>0)return;int mat=hit.feature.mat;if(mat==GLASS||mat==LIGHT||mat==LEAF||mat==VIRTUAL_WINDOW||mat==VIRTUAL_DOOR)return;float3 sun=norm(make_float3(-.7f,1,-.5f));if(dot(hit.n,sun)<=0)return;
 if(hit.id==CAP){Shadows[i]=Far[i*16+15];return;}
 Camera cam=readCam(C);float3 f=make_float3(sinf(cam.yaw)*cosf(cam.pitch),sinf(cam.pitch),cosf(cam.yaw)*cosf(cam.pitch)),right=make_float3(cosf(cam.yaw),0,-sinf(cam.yaw)),up=cross(f,right);float sx=(2*(x+.5f)/w-1)*(float(w)/h)*.68f,sy=(1-2*(y+.5f)/h)*.68f;float3 p=cam.foot+make_float3(0,1.65f,0)+norm(f+right*sx+up*sy)*hit.t;unsigned int rng=mix(i);float3 jitter=make_float3(randf(rng)-.5f,randf(rng+1)-.5f,randf(rng+2)-.5f)*.025f;Hit sh=trace(s,nodes,p+hit.n*.003f,norm(sun+jitter),80,true);Shadows[i]=sh.id<0?1:0;
}
__device__ float blurSun(float* s,const float* Far,const float* Shadows,int x,int y,int w,int h){int i=y*w+x;if(Shadows[i]<0)return -1;Hit center=shadowSurface(s,Far,i);float total=Shadows[i]*4,weight=4;
 for(int dy=-1;dy<=1;++dy)for(int dx=-1;dx<=1;++dx){if(dx==0&&dy==0)continue;int nx=x+dx,ny=y+dy;if(nx<0||nx>=w||ny<0||ny>=h)continue;int j=ny*w+nx;if(Shadows[j]<0)continue;Hit other=shadowSurface(s,Far,j);if(other.id<0||other.feature.id!=center.feature.id||other.feature.mat!=center.feature.mat||dot(other.n,center.n)<.999f||fabsf(other.t-center.t)>fmaxf(.05f,center.t*.02f))continue;float a=dx==0||dy==0?2:1;total+=Shadows[j]*a;weight+=a;}return total/weight;
}
__device__ Hit primaryHit(float* s,const float* Far,int i){int cached=i*16;Hit hit;hit.id=(int)(-Far[cached])-2;hit.t=Far[cached+1];hit.n=make_float3(Far[cached+2],Far[cached+3],Far[cached+4]);if(Far[cached]>0){int b=i*16;hit.id=CAP;hit.t=Far[b];hit.n=make_float3(Far[b+1],Far[b+2],Far[b+3]);Shape o;o.lo=make_float3(0,0,0);o.hi=make_float3(Far[b+13],0,Far[b+14]);o.color=make_float3(Far[b+4],Far[b+5],Far[b+6]);o.mat=(int)Far[b+7];o.id=(unsigned int)Far[b+8]|((unsigned int)Far[b+9]<<16);o.origin=make_float3(Far[b+10],0,Far[b+11]);o.angle=Far[b+12];o.solid=1;hit.feature=o;hit.visibility=Far[b+15];}return hit;}
__global__ void render(float* s,const float* nodes,const float* C,const float* Far,const float* Glass,const float* Shadows,unsigned int* pixels,float* history,int w,int h,int quality){
    int x=(int)(blockIdx.x*blockDim.x+threadIdx.x),y=(int)blockIdx.y;if(x>=w||y>=h)return;int i=y*w+x;int sample=(int)C[9];if(sample>=64)return;Camera cam=readCam(C);unsigned int rng=mix(i^sample*747796405u);
    float3 f=make_float3(sinf(cam.yaw)*cosf(cam.pitch),sinf(cam.pitch),cosf(cam.yaw)*cosf(cam.pitch)),right=make_float3(cosf(cam.yaw),0,-sinf(cam.yaw)),up=cross(f,right);
    float jx=sample?randf(rng)-.5f:0,jy=sample?randf(rng+7)-.5f:0;
    float sx=(2*(x+.5f+jx)/w-1)*(float(w)/h)*.68f,sy=(1-2*(y+.5f+jy)/h)*.68f;
    float3 ro=cam.foot+make_float3(0,1.65f,0),rd=norm(f+right*sx+up*sy);Hit hit=primaryHit(s,Far,i);float3 color;
    if(Glass[i*4+3]<0)color=make_float3(Glass[i*4],Glass[i*4+1],Glass[i*4+2]);
    else if(hit.id>=0&&hitShape(s,hit).mat==GLASS&&!(hit.id==CAP&&Glass[i*4+3]>0)){
        float3 p=ro+rd*hit.t;Hit through=trace(s,nodes,p+rd*.06f,rd);color=shade(s,nodes,p+rd*.06f,rd,through,rng,1.f/h,quality>0);
        float3 reflected=rd-hit.n*(2*dot(rd,hit.n));float fresnel=.035f+.65f*powf(1-fabsf(dot(rd,hit.n)),5);
        color=lerp(color*make_float3(.94f,.98f,.98f),sky(reflected),fresnel);
    }else color=shade(s,nodes,ro,rd,hit,rng,1.f/h,quality>0,blurSun(s,Far,Shadows,x,y,w,h));
    if(hit.id==CAP&&Glass[i*4+3]>0)color=lerp(color*make_float3(.94f,.98f,.98f),make_float3(Glass[i*4],Glass[i*4+1],Glass[i*4+2]),Glass[i*4+3]);
    if(sample>0)color=lerp(make_float3(history[i*4],history[i*4+1],history[i*4+2]),color,1.f/(sample+1));history[i*4]=color.x;history[i*4+1]=color.y;history[i*4+2]=color.z;
    color=color*1.35f;
    // ACES-style filmic curve with display gamma.
    float vals[3]={color.x,color.y,color.z};unsigned int bytes[3];for(int k=0;k<3;++k){float v=vals[k];v=clamp((v*(2.51f*v+.03f))/(v*(2.43f*v+.59f)+.14f));bytes[k]=static_cast<unsigned int>(powf(v,1/2.2f)*255+.5f);}
    pixels[i]=0xff000000u|bytes[0]|(bytes[1]<<8)|(bytes[2]<<16);
}

__device__ bool overlap(float lo,float hi,float a,float b){return lo<b-.001f&&hi>a+.001f;}
__device__ bool freeBody(float* s,float3 foot){for(int i=0;i<((int)s[1]);++i){Shape o=readShape(s,i);if(!o.solid)continue;if(overlap(foot.x-.26f,foot.x+.26f,o.lo.x,o.hi.x)&&overlap(foot.y+.015f,foot.y+1.78f,o.lo.y,o.hi.y)&&overlap(foot.z-.26f,foot.z+.26f,o.lo.z,o.hi.z))return false;}return true;}
__device__ Camera horizontal(float* s,Camera c,float delta,int axis){
    if(fabsf(delta)<1e-8f)return c;float3 target=c.foot;if(axis==0)target.x+=delta;else target.z+=delta;
    float stepTop=c.foot.y;bool obstacle=false;
    for(int i=0;i<((int)s[1]);++i){Shape o=readShape(s,i);if(!o.solid)continue;
        if(overlap(target.x-.26f,target.x+.26f,o.lo.x,o.hi.x)&&overlap(target.z-.26f,target.z+.26f,o.lo.z,o.hi.z)&&overlap(target.y+.015f,target.y+1.78f,o.lo.y,o.hi.y)){
            obstacle=true;stepTop=fmaxf(stepTop,o.hi.y);}}
    if(!obstacle){c.foot=target;return c;}
    if(c.grounded&&stepTop-c.foot.y<=.23f){float3 stepped=target;stepped.y=stepTop+.002f;if(freeBody(s,stepped)){c.foot=stepped;c.vy=0;return c;}}
    for(int i=0;i<((int)s[1]);++i){Shape o=readShape(s,i);if(!o.solid)continue;
        if(!overlap(c.foot.y+.015f,c.foot.y+1.78f,o.lo.y,o.hi.y))continue;
        float old=axis==0?c.foot.x:c.foot.z,other=axis==0?c.foot.z:c.foot.x;
        float alo=axis==0?o.lo.x:o.lo.z,ahi=axis==0?o.hi.x:o.hi.z,blo=axis==0?o.lo.z:o.lo.x,bhi=axis==0?o.hi.z:o.hi.x;
        if(!overlap(other-.26f,other+.26f,blo,bhi))continue;
        float next=axis==0?target.x:target.z;
        if(delta>0&&old+.26f<=alo+.003f&&next+.26f>alo)next=fminf(next,alo-.261f);
        if(delta<0&&old-.26f>=ahi-.003f&&next-.26f<ahi)next=fmaxf(next,ahi+.261f);
        if(axis==0)target.x=next;else target.z=next;
    }
    if(freeBody(s,target))c.foot=target;return c;
}
__global__ void simulate(float* s,float* C,const float* I,int steps){if(threadIdx.x||blockIdx.x)return;Camera c=readCam(C);Input input;input.forward=I[0];input.side=I[1];input.dx=I[2];input.dy=I[3];input.sprint=(int)I[4];input.jump=(int)I[5];
    float3 startFoot=c.foot;
    c.yaw+=input.dx*.0022f;c.pitch=clamp(c.pitch-input.dy*.0022f,-1.45f,1.45f);
    if(I[6]>.5f){float3 forward=make_float3(sinf(c.yaw)*cosf(c.pitch),sinf(c.pitch),cosf(c.yaw)*cosf(c.pitch)),right=make_float3(cosf(c.yaw),0,-sinf(c.yaw));float3 d=forward*input.forward+right*input.side+make_float3(0,I[8],0);if(dot(d,d)>0)c.foot=c.foot+norm(d)*I[7]*(input.sprint?3.0f:1.0f)*(float)steps/120.0f;c.foot.y=fmaxf(.2f,c.foot.y);c.vy=0;c.grounded=0;if(dot(c.foot-startFoot,c.foot-startFoot)>.00000001f||input.dx!=0||input.dy!=0)C[9]=0;writeCam(C,c);return;}
    c.foot=rotateY(c.foot,-s[18]);c.yaw-=s[18];
    for(int t=0;t<steps;++t){float dt=1.f/120;
        if(t==0&&input.jump&&c.grounded){c.vy=4.5f;c.grounded=0;}
        float3 d=make_float3(sinf(c.yaw),0,cosf(c.yaw))*input.forward+make_float3(cosf(c.yaw),0,-sinf(c.yaw))*input.side;
        if(dot(d,d)>0)d=norm(d)*(input.sprint?4.1f:2.5f)*dt;
        float3 before=c.foot;c=horizontal(s,c,d.x,0);c=horizontal(s,c,d.z,2);
        c.vy=fmaxf(-25,c.vy-9.81f*dt);float next=c.foot.y+c.vy*dt;c.grounded=0;
        for(int i=0;i<((int)s[1]);++i){Shape o=readShape(s,i);if(!o.solid||!overlap(c.foot.x-.26f,c.foot.x+.26f,o.lo.x,o.hi.x)||!overlap(c.foot.z-.26f,c.foot.z+.26f,o.lo.z,o.hi.z))continue;
            if(c.vy<=0&&c.foot.y>=o.hi.y-.022f&&next<=o.hi.y){next=fmaxf(next,o.hi.y);c.grounded=1;}
            if(c.vy>0&&c.foot.y+1.78f<=o.lo.y+.002f&&next+1.78f>=o.lo.y)next=fminf(next,o.lo.y-1.781f);
        }
        if(c.grounded||fabsf(next-c.foot.y-c.vy*dt)>.0001f)c.vy=0;c.foot.y=next;c.distance+=sqrtf(dot(c.foot-before,c.foot-before));
    }c.foot=rotateY(c.foot,s[18]);c.yaw+=s[18];if(dot(c.foot-startFoot,c.foot-startFoot)>.00000001f||input.dx!=0||input.dy!=0)C[9]=0.0f;writeCam(C,c);
}

__global__ void accumulate(float* C){if(threadIdx.x||blockIdx.x)return;C[9]=fminf(64.0f,C[9]+1.0f);}


__global__ void initCamera(float* s,float* C,int view){if(threadIdx.x||blockIdx.x)return;for(int i=0;i<16;++i)C[i]=0.0f;C[2]=-15.0f;
if(view==1){C[0]=15;C[1]=3;C[2]=-22;C[3]=-.65f;C[4]=.04f;}
if(view==2){C[0]=.2f;C[2]=-7;C[3]=.08f;C[4]=.02f;}
if(view==3){C[0]=-2.6f;C[2]=-6.5f;C[3]=-.87f;C[4]=-.06f;}
if(view==4){C[0]=-.3f;C[2]=3.8f;C[3]=.03f;C[4]=.18f;}
if(view==5){C[2]=4.7f;C[1]=floorBase(s,(int)s[8]-1);C[3]=PI;C[4]=-.03f;}float3 pos=rotateY(make_float3(C[0]*s[5],C[1],C[2]*s[6]),s[18]);C[0]=pos.x;C[2]=pos.z;C[3]+=s[18];}

__global__ void probeOutdoor(float* s,const float* I,float* Plan){if(threadIdx.x||blockIdx.x)return;float3 c=outdoorMaterial(s,make_float3(I[0],0,I[1]),0);Plan[60]=c.x;Plan[61]=c.y;Plan[62]=c.z;}

__global__ void probeRay(float* s,const float* nodes,const float* Districts,const float* I,float* Plan,int cacheEnabled=1,int virtualEnabled=1){if(threadIdx.x||blockIdx.x)return;Hit h=trace(s,nodes,make_float3(I[0],I[1],I[2]),norm(make_float3(I[3],I[4],I[5])));h=distantQuery(s,Districts,make_float3(I[0],I[1],I[2]),norm(make_float3(I[3],I[4],I[5])),h,false,cacheEnabled,virtualEnabled);Plan[56]=h.t;Plan[57]=(float)h.id;if(h.id>=0){Shape o=hitShape(s,h);Plan[58]=(float)o.mat;Plan[59]=o.color.x;Plan[60]=o.color.y;Plan[61]=o.color.z;}}

__global__ void probeStreet(float* s,const float* I,float* Plan){if(threadIdx.x||blockIdx.x)return;Street r=street((unsigned int)s[22],(int)I[0],(int)I[1],(int)I[2]);Plan[40]=districtValue((unsigned int)s[22],(int)I[0],(int)I[1]);Plan[41]=neighbourhoodValue((unsigned int)s[22],(int)I[0],(int)I[1]);Plan[42]=propertyValue((unsigned int)s[22],(int)I[0],(int)I[1]);Plan[45]=(float)r.terminal;Plan[44]=highwayDistance((unsigned int)s[22],(int)I[0]);Plan[43]=(float)highwayOffset((unsigned int)s[22]);Plan[48]=(float)r.kind;Plan[49]=(float)r.active;Plan[50]=r.a.x;Plan[51]=r.a.z;Plan[52]=r.b.x;Plan[53]=r.b.z;Plan[54]=r.width;Plan[55]=(float)(neighbourhoodKey((unsigned int)s[22],(int)I[0],(int)I[1])&16777215u);}

// Keep procedural traversal in its own compute pass to bound driver compilation work.
__global__ void farVisibility(float* s,const float* nodes,const float* Districts,const float* C,float* Far,float* Glass,int w,int h,int cacheEnabled=1,int virtualEnabled=1){
 int x=(int)(blockIdx.x*blockDim.x+threadIdx.x),y=(int)blockIdx.y;if(x>=w||y>=h)return;int i=y*w+x,sample=(int)C[9];if(sample>=64)return;Far[i*16]=0;Glass[i*4+3]=0;
 Camera cam=readCam(C);unsigned int rng=mix(i^sample*747796405u);float3 f=make_float3(sinf(cam.yaw)*cosf(cam.pitch),sinf(cam.pitch),cosf(cam.yaw)*cosf(cam.pitch)),right=make_float3(cosf(cam.yaw),0,-sinf(cam.yaw)),up=cross(f,right);float jx=sample?randf(rng)-.5f:0,jy=sample?randf(rng+7)-.5f:0;float sx=(2*(x+.5f+jx)/w-1)*(float(w)/h)*.68f,sy=(1-2*(y+.5f+jy)/h)*.68f;
 float3 ro=cam.foot+make_float3(0,1.65f,0),rd=norm(f+right*sx+up*sy);Hit hit=trace(s,nodes,ro,rd);
 // Negative marker caches the exact resident hit (including misses) for shading.
 int primary=i*16;Far[primary]=-(float)(hit.id+2);Far[primary+1]=hit.t;Far[primary+2]=hit.n.x;Far[primary+3]=hit.n.y;Far[primary+4]=hit.n.z;
 hit=distantQuery(s,Districts,ro,rd,hit,false,cacheEnabled,virtualEnabled);bool firstFar=hit.id==CAP;if(!firstFar&&!(hit.id>=0&&hitShape(s,hit).mat==GLASS))return;
 if(hit.id>=0&&hitShape(s,hit).mat==GLASS){float3 reflected=rd-hit.n*(2*dot(rd,hit.n)),reflection=sky(reflected);float fresnel=.035f+.65f*powf(1-fabsf(dot(rd,hit.n)),5),offset=hit.t+.06f;float3 throughOrigin=ro+rd*offset;Hit next=trace(s,nodes,throughOrigin,rd);next=distantQuery(s,Districts,throughOrigin,rd,next,false,cacheEnabled,virtualEnabled);if(next.id>=0){if(!firstFar&&next.id!=CAP&&hitShape(s,next).mat!=VIRTUAL_WINDOW&&hitShape(s,next).mat!=VIRTUAL_DOOR)return;Shape feature=hitShape(s,next);hit=next;hit.id=CAP;hit.feature=feature;hit.t+=offset;Glass[i*4]=reflection.x;Glass[i*4+1]=reflection.y;Glass[i*4+2]=reflection.z;Glass[i*4+3]=fresnel;}}
 if(hit.id!=CAP)return;Shape o=hit.feature;int b=i*16;
 float3 p=ro+rd*hit.t,sun=norm(make_float3(-.7f,1,-.5f)),jitter=make_float3(randf(rng)-.5f,randf(rng+1)-.5f,randf(rng+2)-.5f)*.025f,l=norm(sun+jitter);Far[b+15]=1;if(o.mat!=VIRTUAL_WINDOW&&o.mat!=VIRTUAL_DOOR){Hit sh=trace(s,nodes,p+hit.n*.003f,l,80,true);sh=distantQuery(s,Districts,p+hit.n*.003f,l,sh,true,cacheEnabled,virtualEnabled);Far[b+15]=sh.id<0?1:0;}
 Far[b]=hit.t;Far[b+1]=hit.n.x;Far[b+2]=hit.n.y;Far[b+3]=hit.n.z;Far[b+4]=o.color.x;Far[b+5]=o.color.y;Far[b+6]=o.color.z;Far[b+7]=(float)o.mat;Far[b+8]=(float)(o.id&65535u);Far[b+9]=(float)(o.id>>16);Far[b+10]=o.origin.x;Far[b+11]=o.origin.z;Far[b+12]=o.angle;Far[b+13]=o.hi.x-o.lo.x;Far[b+14]=o.hi.z-o.lo.z;
}

// Only opening pixels evaluate room mapping. Reuse the existing glass buffer;
// negative alpha marks a completed virtual view for the ordinary render pass.
__global__ void virtualOpenings(float* s,const float* C,const float* Far,float* Glass,int w,int h,int angleCulling=1){
 int x=(int)(blockIdx.x*blockDim.x+threadIdx.x),y=(int)blockIdx.y;if(x>=w||y>=h||C[9]>=64)return;int i=y*w+x,sample=(int)C[9];Hit hit=primaryHit(s,Far,i);if(hit.id<0)return;int mat=hitShape(s,hit).mat;if(mat!=VIRTUAL_WINDOW&&mat!=VIRTUAL_DOOR)return;
 Camera cam=readCam(C);unsigned int rng=mix(i^sample*747796405u);float3 f=make_float3(sinf(cam.yaw)*cosf(cam.pitch),sinf(cam.pitch),cosf(cam.yaw)*cosf(cam.pitch)),right=make_float3(cosf(cam.yaw),0,-sinf(cam.yaw)),up=cross(f,right);float jx=sample?randf(rng)-.5f:0,jy=sample?randf(rng+7)-.5f:0;float sx=(2*(x+.5f+jx)/w-1)*(float(w)/h)*.68f,sy=(1-2*(y+.5f+jy)/h)*.68f;float3 ro=cam.foot+make_float3(0,1.65f,0),rd=norm(f+right*sx+up*sy),color=virtualInterior(s,ro,rd,hit,1.f/h,angleCulling);
 if(Glass[i*4+3]>0)color=lerp(color*make_float3(.94f,.98f,.98f),make_float3(Glass[i*4],Glass[i*4+1],Glass[i*4+2]),Glass[i*4+3]);Glass[i*4]=color.x;Glass[i*4+1]=color.y;Glass[i*4+2]=color.z;Glass[i*4+3]=-1;
}
// Reproject only verified diffuse surfaces. Full current visibility/shading still runs.
// Far is reused as the current surface buffer after render has consumed its ray records.
__global__ void temporalResolve(float* s,const float* C,float* Far,const float* Glass,float* history,const float* MotionHistory,const float* MotionSurface,unsigned int* pixels,int w,int h,int enabled=1){
 int x=(int)(blockIdx.x*blockDim.x+threadIdx.x),y=(int)blockIdx.y;if(x>=w||y>=h||C[9]>=64||!enabled)return;int i=y*w+x,b=i*16,old=w*h*4;float mark=Far[b],t;float3 n;unsigned int key=0;int mat=-1;
 if(mark>0){t=Far[b];n=make_float3(Far[b+1],Far[b+2],Far[b+3]);mat=(int)Far[b+7];key=(unsigned int)Far[b+8]|((unsigned int)Far[b+9]<<16);}else{int id=(int)(-mark)-2;t=Far[b+1];n=make_float3(Far[b+2],Far[b+3],Far[b+4]);if(id>=0){Shape o=readShape(s,id);mat=o.mat;key=o.id;}}
 Camera cam=readCam(C);int sample=(int)C[9];unsigned int rng=mix(i^sample*747796405u);float3 f=make_float3(sinf(cam.yaw)*cosf(cam.pitch),sinf(cam.pitch),cosf(cam.yaw)*cosf(cam.pitch)),right=make_float3(cosf(cam.yaw),0,-sinf(cam.yaw)),up=cross(f,right);float jx=sample?randf(rng)-.5f:0,jy=sample?randf(rng+7)-.5f:0;
 float sx=(2*(x+.5f+jx)/w-1)*(float(w)/h)*.68f,sy=(1-2*(y+.5f+jy)/h)*.68f;float3 point=cam.foot+make_float3(0,1.65f,0)+norm(f+right*sx+up*sy)*t;
 bool eligible=mat>=0&&mat!=GLASS&&mat!=VIRTUAL_WINDOW&&mat!=VIRTUAL_DOOR&&mat!=METAL&&mat!=LIGHT&&mat!=LEAF&&Glass[i*4+3]==0;
 float identity=(float)((key&65535u)+(unsigned int)(mat<0?0:mat)*65536u);history[i*4+3]=0;
 if(eligible&&sample==0&&MotionHistory[old+16]>.5f){
  float3 oldFoot=make_float3(MotionHistory[old],MotionHistory[old+1],MotionHistory[old+2]),move=cam.foot-oldFoot;float yaw=MotionHistory[old+3],pitch=MotionHistory[old+4];float3 pf=make_float3(sinf(yaw)*cosf(pitch),sinf(pitch),cosf(yaw)*cosf(pitch)),pr=make_float3(cosf(yaw),0,-sinf(yaw)),pu=cross(pf,pr),delta=point-oldFoot-make_float3(0,1.65f,0);float z=dot(delta,pf),motion=dot(move,move);
  if(z>.05f&&motion<4.0f&&dot(f,pf)>.95f&&(motion>1e-10f||fabsf(cam.yaw-yaw)>1e-7f||fabsf(cam.pitch-pitch)>1e-7f)){
   int px=(int)floorf((dot(delta,pr)/(z*.68f*(float(w)/h))+1)*.5f*w),py=(int)floorf((1-dot(delta,pu)/(z*.68f))*.5f*h);
   if(px>=0&&px<w&&py>=0&&py<h){int j=py*w+px,a=j*8;float3 previous=make_float3(MotionSurface[a],MotionSurface[a+1],MotionSurface[a+2]),pn=make_float3(MotionSurface[a+3],MotionSurface[a+4],MotionSurface[a+5]),error=previous-point;float tolerance=clamp(t*1.8f/h,.02f,.12f);
    if(MotionSurface[a+6]==identity&&MotionSurface[a+7]==(float)(key>>16)&&dot(n,pn)>.999f&&fabsf(dot(error,n))<.01f&&dot(error,error)<tolerance*tolerance){
     float3 current=make_float3(history[i*4],history[i*4+1],history[i*4+2]),past=make_float3(MotionHistory[j*4],MotionHistory[j*4+1],MotionHistory[j*4+2]);float count=fminf(7,fmaxf(MotionHistory[j*4+3],MotionHistory[old+9]+1)),alpha=count/(count+1);
     float3 radius=make_float3(.005f,.005f,.005f)+current*.03f;past=vmax(current-radius,vmin(current+radius,past));float3 color=lerp(current,past,alpha);history[i*4]=color.x;history[i*4+1]=color.y;history[i*4+2]=color.z;history[i*4+3]=count+1;
     color=color*1.35f;float vals[3]={color.x,color.y,color.z};unsigned int bytes[3];for(int k=0;k<3;++k){float v=vals[k];v=clamp((v*(2.51f*v+.03f))/(v*(2.43f*v+.59f)+.14f));bytes[k]=(unsigned int)(powf(v,1/2.2f)*255+.5f);}pixels[i]=0xff000000u|bytes[0]|(bytes[1]<<8)|(bytes[2]<<16);
    }
   }
  }
 }
 Far[b]=point.x;Far[b+1]=point.y;Far[b+2]=point.z;Far[b+3]=n.x;Far[b+4]=n.y;Far[b+5]=n.z;Far[b+6]=eligible?identity:-1;Far[b+7]=(float)(key>>16);
}
__global__ void rememberFrame(const float* s,const float* C,const float* Far,const float* history,float* MotionHistory,float* MotionSurface,int w,int h,int enabled=1){int i=(int)(blockIdx.x*blockDim.x+threadIdx.x);if(i>=w*h||C[9]>=64||!enabled)return;for(int k=0;k<4;++k)MotionHistory[i*4+k]=history[i*4+k];for(int k=0;k<8;++k)MotionSurface[i*8+k]=Far[i*16+k];if(i==0){int b=w*h*4;for(int k=0;k<16;++k)MotionHistory[b+k]=C[k];MotionHistory[b+16]=1;}}
