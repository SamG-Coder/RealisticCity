#define NOMINMAX
#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <cuda_runtime.h>
#include <thrust/device_ptr.h>
#include <thrust/sort.h>
#include <algorithm>
#include <chrono>
#include <cmath>
#include <cstdint>
#include <fstream>
#include <iostream>
#include <stdexcept>
#include <string>
#include <vector>

#define CU(call) do { cudaError_t status_=(call); if(status_!=cudaSuccess)throw std::runtime_error(std::string(#call)+": "+cudaGetErrorString(status_)); } while(0)
#define HD __host__ __device__
using U=uint32_t;
constexpr int CAP=4096,LEVELS=12;
constexpr float PI=3.14159265359f;
struct V {float x,y,z;HD V(float a=0,float b=0,float c=0):x(a),y(b),z(c){} };
HD V operator+(V a,V b){return V(a.x+b.x,a.y+b.y,a.z+b.z);} HD V operator-(V a,V b){return V(a.x-b.x,a.y-b.y,a.z-b.z);}
HD V operator*(V a,float b){return V(a.x*b,a.y*b,a.z*b);} HD V operator*(float b,V a){return a*b;} HD V operator*(V a,V b){return V(a.x*b.x,a.y*b.y,a.z*b.z);}
HD V operator/(V a,float b){return a*(1/b);} HD float dot(V a,V b){return a.x*b.x+a.y*b.y+a.z*b.z;}
HD V cross(V a,V b){return V(a.y*b.z-a.z*b.y,a.z*b.x-a.x*b.z,a.x*b.y-a.y*b.x);}
HD V norm(V a){return a*(1/sqrtf(fmaxf(1e-12f,dot(a,a))));}
HD V vmin(V a,V b){return V(fminf(a.x,b.x),fminf(a.y,b.y),fminf(a.z,b.z));} HD V vmax(V a,V b){return V(fmaxf(a.x,b.x),fmaxf(a.y,b.y),fmaxf(a.z,b.z));}
HD float clamp(float x,float a=0,float b=1){return fminf(b,fmaxf(a,x));} HD V lerp(V a,V b,float t){return a*(1-t)+b*t;}
HD U mix(U x){x^=x>>16;x*=0x7feb352du;x^=x>>15;x*=0x846ca68bu;return x^(x>>16);}
HD float randf(U x){return (mix(x)&0xffffff)/16777216.f;}
HD float fract(float x){return x-floorf(x);}
enum Mat {PLASTER,BRICK,WOOD,CONCRETE,METAL,FABRIC,GLASS,LIGHT,TILE,LEAF,ASPHALT};
struct Shape{V lo,hi,color;U id;int mat,solid;};
struct Node{V lo,hi;int shape;};
struct Scene{Shape objects[CAP];int count,overflow;U seed;};
struct Camera{V foot;float yaw,pitch,vy;int grounded;float distance;};
struct Input{float forward,side,dx,dy;int sprint,jump;};

__device__ void box(Scene* s,V p,V half,int mat,V color,bool solid=true){
    int i=s->count;if(i>=CAP){s->overflow=1;return;}s->count++;
    s->objects[i]={p-half,p+half,color,mix(s->seed^static_cast<U>(i)),mat,solid?1:0};
}
__device__ void between(Scene* s,V lo,V hi,int mat,V c,bool solid=true){box(s,(lo+hi)*.5f,(hi-lo)*.5f,mat,c,solid);}
__device__ void leg(Scene* s,float x,float y,float z,float height){box(s,V(x,y+height*.5f,z),V(.035f,height*.5f,.035f),METAL,V(.11f,.13f,.13f));}
__device__ void table(Scene* s,float x,float y,float z,float width,float depth){
    box(s,V(x,y+.76f,z),V(width*.5f,.045f,depth*.5f),WOOD,V(.55f,.32f,.15f));
    for(int a=-1;a<=1;a+=2)for(int b=-1;b<=1;b+=2)leg(s,x+a*(width*.5f-.12f),y,z+b*(depth*.5f-.12f),.72f);
}
__device__ void chair(Scene* s,float x,float y,float z,V col,int face=1){
    box(s,V(x,y+.45f,z),V(.24f,.055f,.23f),FABRIC,col);
    box(s,V(x,y+.77f,z+face*.20f),V(.24f,.28f,.05f),FABRIC,col);
    for(int a=-1;a<=1;a+=2)for(int b=-1;b<=1;b+=2)leg(s,x+a*.18f,y,z+b*.17f,.42f);
}
__device__ void plant(Scene* s,float x,float y,float z,float size=1){
    box(s,V(x,y+.2f*size,z),V(.18f*size,.2f*size,.18f*size),CONCRETE,V(.68f,.58f,.44f));
    box(s,V(x,y+.7f*size,z),V(.025f,.5f*size,.025f),WOOD,V(.2f,.16f,.07f),false);
    for(int i=0;i<7;++i){float a=i*2.4f;box(s,V(x+cosf(a)*.16f*size,y+(.6f+i*.08f)*size,z+sinf(a)*.16f*size),V(.22f*size,.055f*size,.15f*size),LEAF,V(.13f,.27f,.09f),false);}
}
__device__ void art(Scene* s,float x,float y,float z,int side,U seed){
    box(s,V(x,y,z),V(.045f,.62f,.83f),WOOD,V(.2f,.12f,.07f),false);
    box(s,V(x-side*.05f,y,z),V(.015f,.56f,.77f),PLASTER,V(.88f,.83f,.73f),false);
    for(int i=0;i<4;++i)box(s,V(x-side*.07f,y+(randf(seed+i)-.5f)*.65f,z+(randf(seed+20+i)-.5f)*.9f),V(.01f,.1f+randf(seed+40+i)*.16f,.1f+randf(seed+80+i)*.18f),PLASTER,V(.15f+randf(seed+i)*.35f,.24f+randf(seed+60+i)*.2f,.22f),false);
}
__device__ void room(Scene* s,int floor,int side,int back){
    float y=floor*3.2f,x=side*5.2f,z=back?1.8f:-4.8f;U key=mix(s->seed^mix(floor*101+side*17+back*43));
    V accent=lerp(V(.30f,.39f,.38f),V(.52f,.29f,.17f),randf(key));
    int type=floor==0?(back?(side<0?2:3):(side<0?0:1)):(floor+back+(side>0)+static_cast<int>(key%2))%4+4;
    // Common details, ceiling fixtures, rug, art, power outlets.
    box(s,V(x,y+3.02f,z),V(.68f,.035f,.035f),LIGHT,V(1,.81f,.51f),false);
    box(s,V(x,y+.012f,z),V(1.55f,.009f,1.55f),FABRIC,lerp(accent,V(.72f,.64f,.51f),.55f),false);
    art(s,side*8.67f,y+1.65f,z,side,key);
    for(int j=0;j<2;++j)box(s,V(side*1.84f,y+.35f,z+(j?1.5f:-1.6f)),V(.025f,.06f,.09f),PLASTER,V(.86f,.84f,.77f),false);
    plant(s,side*7.8f,y,z+1.7f,.9f);
    if(type==0 || type==7){
        // Sofa at the outer side, low table, lounge chair.
        box(s,V(side*7.1f,y+.30f,z-.15f),V(.62f,.23f,1.22f),FABRIC,accent);
        box(s,V(side*7.55f,y+.76f,z-.15f),V(.18f,.5f,1.22f),FABRIC,accent*.8f);
        for(int j=-1;j<=1;j+=2)box(s,V(side*7.1f,y+.56f,z+j*1.1f-.15f),V(.63f,.22f,.14f),FABRIC,accent*.8f);
        for(int j=0;j<3;++j)box(s,V(side*6.95f,y+.58f,z-.85f+j*.7f),V(.40f,.08f,.31f),FABRIC,accent*1.15f);
        box(s,V(side*4.85f,y+.36f,z),V(.58f,.055f,.9f),WOOD,V(.39f,.23f,.12f));
        leg(s,side*4.85f,y,z-.6f,.32f);leg(s,side*4.85f,y,z+.6f,.32f);
        box(s,V(side*4.85f,y+.43f,z-.3f),V(.21f,.025f,.3f),PLASTER,V(.70f,.46f,.28f),false);
        chair(s,side*4.7f,y,z+1.8f,V(.53f,.47f,.35f));
    }else if(type==1){
        // Kitchen cabinets with separate doors and handles, counter and hob.
        for(int j=0;j<4;++j){float cz=z-1.5f+j*.9f;
            box(s,V(side*7.85f,y+.44f,cz),V(.65f,.44f,.43f),WOOD,V(.34f,.27f,.18f));
            box(s,V(side*7.17f,y+.45f,cz),V(.025f,.40f,.4f),PLASTER,V(.68f,.68f,.58f));
            box(s,V(side*7.12f,y+.68f,cz),V(.028f,.015f,.17f),METAL,V(.08f,.09f,.085f));
        }
        box(s,V(side*7.8f,y+.92f,z-.15f),V(.76f,.05f,1.88f),TILE,V(.84f,.81f,.71f));
        box(s,V(side*7.7f,y+.979f,z-.9f),V(.49f,.012f,.42f),METAL,V(.07f,.085f,.085f));
        for(int j=0;j<4;++j)box(s,V(side*7.7f+(j%2-.5f)*.45f,y+.993f,z-.9f+(j/2-.5f)*.40f),V(.13f,.012f,.13f),METAL,V(.16f,.17f,.16f),false);
        table(s,side*4.4f,y,z,1.6f,1.0f);chair(s,side*4.4f,y,z+1.0f,accent);chair(s,side*4.4f,y,z-1.0f,accent,-1);
    }else if(type==2 || type==6){
        table(s,side*6.9f,y,z,1.25f,2.1f);chair(s,side*5.8f,y,z,accent);
        box(s,V(side*6.9f,y+1.12f,z),V(.04f,.3f,.47f),METAL,V(.09f,.1f,.11f));
        box(s,V(side*6.84f,y+1.12f,z),V(.015f,.26f,.42f),GLASS,V(.18f,.30f,.32f),false);
        box(s,V(side*7.8f,y+1.1f,z+1.9f),V(.50f,1.1f,.27f),WOOD,V(.4f,.24f,.12f));
        for(int row=0;row<4;++row){box(s,V(side*7.8f,y+.25f+row*.5f,z+1.61f),V(.47f,.025f,.04f),WOOD,V(.65f,.43f,.23f));
            for(int j=0;j<5;++j)box(s,V(side*7.8f+(j-2)*.15f,y+.42f+row*.5f,z+1.72f),V(.055f,.15f,.13f),FABRIC,V(.2f+randf(key+j+row*10)*.45f,.24f,.18f),false);}
    }else if(type==3){
        table(s,x,y,z,2.2f,1.2f);for(int j=-1;j<=1;j+=2){chair(s,x+j*.65f,y,z+1,accent);chair(s,x+j*.65f,y,z-1,accent,-1);}
        box(s,V(x,y+.86f,z),V(.25f,.055f,.25f),CONCRETE,V(.64f,.57f,.44f),false);
    }else if(type==4 || type==5){
        // Bedroom or guest room. Keep corridor-side approach clear.
        box(s,V(side*6.1f,y+.24f,z),V(1.15f,.2f,1.12f),WOOD,V(.28f,.17f,.1f));
        box(s,V(side*6.1f,y+.51f,z),V(1.14f,.16f,1.10f),FABRIC,V(.86f,.81f,.69f));
        box(s,V(side*7.18f,y+.86f,z),V(.10f,.58f,1.16f),FABRIC,accent);
        box(s,V(side*5.7f,y+.69f,z),V(.64f,.035f,1.08f),FABRIC,accent);
        for(int j=-1;j<=1;j+=2){box(s,V(side*6.8f,y+.73f,z+j*.52f),V(.28f,.12f,.42f),FABRIC,V(.93f,.89f,.80f));
            box(s,V(side*7.0f,y+.37f,z+j*1.65f),V(.40f,.36f,.35f),WOOD,V(.46f,.28f,.14f));
            box(s,V(side*7.0f,y+.85f,z+j*1.65f),V(.12f,.12f,.12f),LIGHT,V(1,.70f,.38f),false);}
    }
}

__device__ void sideWindow(Scene* s,float x,float y,float z){
    box(s,V(x,y+1.8f,z),V(.025f,.80f,1.05f),GLASS,V(.79f,.86f,.88f));
    for(int j=-1;j<=1;j+=2){box(s,V(x,y+1.8f+j*.84f,z),V(.14f,.055f,1.14f),METAL,V(.16f,.18f,.18f));
        box(s,V(x,y+1.8f,z+j*1.10f),V(.14f,.88f,.045f),METAL,V(.16f,.18f,.18f));}
    box(s,V(x,y+1.8f,z),V(.13f,.84f,.028f),METAL,V(.16f,.18f,.18f));
    box(s,V(x,y+.92f,z),V(.3f,.06f,1.18f),CONCRETE,V(.65f,.64f,.57f));
}
__global__ void generateScene(Scene* s,U seed){
    if(threadIdx.x||blockIdx.x)return;s->count=0;s->overflow=0;s->seed=seed;
    V plaster(.78f,.75f,.66f),brick(.40f,.20f,.115f),floorWood(.52f,.32f,.17f),dark(.13f,.16f,.15f);
    box(s,V(0,-.2f,0),V(80,.2f,80),ASPHALT,V(.26f,.28f,.25f));
    box(s,V(0,-.08f,-14),V(4,.08f,6),CONCRETE,V(.64f,.62f,.55f));
    for(int i=0;i<6;++i){plant(s,-5.5f,0,-19+i*1.4f,1.5f);plant(s,5.5f,0,-19+i*1.4f,1.5f);}
    for(int f=0;f<=3;++f){float y=f*3.2f;
        if(f==0||f==3)box(s,V(0,y-.12f,1.5f),V(9.2f,.12f,9.7f),f==0?WOOD:CONCRETE,f==0?floorWood:plaster);
        else {between(s,V(-9.2f,y-.20f,-8.2f),V(9.2f,y,5.5f),WOOD,floorWood);
            between(s,V(-9.2f,y-.20f,5.5f),V(-1.8f,y,11.2f),WOOD,floorWood);
            between(s,V(1.8f,y-.20f,5.5f),V(9.2f,y,11.2f),WOOD,floorWood);
            between(s,V(-1.8f,y-.20f,10.2f),V(1.8f,y,11.2f),WOOD,floorWood);}
        if(f==3)break;
        // Front facade has an open entrance below, a broad glazed bay above.
        box(s,V(-5.2f,y+1.6f,-8.1f),V(3.8f,1.6f,.16f),BRICK,brick);box(s,V(5.2f,y+1.6f,-8.1f),V(3.8f,1.6f,.16f),BRICK,brick);
        box(s,V(0,y+2.95f,-8.1f),V(1.4f,.25f,.16f),CONCRETE,plaster);
        if(f>0){box(s,V(0,y+.5f,-8.1f),V(1.4f,.5f,.16f),BRICK,brick);box(s,V(0,y+1.85f,-8.1f),V(1.38f,.85f,.025f),GLASS,V(.8f,.9f,.9f));}
        box(s,V(0,y+1.6f,11.1f),V(9.1f,1.6f,.15f),BRICK,brick);
        for(int side=-1;side<=1;side+=2){
            // Side facade uses actual apertures, with solid sills and lintels.
            box(s,V(side*9,y+.45f,1.5f),V(.16f,.45f,9.5f),BRICK,brick);
            box(s,V(side*9,y+2.95f,1.5f),V(.16f,.25f,9.5f),BRICK,brick);
            float last=-8;for(int j=0;j<3;++j){float z=j==0?-4.8f:(j==1?1.8f:8.1f);float start=z-1.12f;
                if(start>last)box(s,V(side*9,y+1.8f,(start+last)*.5f),V(.16f,.9f,(start-last)*.5f),BRICK,brick);
                sideWindow(s,side*9,y,z);last=z+1.12f;}
            box(s,V(side*9,y+1.8f,(last+11)*.5f),V(.16f,.9f,(11-last)*.5f),BRICK,brick);
            // Shared hallway wall: two real door openings per side.
            float start=-8;for(int r=0;r<2;++r){float z=r?1.8f:-4.8f;
                box(s,V(side*1.7f,y+1.5f,(start+z-.72f)*.5f),V(.11f,1.5f,(z-.72f-start)*.5f),PLASTER,plaster);
                box(s,V(side*1.7f,y+2.7f,z),V(.11f,.30f,.72f),PLASTER,plaster);
                for(int j=-1;j<=1;j+=2)box(s,V(side*1.7f,y+1.2f,z+j*.76f),V(.16f,1.2f,.045f),WOOD,V(.30f,.20f,.12f));
                box(s,V(side*1.7f,y+2.43f,z),V(.16f,.045f,.80f),WOOD,V(.30f,.20f,.12f));
                // Open door leaf sits alongside the room-side wall.
                box(s,V(side*2.39f,y+1.17f,z+.79f),V(.65f,1.17f,.04f),WOOD,V(.47f,.30f,.17f));
                box(s,V(side*2.93f,y+1.0f,z+.73f),V(.075f,.025f,.04f),METAL,dark,false);
                start=z+.72f;room(s,f,side,r);
            }
            box(s,V(side*1.7f,y+1.5f,(start+5.4f)*.5f),V(.11f,1.5f,(5.4f-start)*.5f),PLASTER,plaster);
            box(s,V(side*5.35f,y+1.5f,-1.5f),V(3.55f,1.5f,.10f),PLASTER,plaster);
            box(s,V(side*5.35f,y+1.5f,5.4f),V(3.55f,1.5f,.10f),PLASTER,plaster);
            // Skirting and ceiling trim, separated around door openings.
            for(int seg=0;seg<3;++seg){float a=seg==0?-8:(seg==1?-4.0f:2.6f),b=seg==0?-5.6f:(seg==1?1.0f:5.4f);
                box(s,V(side*1.55f,y+.075f,(a+b)*.5f),V(.035f,.075f,(b-a)*.5f),WOOD,V(.45f,.32f,.20f),false);}
            box(s,V(side*1.53f,y+2.97f,-1.3f),V(.09f,.065f,6.6f),PLASTER,V(.89f,.86f,.76f),false);
            plant(s,side*3.0f,y,9.5f,1.2f);
        }
        for(int j=0;j<4;++j){float z=-6+j*3.5f;box(s,V(0,y+2.96f,z),V(.45f,.028f,.05f),LIGHT,V(1,.83f,.57f),false);}
        if(f<2){
            // Two flights, ten 16cm risers each, with a broad intermediate landing.
            for(int i=0;i<10;++i){float height=(i+1)*.16f;
                box(s,V(-.94f,y+height*.5f,5.65f+i*.30f),V(.73f,height*.5f,.15f),CONCRETE,V(.60f,.58f,.51f));
                box(s,V(-.94f,y+height+.009f,5.65f+i*.30f),V(.73f,.009f,.15f),WOOD,V(.43f,.28f,.16f));
                float upper=1.6f+height;
                box(s,V(.94f,y+upper*.5f,8.35f-i*.30f),V(.73f,upper*.5f,.15f),CONCRETE,V(.60f,.58f,.51f));
                box(s,V(.94f,y+upper+.009f,8.35f-i*.30f),V(.73f,.009f,.15f),WOOD,V(.43f,.28f,.16f));
                for(int side=-1;side<=1;side+=2){float xx=side*1.73f,top=side<0?height:upper;
                    box(s,V(xx,y+top+.5f,side<0?5.65f+i*.30f:8.35f-i*.30f),V(.025f,.50f,.025f),METAL,dark);
                    box(s,V(xx,y+top+1.01f,side<0?5.65f+i*.30f:8.35f-i*.30f),V(.045f,.04f,.18f),WOOD,V(.34f,.21f,.10f));}
            }
            box(s,V(0,y+1.5f,9.35f),V(1.78f,.10f,.85f),CONCRETE,V(.59f,.57f,.5f));
            box(s,V(0,y+1.61f,9.35f),V(1.78f,.01f,.85f),WOOD,V(.43f,.28f,.16f));
            box(s,V(0,y+2.12f,10.18f),V(1.8f,.50f,.035f),GLASS,V(.83f,.90f,.89f));
        }
    }
    // Entrance portal, canopy, facade bands and planted setbacks.
    for(int side=-1;side<=1;side+=2){box(s,V(side*1.48f,1.4f,-8.4f),V(.12f,1.4f,.33f),CONCRETE,V(.68f,.64f,.55f));
        box(s,V(side*2.2f,1.85f,-8.29f),V(.065f,.22f,.055f),LIGHT,V(1,.7f,.35f),false);}
    box(s,V(0,2.84f,-8.7f),V(2.1f,.10f,.90f),CONCRETE,V(.65f,.62f,.54f));
    for(int f=1;f<=3;++f){box(s,V(0,f*3.2f,-8.27f),V(9.3f,.10f,.12f),CONCRETE,V(.59f,.57f,.49f));
        for(int side=-1;side<=1;side+=2)box(s,V(side*9.2f,f*3.2f,1.5f),V(.10f,.10f,9.7f),CONCRETE,V(.59f,.57f,.49f));}
}

HD U spread(U x){x&=1023;x=(x|(x<<16))&0x030000ff;x=(x|(x<<8))&0x0300f00f;x=(x|(x<<4))&0x030c30c3;x=(x|(x<<2))&0x09249249;return x;}
__global__ void morton(Scene* s,U* keys,int* indices){int i=blockIdx.x*blockDim.x+threadIdx.x;if(i>=CAP)return;indices[i]=i;
    if(i>=s->count){keys[i]=0xffffffff;return;}V p=(s->objects[i].lo+s->objects[i].hi)*.5f;
    U x=static_cast<U>(clamp((p.x+20)/40)*1023),y=static_cast<U>(clamp((p.y+1)/12)*1023),z=static_cast<U>(clamp((p.z+25)/45)*1023);
    keys[i]=spread(x)|(spread(y)<<1)|(spread(z)<<2);}
__global__ void leaves(Scene* s,const int* order,Node* nodes){int i=blockIdx.x*blockDim.x+threadIdx.x;if(i>=CAP)return;int j=order[i];Node n;
    if(j<s->count){n.lo=s->objects[j].lo;n.hi=s->objects[j].hi;n.shape=j;}else{n.lo=V(1e20f,1e20f,1e20f);n.hi=V(-1e20f,-1e20f,-1e20f);n.shape=-1;}nodes[CAP+i]=n;}
__global__ void parents(Node* nodes,int start,int count){int i=blockIdx.x*blockDim.x+threadIdx.x;if(i>=count)return;int j=start+i;Node a=nodes[j*2],b=nodes[j*2+1];nodes[j]={vmin(a.lo,b.lo),vmax(a.hi,b.hi),-1};}

__device__ float bound(V ro,V inv,V lo,V hi,float maxT){V a=(lo-ro)*inv,b=(hi-ro)*inv;V mn=vmin(a,b),mx=vmax(a,b);float near=fmaxf(mn.x,fmaxf(mn.y,mn.z)),far=fminf(mx.x,fminf(mx.y,mx.z));return far>=fmaxf(near,.001f)&&near<maxT?fmaxf(near,.001f):1e30f;}
struct Hit{float t;int id;V n;};
__device__ Hit trace(const Scene* s,const Node* nodes,V ro,V rd,float maxT=1000,bool shadow=false){
    V inv(1/(fabsf(rd.x)<1e-8f?1e-8f:rd.x),1/(fabsf(rd.y)<1e-8f?1e-8f:rd.y),1/(fabsf(rd.z)<1e-8f?1e-8f:rd.z));
    int stack[32],top=0;stack[top++]=1;Hit hit{maxT,-1,V()};
    while(top){int i=stack[--top];Node n=nodes[i];if(bound(ro,inv,n.lo,n.hi,hit.t)>=hit.t)continue;
        if(i>=CAP){if(n.shape<0)continue;Shape o=s->objects[n.shape];if(shadow&&(o.mat==GLASS||o.mat==LIGHT))continue;
            V a=(o.lo-ro)*inv,b=(o.hi-ro)*inv,mn=vmin(a,b),mx=vmax(a,b);
            float near=fmaxf(mn.x,fmaxf(mn.y,mn.z)),far=fminf(mx.x,fminf(mx.y,mx.z));float t=near>.001f?near:far;
            if(t>.001f&&t<hit.t){hit.t=t;hit.id=n.shape;V p=ro+rd*t,c=(o.lo+o.hi)*.5f,h=(o.hi-o.lo)*.5f;
                V v((p.x-c.x)/fmaxf(.00001f,h.x),(p.y-c.y)/fmaxf(.00001f,h.y),(p.z-c.z)/fmaxf(.00001f,h.z));
                if(fabsf(v.x)>fabsf(v.y)&&fabsf(v.x)>fabsf(v.z))hit.n=V(v.x>0?1.f:-1.f,0,0);else if(fabsf(v.y)>fabsf(v.z))hit.n=V(0,v.y>0?1.f:-1.f,0);else hit.n=V(0,0,v.z>0?1.f:-1.f);
                if(shadow)return hit;}
        }else{float a=bound(ro,inv,nodes[i*2].lo,nodes[i*2].hi,hit.t),b=bound(ro,inv,nodes[i*2+1].lo,nodes[i*2+1].hi,hit.t);
            if(a<b){if(b<hit.t)stack[top++]=i*2+1;if(a<hit.t)stack[top++]=i*2;}else{if(a<hit.t)stack[top++]=i*2;if(b<hit.t)stack[top++]=i*2+1;}}
    }return hit;
}

__device__ V material(Shape o,V p,V n,float footprint){
    V c=o.color;float u=fabsf(n.x)>.5f?p.z:p.x,v=fabsf(n.y)>.5f?p.z:p.y;
    float noise=randf(static_cast<U>(floorf(p.x*180))*73856093u^static_cast<U>(floorf(p.y*180))*19349663u^static_cast<U>(floorf(p.z*180))*83492791u);
    float micro=clamp(1-footprint*80);c=c*(1+(noise-.5f)*.06f*micro);
    if(o.mat==BRICK){float row=floorf(v/.085f);float bx=fract(u/.29f+static_cast<int>(row)%2*.5f),by=fract(v/.085f);
        float mortar=clamp(fminf(fminf(bx,1-bx)*.29f,fminf(by,1-by)*.085f)/fmaxf(.003f,footprint));
        float r=randf(static_cast<U>(floorf(u/.29f+static_cast<int>(row)%2*.5f))*1231u^static_cast<U>(row)*919u);
        c=lerp(V(.47f,.43f,.35f),c*(.75f+r*.45f),mortar);}
    if(o.mat==WOOD){float strip=floorf(p.x/.19f),seam=fminf(fract(p.x/.19f),1-fract(p.x/.19f));
        float grain=sinf(p.x*180+sinf(p.z*2.2f)*2+sinf(p.z*11)*.4f)*.04f;
        c=c*(.87f+randf(static_cast<U>(strip)^o.id)*.19f+grain*micro);if(n.y>.5f&&seam<.013f&&footprint<.02f)c=c*.7f;}
    if(o.mat==TILE){float fu=fract(u/.45f),fv=fract(v/.45f);if(fminf(fminf(fu,1-fu),fminf(fv,1-fv))<.012f)c=c*.62f;}
    if(o.mat==FABRIC)c=c*(1+.035f*sinf(u*420)*sinf(v*420)*micro);
    if(o.mat==CONCRETE||o.mat==PLASTER)c=c*(.98f+.04f*noise*micro);
    if(o.mat==ASPHALT){float d=fminf(fabsf(p.x),fabsf(p.z+14));c=c*(.92f+.12f*noise);if(fabsf(p.x)>12||p.z>15)c=V(.22f,.27f,.14f)*(.9f+noise*.2f);}
    return c;
}
__device__ V sky(V rd){float t=clamp(rd.y*.7f+.35f);V c=lerp(V(.76f,.79f,.76f),V(.28f,.48f,.68f),t);float sun=powf(fmaxf(0,dot(rd,norm(V(-.7f,1,-.5f)))),900);return c+V(6,4.8f,3.1f)*sun;}
__device__ V shade(const Scene* s,const Node* nodes,V ro,V rd,Hit h,U rng,float pixelScale,bool detailed){
    if(h.id<0)return sky(rd);Shape o=s->objects[h.id];V p=ro+rd*h.t,n=h.n,c=material(o,p,n,h.t*pixelScale);
    if(o.mat==LIGHT)return o.color*3;
    bool indoors=fabsf(p.x)<9.15f&&p.z>-8.25f&&p.z<11.2f&&p.y<9.5f;
    float ambient=indoors?.20f:.40f;V illumination(ambient*.9f,ambient*.95f,ambient);
    V sun=norm(V(-.7f,1,-.5f));float nd=clamp(dot(n,sun));
    if(nd>0){V jitter=V(randf(rng)-.5f,randf(rng+1)-.5f,randf(rng+2)-.5f)*.025f;V l=norm(sun+jitter);Hit sh=trace(s,nodes,p+n*.003f,l,80,true);if(sh.id<0)illumination=illumination+V(2.4f,2.05f,1.55f)*nd;}
    if(indoors){
        float floor=floorf((p.y+.05f)/3.2f);floor=clamp(floor,0,2);
        V lamp;if(fabsf(p.x)<1.85f)lamp=V(0,floor*3.2f+2.85f,roundf((p.z+6)/3.5f)*3.5f-6);else lamp=V(p.x<0?-5.2f:5.2f,floor*3.2f+2.9f,p.z< -1.5f?-4.8f:1.8f);
        if(p.z>5.4f)lamp=V(0,floor*3.2f+3.0f,8.8f);
        V delta=lamp-p;float dist=sqrtf(dot(delta,delta));V l=delta/fmaxf(.01f,dist);float cosine=clamp(dot(n,l));
        if(cosine>0){Hit sh=trace(s,nodes,p+n*.005f,l,dist-.08f,true);if(sh.id<0)illumination=illumination+V(1.0f,.81f,.59f)*(cosine*5.5f/(1+dist*dist*.55f));}
        // Broad diffuse fill from the nearest real window.
        V window(p.x<0?-8.9f:8.9f,floor*3.2f+1.85f,p.z< -1.5f?-4.8f:1.8f);V wl=norm(window-p);
        float facing=clamp(dot(n,wl));illumination=illumination+V(.43f,.51f,.59f)*(facing/(1+fabsf(window.x-p.x)*.12f));
    }
    if(detailed){V random=norm(V(randf(rng+3)*2-1,randf(rng+4)*2-1,randf(rng+5)*2-1));V ao=norm(n+random);if(dot(ao,n)<.01f)ao=n;
        Hit occ=trace(s,nodes,p+n*.004f,ao,1.1f,true);if(occ.id>=0)illumination=illumination*(.6f+.4f*clamp(occ.t/1.1f));}
    return c*illumination;
}
__global__ void render(const Scene* s,const Node* nodes,const Camera* camera,U* pixels,V* history,int w,int h,int sample,int quality){
    int i=blockIdx.x*blockDim.x+threadIdx.x;if(i>=w*h)return;int x=i%w,y=i/w;Camera cam=*camera;U rng=mix(i^sample*747796405u);
    V f(sinf(cam.yaw)*cosf(cam.pitch),sinf(cam.pitch),cosf(cam.yaw)*cosf(cam.pitch)),right(cosf(cam.yaw),0,-sinf(cam.yaw)),up=cross(f,right);
    float jx=sample?randf(rng)-.5f:0,jy=sample?randf(rng+7)-.5f:0;
    float sx=(2*(x+.5f+jx)/w-1)*(float(w)/h)*.68f,sy=(1-2*(y+.5f+jy)/h)*.68f;
    V ro=cam.foot+V(0,1.65f,0),rd=norm(f+right*sx+up*sy);Hit hit=trace(s,nodes,ro,rd);V color;
    if(hit.id>=0&&s->objects[hit.id].mat==GLASS){
        V p=ro+rd*hit.t;Hit through=trace(s,nodes,p+rd*.06f,rd);color=shade(s,nodes,p+rd*.06f,rd,through,rng,1.f/h,quality>0);
        V reflected=rd-hit.n*(2*dot(rd,hit.n));float fresnel=.035f+.65f*powf(1-fabsf(dot(rd,hit.n)),5);
        color=lerp(color*V(.94f,.98f,.98f),sky(reflected),fresnel);
    }else color=shade(s,nodes,ro,rd,hit,rng,1.f/h,quality>0);
    if(sample>0)color=lerp(history[i],color,1.f/(sample+1));history[i]=color;
    color=color*1.35f;
    // ACES-style filmic curve with display gamma.
    float vals[3]={color.x,color.y,color.z};U bytes[3];for(int k=0;k<3;++k){float v=vals[k];v=clamp((v*(2.51f*v+.03f))/(v*(2.43f*v+.59f)+.14f));bytes[k]=static_cast<U>(powf(v,1/2.2f)*255+.5f);}
    pixels[i]=0xff000000u|(bytes[0]<<16)|(bytes[1]<<8)|bytes[2];
}

// Player is an upright body volume. Fixed 120Hz integration, gravity, swept
// axis motion, bounded stair stepping. Only authoritative solid shapes collide.
__device__ bool overlap(float lo,float hi,float a,float b){return lo<b-.001f&&hi>a+.001f;}
__device__ bool freeBody(const Scene* s,V foot){for(int i=0;i<s->count;++i){Shape o=s->objects[i];if(!o.solid)continue;if(overlap(foot.x-.26f,foot.x+.26f,o.lo.x,o.hi.x)&&overlap(foot.y+.015f,foot.y+1.78f,o.lo.y,o.hi.y)&&overlap(foot.z-.26f,foot.z+.26f,o.lo.z,o.hi.z))return false;}return true;}
__device__ void horizontal(const Scene* s,Camera& c,float delta,int axis){
    if(fabsf(delta)<1e-8f)return;V target=c.foot;if(axis==0)target.x+=delta;else target.z+=delta;
    float stepTop=c.foot.y;bool obstacle=false;
    for(int i=0;i<s->count;++i){Shape o=s->objects[i];if(!o.solid)continue;
        if(overlap(target.x-.26f,target.x+.26f,o.lo.x,o.hi.x)&&overlap(target.z-.26f,target.z+.26f,o.lo.z,o.hi.z)&&overlap(target.y+.015f,target.y+1.78f,o.lo.y,o.hi.y)){
            obstacle=true;stepTop=fmaxf(stepTop,o.hi.y);}}
    if(!obstacle){c.foot=target;return;}
    if(c.grounded&&stepTop-c.foot.y<=.23f){V stepped=target;stepped.y=stepTop+.002f;if(freeBody(s,stepped)){c.foot=stepped;c.vy=0;return;}}
    for(int i=0;i<s->count;++i){Shape o=s->objects[i];if(!o.solid)continue;
        if(!overlap(c.foot.y+.015f,c.foot.y+1.78f,o.lo.y,o.hi.y))continue;
        float old=axis==0?c.foot.x:c.foot.z,other=axis==0?c.foot.z:c.foot.x;
        float alo=axis==0?o.lo.x:o.lo.z,ahi=axis==0?o.hi.x:o.hi.z,blo=axis==0?o.lo.z:o.lo.x,bhi=axis==0?o.hi.z:o.hi.x;
        if(!overlap(other-.26f,other+.26f,blo,bhi))continue;
        float next=axis==0?target.x:target.z;
        if(delta>0&&old+.26f<=alo+.003f&&next+.26f>alo)next=fminf(next,alo-.261f);
        if(delta<0&&old-.26f>=ahi-.003f&&next-.26f<ahi)next=fmaxf(next,ahi+.261f);
        if(axis==0)target.x=next;else target.z=next;
    }
    if(freeBody(s,target))c.foot=target;
}
__global__ void simulate(const Scene* s,Camera* cam,Input input,int steps){if(threadIdx.x||blockIdx.x)return;Camera c=*cam;
    c.yaw+=input.dx*.0022f;c.pitch=clamp(c.pitch-input.dy*.0022f,-1.45f,1.45f);
    for(int t=0;t<steps;++t){constexpr float dt=1.f/120;
        if(t==0&&input.jump&&c.grounded){c.vy=4.5f;c.grounded=0;}
        V d=V(sinf(c.yaw),0,cosf(c.yaw))*input.forward+V(cosf(c.yaw),0,-sinf(c.yaw))*input.side;
        if(dot(d,d)>0)d=norm(d)*(input.sprint?4.1f:2.5f)*dt;
        V before=c.foot;horizontal(s,c,d.x,0);horizontal(s,c,d.z,2);
        c.vy=fmaxf(-25,c.vy-9.81f*dt);float next=c.foot.y+c.vy*dt;c.grounded=0;
        for(int i=0;i<s->count;++i){Shape o=s->objects[i];if(!o.solid||!overlap(c.foot.x-.26f,c.foot.x+.26f,o.lo.x,o.hi.x)||!overlap(c.foot.z-.26f,c.foot.z+.26f,o.lo.z,o.hi.z))continue;
            if(c.vy<=0&&c.foot.y>=o.hi.y-.022f&&next<=o.hi.y){next=fmaxf(next,o.hi.y);c.grounded=1;}
            if(c.vy>0&&c.foot.y+1.78f<=o.lo.y+.002f&&next+1.78f>=o.lo.y)next=fminf(next,o.lo.y-1.781f);
        }
        if(c.grounded||fabsf(next-c.foot.y-c.vy*dt)>.0001f)c.vy=0;c.foot.y=next;c.distance+=sqrtf(dot(c.foot-before,c.foot-before));
    }*cam=c;
}

struct Engine{
    Scene* scene=nullptr;Node* nodes=nullptr;U* keys=nullptr;int* order=nullptr;Camera* camera=nullptr;U* pixels=nullptr;V* history=nullptr;U* host=nullptr;int w=0,h=0,count=0;U seed=240921;
    Engine(){CU(cudaMalloc(&scene,sizeof(Scene)));CU(cudaMalloc(&nodes,2*CAP*sizeof(Node)));CU(cudaMalloc(&keys,CAP*sizeof(U)));CU(cudaMalloc(&order,CAP*sizeof(int)));CU(cudaMalloc(&camera,sizeof(Camera)));build(seed);reset();}
    ~Engine(){cudaFree(scene);cudaFree(nodes);cudaFree(keys);cudaFree(order);cudaFree(camera);cudaFree(pixels);cudaFree(history);cudaFreeHost(host);}
    void build(U value){seed=value;generateScene<<<1,1>>>(scene,seed);CU(cudaGetLastError());Scene check;CU(cudaMemcpy(&check,scene,sizeof(Scene),cudaMemcpyDeviceToHost));if(check.overflow)throw std::runtime_error("Scene capacity exceeded");count=check.count;
        morton<<<CAP/256,256>>>(scene,keys,order);CU(cudaGetLastError());thrust::sort_by_key(thrust::device_pointer_cast(keys),thrust::device_pointer_cast(keys+CAP),thrust::device_pointer_cast(order));leaves<<<CAP/256,256>>>(scene,order,nodes);CU(cudaGetLastError());
        for(int start=CAP/2;start;start/=2){parents<<<(start+255)/256,256>>>(nodes,start,start);CU(cudaGetLastError());}CU(cudaDeviceSynchronize());}
    void set(Camera c){CU(cudaMemcpy(camera,&c,sizeof(c),cudaMemcpyHostToDevice));}
    Camera get(){Camera c;CU(cudaMemcpy(&c,camera,sizeof(c),cudaMemcpyDeviceToHost));return c;}
    void reset(){set({V(0,.01f,-15),0,0,0,0,0});}
    void resize(int width,int height){if(w==width&&h==height)return;CU(cudaDeviceSynchronize());cudaFree(pixels);cudaFree(history);cudaFreeHost(host);pixels=nullptr;history=nullptr;host=nullptr;w=width;h=height;CU(cudaMalloc(&pixels,size_t(w)*h*sizeof(U)));CU(cudaMalloc(&history,size_t(w)*h*sizeof(V)));CU(cudaMallocHost(&host,size_t(w)*h*sizeof(U)));}
    void frame(int sample,int quality=1){render<<<(w*h+127)/128,128>>>(scene,nodes,camera,pixels,history,w,h,sample,quality);CU(cudaGetLastError());CU(cudaMemcpy(host,pixels,size_t(w)*h*sizeof(U),cudaMemcpyDeviceToHost));}
    void move(Input in,int ticks){simulate<<<1,1>>>(scene,camera,in,ticks);CU(cudaGetLastError());}
    void bmp(const std::string& file){BITMAPFILEHEADER fh{};BITMAPINFOHEADER ih{};ih.biSize=sizeof(ih);ih.biWidth=w;ih.biHeight=-h;ih.biPlanes=1;ih.biBitCount=32;ih.biCompression=BI_RGB;fh.bfType=0x4d42;fh.bfOffBits=sizeof(fh)+sizeof(ih);fh.bfSize=fh.bfOffBits+w*h*4;
        std::ofstream out(file,std::ios::binary);out.write(reinterpret_cast<char*>(&fh),sizeof(fh));out.write(reinterpret_cast<char*>(&ih),sizeof(ih));out.write(reinterpret_cast<char*>(host),size_t(w)*h*4);if(!out)throw std::runtime_error("Cannot save capture "+file);}
};

void walkTo(Engine& e,float x,float z,int maxTicks=1800){for(int t=0;t<maxTicks;++t){Camera c=e.get();V delta=V(x,0,z)-V(c.foot.x,0,c.foot.z);if(dot(delta,delta)<.008f)return;c.yaw=atan2f(delta.x,delta.z);e.set(c);e.move({1,0,0,0,0,0},1);}Camera c=e.get();throw std::runtime_error("Route blocked toward "+std::to_string(x)+","+std::to_string(z)+" at "+std::to_string(c.foot.x)+","+std::to_string(c.foot.y)+","+std::to_string(c.foot.z));}
void selfTest(Engine& e){
    Scene a,b;CU(cudaMemcpy(&a,e.scene,sizeof(a),cudaMemcpyDeviceToHost));e.build(e.seed);CU(cudaMemcpy(&b,e.scene,sizeof(b),cudaMemcpyDeviceToHost));if(a.count!=b.count||memcmp(a.objects,b.objects,a.count*sizeof(Shape)))throw std::runtime_error("Seed regeneration mismatch");
    e.reset();e.move({},120);Camera c=e.get();if(fabsf(c.foot.y)>.03f)throw std::runtime_error("Grounding failed");
    walkTo(e,0,-4.8f);walkTo(e,-3.5f,-4.8f);walkTo(e,0,-4.8f);walkTo(e,3.5f,-4.8f);walkTo(e,0,-4.8f);
    for(int f=0;f<2;++f){walkTo(e,0,5.0f);walkTo(e,-.94f,5.0f);walkTo(e,-.94f,9.2f);walkTo(e,.94f,9.2f);walkTo(e,.94f,5.1f);c=e.get();if(fabsf(c.foot.y-(f+1)*3.2f)>.1f)throw std::runtime_error("Stair height failed");
        walkTo(e,0,1.8f);walkTo(e,-3.5f,1.8f);walkTo(e,0,1.8f);walkTo(e,3.5f,1.8f);walkTo(e,0,1.8f);}
    // Walk back down the same continuous route.
    for(int f=2;f>0;--f){walkTo(e,.94f,5.1f);walkTo(e,.94f,9.2f);walkTo(e,-.94f,9.2f);walkTo(e,-.94f,5.0f);walkTo(e,0,4.7f);e.move({},60);c=e.get();if(fabsf(c.foot.y-(f-1)*3.2f)>.1f)throw std::runtime_error("Stair descent failed");}
    walkTo(e,0,-12);c=e.get();float y=c.foot.y;e.move({0,0,0,0,0,1},15);if(e.get().foot.y<=y+.1f)throw std::runtime_error("Jump failed");e.move({},180);if(fabsf(e.get().foot.y-y)>.03f)throw std::runtime_error("Landing failed");
    // Deliberately walk into solid facade.
    e.set({V(4,0,-10),0,0,0,1,0});e.move({1,0,0,0,1,0},240);if(e.get().foot.z>-8.45f)throw std::runtime_error("Facade penetration");
    e.resize(320,180);e.frame(0);unsigned long long sum=0;for(int i=0;i<320*180;++i)sum+=e.host[i]&0xffffff;if(!sum)throw std::runtime_error("Black render");
    std::cout<<"PASS: seeded regeneration, entry, rooms, all floors, ascent/descent, gravity, jump, facade collision, GPU render. Shapes: "<<e.count<<"\n";e.reset();
}

HWND windowHandle=nullptr;bool running=true,captured=false,hud=true;bool requestReset=false,requestSeed=false,requestCapture=false,requestQuality=false,requestResolution=false;int wheel=0;
void captureMouse(bool enabled){captured=enabled;if(enabled){SetCapture(windowHandle);while(ShowCursor(FALSE)>=0){}RECT r;GetClientRect(windowHandle,&r);POINT a{r.left,r.top},b{r.right,r.bottom};ClientToScreen(windowHandle,&a);ClientToScreen(windowHandle,&b);RECT clip{a.x,a.y,b.x,b.y};ClipCursor(&clip);SetCursorPos((a.x+b.x)/2,(a.y+b.y)/2);}else{ReleaseCapture();ClipCursor(nullptr);while(ShowCursor(TRUE)<0){}}}
LRESULT CALLBACK proc(HWND hwnd,UINT msg,WPARAM wp,LPARAM lp){switch(msg){case WM_DESTROY:running=false;PostQuitMessage(0);return 0;case WM_KILLFOCUS:if(captured)captureMouse(false);return 0;case WM_LBUTTONDOWN:if(!captured)captureMouse(true);return 0;
    case WM_KEYDOWN:if(lp&(1ll<<30))break;switch(wp){case VK_ESCAPE:if(captured)captureMouse(false);else running=false;break;case 'R':requestReset=true;break;case 'N':requestSeed=true;break;case 'H':hud=!hud;break;case VK_F2:requestResolution=true;break;case VK_F3:requestQuality=true;break;case VK_F12:requestCapture=true;break;}return 0;case WM_ERASEBKGND:return 1;}return DefWindowProc(hwnd,msg,wp,lp);}
void ui(Engine& e){HINSTANCE instance=GetModuleHandle(nullptr);WNDCLASSW wc{};wc.lpfnWndProc=proc;wc.hInstance=instance;wc.lpszClassName=L"SeededBuildingCUDA";wc.hCursor=LoadCursor(nullptr,IDC_ARROW);RegisterClassW(&wc);
    int sw=GetSystemMetrics(SM_CXSCREEN),sh=GetSystemMetrics(SM_CYSCREEN);int cw=std::min(1600,sw-80),ch=std::min(960,sh-100);
    windowHandle=CreateWindowExW(0,wc.lpszClassName,L"Realistic City | A building from a seed | Native CUDA",WS_OVERLAPPEDWINDOW,CW_USEDEFAULT,CW_USEDEFAULT,cw,ch,nullptr,nullptr,instance,nullptr);if(!windowHandle)throw std::runtime_error("Window creation failed");ShowWindow(windowHandle,SW_SHOW);UpdateWindow(windowHandle);
    HFONT font=CreateFontW(-17,0,0,0,FW_NORMAL,FALSE,FALSE,FALSE,DEFAULT_CHARSET,OUT_DEFAULT_PRECIS,CLIP_DEFAULT_PRECIS,CLEARTYPE_QUALITY,DEFAULT_PITCH,L"Segoe UI");
    auto prev=std::chrono::steady_clock::now();double accumulator=0;float fps=0;int sample=0,resolution=1,quality=1;bool lastJump=false;
    e.resize(1920,1080);while(running){MSG m;while(PeekMessage(&m,nullptr,0,0,PM_REMOVE)){TranslateMessage(&m);DispatchMessage(&m);}if(!running)break;
        if(IsIconic(windowHandle)){Sleep(40);prev=std::chrono::steady_clock::now();continue;}
        auto now=std::chrono::steady_clock::now();double dt=std::chrono::duration<double>(now-prev).count();prev=now;dt=std::min(.10,dt);accumulator+=dt;int ticks=std::min(12,static_cast<int>(accumulator*120));accumulator-=ticks/120.;
        RECT rect;GetClientRect(windowHandle,&rect);if(rect.right<=0||rect.bottom<=0)continue;
        if(requestReset){e.reset();sample=0;requestReset=false;}if(requestSeed){e.build(mix(e.seed+1));e.reset();sample=0;requestSeed=false;}
        if(requestResolution){resolution=(resolution+1)%3;sample=0;requestResolution=false;}if(requestQuality){quality=1-quality;sample=0;requestQuality=false;}
        int width=resolution==0?1280:(resolution==1?1920:2560),height=std::max(1,static_cast<int>(width*float(rect.bottom)/rect.right));if(e.w!=width||e.h!=height){e.resize(width,height);sample=0;}
        Input input{};if(captured){auto down=[](int key){return (GetAsyncKeyState(key)&0x8000)!=0;};input.forward=float(down('W')||down(VK_UP))-float(down('S')||down(VK_DOWN));input.side=float(down('D')||down(VK_RIGHT))-float(down('A')||down(VK_LEFT));input.sprint=down(VK_SHIFT);bool jump=down(VK_SPACE);input.jump=jump&&!lastJump;lastJump=jump;
            POINT center{rect.right/2,rect.bottom/2},mouse;ClientToScreen(windowHandle,&center);GetCursorPos(&mouse);input.dx=float(mouse.x-center.x);input.dy=float(mouse.y-center.y);SetCursorPos(center.x,center.y);}
        Camera before=e.get();e.move(input,ticks);Camera after=e.get();if(dot(after.foot-before.foot,after.foot-before.foot)>.0000001f||input.dx||input.dy)sample=0;
        e.frame(sample,quality);sample=std::min(sample+1,63);HDC dc=GetDC(windowHandle);BITMAPINFO info{};info.bmiHeader.biSize=sizeof(BITMAPINFOHEADER);info.bmiHeader.biWidth=e.w;info.bmiHeader.biHeight=-e.h;info.bmiHeader.biPlanes=1;info.bmiHeader.biBitCount=32;info.bmiHeader.biCompression=BI_RGB;
        StretchDIBits(dc,0,0,rect.right,rect.bottom,0,0,e.w,e.h,e.host,&info,DIB_RGB_COLORS,SRCCOPY);
        fps=fps*.92f+float(1/std::max(.001,dt))*.08f;if(hud){SetBkMode(dc,TRANSPARENT);SelectObject(dc,font);SetTextColor(dc,RGB(245,239,223));
            HBRUSH brush=CreateSolidBrush(RGB(23,29,28));RECT bg{18,18,660,104};FillRect(dc,&bg,brush);DeleteObject(brush);
            std::wstring title=L"STRATUM / ONE BUILDING    Seed "+std::to_wstring(e.seed)+L"    Floor "+std::to_wstring(std::min(3,1+int((after.foot.y+.05f)/3.2f)));
            TextOutW(dc,32,28,title.c_str(),static_cast<int>(title.size()));std::wstring controls=captured?L"WASD walk  |  Mouse look  |  Shift run  |  Space jump  |  Esc release":L"Click to walk inside  |  WASD + mouse  |  Esc releases the pointer";TextOutW(dc,32,53,controls.c_str(),static_cast<int>(controls.size()));
            std::wstring bottom=L"F2 resolution  F3 lighting  N new seed  R entrance  H hide  F12 capture     "+std::to_wstring(int(fps))+L" fps";TextOutW(dc,32,78,bottom.c_str(),static_cast<int>(bottom.size()));}
        if(captured){SetPixel(dc,rect.right/2,rect.bottom/2,RGB(240,230,210));}ReleaseDC(windowHandle,dc);
        if(requestCapture){e.bmp("building-capture.bmp");requestCapture=false;}
    }if(captured)captureMouse(false);DeleteObject(font);if(IsWindow(windowHandle))DestroyWindow(windowHandle);
}
int main(int argc,char** argv){try{Engine e;for(int i=1;i<argc;++i)if(std::string(argv[i])=="--seed"&&i+1<argc)e.build(static_cast<U>(std::stoul(argv[++i])));
    if(argc>1&&std::string(argv[1])=="--self-test"){selfTest(e);return 0;}
    if(argc>1&&std::string(argv[1])=="--capture"){std::string path=argc>2?argv[2]:"building.bmp",view=argc>3?argv[3]:"exterior";
        if(view=="exterior")e.set({V(15,3,-22),-.65f,.04f,0,0,0});
        if(view=="lobby")e.set({V(.2f,0,-7.0f),.08f,.02f,0,1,0});
        if(view=="room")e.set({V(-2.6f,0,-6.5f),-.87f,-.06f,0,1,0});
        if(view=="stairs")e.set({V(-.3f,0,3.8f),.03f,.18f,0,1,0});
        if(view=="upper")e.set({V(0,6.4f,4.7f),PI,-.03f,0,1,0});
        e.resize(1920,1080);auto start=std::chrono::steady_clock::now();for(int i=0;i<24;++i)e.frame(i);e.bmp(path);std::cout<<"Saved "<<path<<"; "<<e.count<<" shapes; 24 samples in "<<std::chrono::duration<double>(std::chrono::steady_clock::now()-start).count()<<" s\n";return 0;}
    ui(e);return 0;
}catch(const std::exception& ex){std::cerr<<ex.what()<<'\n';MessageBoxA(nullptr,ex.what(),"Building error",MB_OK|MB_ICONERROR);return 1;}}
