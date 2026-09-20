#define CAP 32768
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
struct Shape { float3 lo; float3 hi; float3 color; float3 origin; unsigned int id; int mat; int solid; };
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
__device__ unsigned int buildingKey(const float* s){return (unsigned int)s[3]|((unsigned int)s[4]<<16);}
__device__ float floorBase(const float* s,int floor){return s[10+floor];}
__device__ unsigned int roomKey(const float* s,int floor,int side,int back){return mix(buildingKey(s)^mix((unsigned int)floor*101u+(side<0?17u:29u)+(unsigned int)back*43u));}
__device__ float roomSplit(const float* s,int floor,int side){return -2.0f+randf(roomKey(s,floor,side,0)^713u)*1.5f;}
__device__ float roomZ(const float* s,int floor,int side,int back){float split=roomSplit(s,floor,side);return back?(split+5.4f)*.5f:(-8.0f+split)*.5f;}
__device__ int roomType(const float* s,int floor,int side,int back){unsigned int key=roomKey(s,floor,side,back);int use=(int)s[7];if(use==1){int v=(int)(mix(key^9821u)%4u);return v==0?1:(v==1?3:(v==2?2:0));}if(use==0&&floor>0)return 4+(int)(mix(key^9821u)%4u);return (int)(mix(key^9821u)%8u);}
__device__ Shape readShape(const float* s,int index){int b=32+index*16;Shape o;o.lo=make_float3(s[b],s[b+1],s[b+2]);o.hi=make_float3(s[b+3],s[b+4],s[b+5]);o.color=make_float3(s[b+6],s[b+7],s[b+8]);o.mat=(int)s[b+9];o.solid=(int)s[b+10];o.origin=make_float3(s[b+13],0,s[b+14]);o.id=(unsigned int)s[b+11]^((unsigned int)s[b+12]<<16);return o;}
__device__ void box(float* s,float3 p,float3 half,int mat,float3 color,bool solid=true){int i=(int)s[0];if(i>=CAP){s[2]=1.0f;return;}s[0]=(float)(i+1);p.x=p.x*s[5]+s[16];p.z=p.z*s[6]+s[17];half.x*=s[5];half.z*=s[6];int b=32+i*16;float3 lo=p-half,hi=p+half;s[b]=lo.x;s[b+1]=lo.y;s[b+2]=lo.z;s[b+3]=hi.x;s[b+4]=hi.y;s[b+5]=hi.z;s[b+6]=color.x;s[b+7]=color.y;s[b+8]=color.z;s[b+9]=(float)mat;s[b+10]=solid?1.0f:0.0f;s[b+11]=s[3];s[b+12]=s[4];s[b+13]=s[16];s[b+14]=s[17];s[b+15]=0;}
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
    box(s,make_float3(x,y+.45f,z),make_float3(.24f,.055f,.23f),FABRIC,col);
    box(s,make_float3(x,y+.77f,z+face*.20f),make_float3(.24f,.28f,.05f),FABRIC,col);
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
__device__ void room(float* s,int floor,int side,int back){
    float y=floorBase(s,floor),storey=floorBase(s,floor+1)-y,x=side*5.2f,z=roomZ(s,floor,side,back);unsigned int key=roomKey(s,floor,side,back);
    float3 accent=lerp(make_float3(.30f,.39f,.38f),make_float3(.52f,.29f,.17f),randf(key));
    int type=roomType(s,floor,side,back);
    // Common details, ceiling fixtures, rug, art, power outlets.
    box(s,make_float3(x,y+storey-.18f,z),make_float3(.68f,.035f,.035f),LIGHT,make_float3(1,.81f,.51f),false);
    box(s,make_float3(x,y+.012f,z),make_float3(1.55f,.009f,1.55f),FABRIC,lerp(accent,make_float3(.72f,.64f,.51f),.55f),false);
    art(s,side*8.67f,y+1.65f,z-2.05f,side,key);
    for(int j=0;j<2;++j)box(s,make_float3(side*1.84f,y+.35f,z+(j?1.5f:-1.6f)),make_float3(.025f,.06f,.09f),PLASTER,make_float3(.86f,.84f,.77f),false);
    plant(s,side*7.8f,y,z+1.7f,.9f);
    if(type==0 || type==7){
        // Sofa at the outer side, low table, lounge chair.
        box(s,make_float3(side*7.1f,y+.30f,z-.15f),make_float3(.62f,.23f,1.22f),FABRIC,accent);
        box(s,make_float3(side*7.55f,y+.76f,z-.15f),make_float3(.18f,.5f,1.22f),FABRIC,accent*.8f);
        for(int j=-1;j<=1;j+=2)box(s,make_float3(side*7.1f,y+.56f,z+j*1.1f-.15f),make_float3(.63f,.22f,.14f),FABRIC,accent*.8f);
        for(int j=0;j<3;++j)box(s,make_float3(side*6.95f,y+.58f,z-.85f+j*.7f),make_float3(.40f,.08f,.31f),FABRIC,accent*1.15f);
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
        box(s,make_float3(side*6.1f,y+.24f,z),make_float3(1.15f,.2f,1.12f),WOOD,make_float3(.28f,.17f,.1f));
        box(s,make_float3(side*6.1f,y+.51f,z),make_float3(1.14f,.16f,1.10f),FABRIC,make_float3(.86f,.81f,.69f));
        box(s,make_float3(side*7.18f,y+.86f,z),make_float3(.10f,.58f,1.16f),FABRIC,accent);
        box(s,make_float3(side*5.7f,y+.69f,z),make_float3(.64f,.035f,1.08f),FABRIC,accent);
        for(int j=-1;j<=1;j+=2){box(s,make_float3(side*6.8f,y+.73f,z+j*.52f),make_float3(.28f,.12f,.42f),FABRIC,make_float3(.93f,.89f,.80f));
            box(s,make_float3(side*7.0f,y+.37f,z+j*1.65f),make_float3(.40f,.36f,.35f),WOOD,make_float3(.46f,.28f,.14f));
            box(s,make_float3(side*7.0f,y+.85f,z+j*1.65f),make_float3(.12f,.12f,.12f),LIGHT,make_float3(1,.70f,.38f),false);}
    }
}

__device__ void sideWindow(float* s,float x,float y,float z){
    box(s,make_float3(x,y+1.8f,z),make_float3(.025f,.80f,1.05f),GLASS,make_float3(.79f,.86f,.88f));
    for(int j=-1;j<=1;j+=2){box(s,make_float3(x,y+1.8f+j*.84f,z),make_float3(.14f,.055f,1.14f),METAL,make_float3(.16f,.18f,.18f));
        box(s,make_float3(x,y+1.8f,z+j*1.10f),make_float3(.14f,.88f,.045f),METAL,make_float3(.16f,.18f,.18f));}
    box(s,make_float3(x,y+1.8f,z),make_float3(.13f,.84f,.028f),METAL,make_float3(.16f,.18f,.18f));
    box(s,make_float3(x,y+.92f,z),make_float3(.3f,.06f,1.18f),CONCRETE,make_float3(.65f,.64f,.57f));
}
__device__ void emitBuilding(float* s,unsigned int seed,int lotX,int lotZ,int resident,float offsetX,float offsetZ){
    s[16]=offsetX;s[17]=offsetZ;unsigned int key=mix(seed^mix((unsigned int)lotX*1973u+1387u)^mix((unsigned int)lotZ*9277u+5261u));
    s[15]=(float)resident;s[3]=(float)(key&65535u);s[4]=(float)(key>>16);
    s[5]=.90f+.23f*randf(key^101u);s[6]=.93f+.20f*randf(key^102u);s[7]=(float)(mix(key^103u)%3u);s[8]=(float)(2u+mix(key^104u)%3u);s[9]=(float)(mix(key^105u)%3u);
    int floors=(int)s[8];s[10]=0.0f;for(int f=1;f<=4;++f)s[10+f]=s[9+f]+3.08f+.27f*randf(mix(key^(unsigned int)f)^106u);
    float3 plaster=make_float3(.78f,.75f,.66f),brick=make_float3(.40f,.20f,.115f),floorWood=make_float3(.52f,.32f,.17f),dark=make_float3(.13f,.16f,.15f);
    int facade=(int)s[7]==1?CONCRETE:BRICK;brick=lerp(make_float3(.29f,.12f,.07f),make_float3(.49f,.35f,.22f),randf(key^107u));if(facade==CONCRETE)brick=make_float3(.56f,.58f,.54f);

    box(s,make_float3(0,-.08f,-14),make_float3(4,.08f,6),CONCRETE,make_float3(.64f,.62f,.55f));
    for(int i=0;i<6;++i){plant(s,-5.5f,0,-19+i*1.4f,1.5f);plant(s,5.5f,0,-19+i*1.4f,1.5f);}
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
        if(f>0){box(s,make_float3(0,y+.5f,-8.1f),make_float3(1.4f,.5f,.16f),facade,brick);box(s,make_float3(0,y+1.85f,-8.1f),make_float3(1.38f,.85f,.025f),GLASS,make_float3(.8f,.9f,.9f));}
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
        if(resident)for(int j=0;j<4;++j){float z=-6+j*3.5f;box(s,make_float3(0,y+storey-.24f,z),make_float3(.45f,.028f,.05f),LIGHT,make_float3(1,.83f,.57f),false);}
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
    // Entrance portal, canopy, facade bands and planted setbacks.
    for(int side=-1;side<=1;side+=2){box(s,make_float3(side*1.48f,1.4f,-8.4f),make_float3(.12f,1.4f,.33f),CONCRETE,make_float3(.68f,.64f,.55f));
        box(s,make_float3(side*2.2f,1.85f,-8.29f),make_float3(.065f,.22f,.055f),LIGHT,make_float3(1,.7f,.35f),false);}
    box(s,make_float3(0,2.84f,-8.7f),make_float3(2.1f,.10f,.90f),CONCRETE,make_float3(.65f,.62f,.54f));
    for(int f=1;f<=floors;++f){box(s,make_float3(0,floorBase(s,f),-8.27f),make_float3(9.3f,.10f,.12f),CONCRETE,make_float3(.59f,.57f,.49f));
        for(int side=-1;side<=1;side+=2)box(s,make_float3(side*9.2f,floorBase(s,f),1.5f),make_float3(.10f,.10f,9.7f),CONCRETE,make_float3(.59f,.57f,.49f));}
    float roofY=floorBase(s,floors);int roof=(int)s[9];
    if(roof==0){for(int side=-1;side<=1;side+=2){box(s,make_float3(side*9.05f,roofY+.3f,1.5f),make_float3(.10f,.3f,9.65f),CONCRETE,plaster);box(s,make_float3(0,roofY+.3f,1.5f+side*9.55f),make_float3(9.1f,.3f,.10f),CONCRETE,plaster);}for(int j=0;j<4;++j)plant(s,-7+j*4.5f,roofY,9.3f,1.25f);}
    if(roof==1){for(int j=0;j<48;++j){float x=-9.4f+(j+.5f)*18.8f/48.0f,height=.25f+(1-fabsf(x)/9.4f)*2.1f;box(s,make_float3(x,roofY+height,1.5f),make_float3(18.8f/96.0f,.06f,9.95f),METAL,make_float3(.19f,.22f,.21f));for(int side=-1;side<=1;side+=2)box(s,make_float3(x,roofY+height*.5f,1.5f+side*9.55f),make_float3(18.8f/96.0f,height*.5f,.1f),facade,brick);}}
    if(roof==2){for(int j=0;j<3;++j)box(s,make_float3(0,roofY+j*.38f+.19f,1.5f),make_float3(7.9f-j*1.6f,.19f,8.1f-j*1.6f),CONCRETE,plaster);for(int j=0;j<3;++j)box(s,make_float3(-3.4f+j*3.0f,roofY+1.25f,1.3f),make_float3(.9f,.1f,1.6f),GLASS,make_float3(.15f,.24f,.28f));}
}
// A bounded residency window enumerates the SAME exterior grammar at every address.
// No proxy facade or different distant roof. Only hidden interior allocation changes.
__global__ void generateScene(float* s,unsigned int seed,int lotX,int lotZ,int resident){
    if(threadIdx.x||blockIdx.x)return;s[0]=0;s[2]=0;s[5]=1;s[6]=1;s[16]=0;s[17]=0;s[3]=0;s[4]=0;
    box(s,make_float3(0,-.2f,0),make_float3(120,.2f,120),ASPHALT,make_float3(.26f,.28f,.25f));
    emitBuilding(s,seed,lotX,lotZ,resident,0,0);s[1]=s[0];float header[18];for(int i=1;i<18;++i)header[i]=s[i];
    for(int dz=-2;dz<=2;++dz)for(int dx=-2;dx<=2;++dx){if(dx!=0||dz!=0)emitBuilding(s,seed,lotX+dx,lotZ+dz,0,dx*40.0f,dz*40.0f);}
    float overflow=s[2];for(int i=1;i<18;++i)s[i]=header[i];s[2]=overflow;
}

__global__ void describeLayout(const float* s,float* Plan){if(threadIdx.x||blockIdx.x)return;for(int i=0;i<64;++i)Plan[i]=0;Plan[0]=s[5];Plan[1]=s[6];Plan[2]=s[8];Plan[3]=s[9];Plan[4]=s[7];Plan[5]=s[3];Plan[6]=s[4];Plan[7]=s[15];for(int f=0;f<=4;++f)Plan[8+f]=floorBase(s,f);for(int f=0;f<(int)s[8];++f)for(int r=0;r<4;++r){int side=r%2?1:-1;Plan[16+f*4+r]=roomZ(s,f,side,r/2)*s[6];Plan[32+f*4+r]=(float)roomType(s,f,side,r/2);}}


__device__ unsigned int spread(unsigned int x){x&=1023u;x=(x|(x<<16))&0x030000ffu;x=(x|(x<<8))&0x0300f00fu;x=(x|(x<<4))&0x030c30c3u;x=(x|(x<<2))&0x09249249u;return x;}
__global__ void morton(const float* s,unsigned int* keys){int i=(int)(blockIdx.x*blockDim.x+threadIdx.x);if(i>=CAP)return;keys[i*2+1]=(unsigned int)i;if(i>=(int)s[0]){keys[i*2]=4294967295u;return;}Shape o=readShape(s,i);float3 p=(o.lo+o.hi)*0.5f;unsigned int x=(unsigned int)(clamp((p.x+110.0f)/220.0f)*1023.0f),y=(unsigned int)(clamp((p.y+1.0f)/18.0f)*1023.0f),z=(unsigned int)(clamp((p.z+110.0f)/220.0f)*1023.0f);keys[i*2]=spread(x)|(spread(y)<<1)|(spread(z)<<2);}
__global__ void sortPairs(unsigned int* keys,int stage,int stride){int i=(int)(blockIdx.x*blockDim.x+threadIdx.x);int j=i^stride;if(i>=CAP||j<=i)return;bool up=(i&stage)==0;unsigned int a=keys[i*2],b=keys[j*2],ai=keys[i*2+1],bi=keys[j*2+1];bool greater=a>b||(a==b&&ai>bi);if(greater==up){keys[i*2]=b;keys[i*2+1]=bi;keys[j*2]=a;keys[j*2+1]=ai;}}
__global__ void leaves(const float* s,const unsigned int* keys,float* nodes){int i=(int)(blockIdx.x*blockDim.x+threadIdx.x);if(i>=CAP)return;int j=(int)keys[i*2+1];Node n;if(j<(int)s[0]){Shape o=readShape(s,j);n.lo=o.lo;n.hi=o.hi;n.shape=j;}else{n.lo=make_float3(1e20f,1e20f,1e20f);n.hi=make_float3(-1e20f,-1e20f,-1e20f);n.shape=-1;}writeNode(nodes,CAP+i,n);}
__global__ void parents(float* nodes,int start){int i=(int)(blockIdx.x*blockDim.x+threadIdx.x);if(i>=start)return;int j=start+i;Node a=readNode(nodes,j*2),b=readNode(nodes,j*2+1),n;n.lo=vmin(a.lo,b.lo);n.hi=vmax(a.hi,b.hi);n.shape=-1;writeNode(nodes,j,n);}
__device__ float bound(float3 ro,float3 inv,float3 lo,float3 hi,float maxT){if(lo.x>hi.x||lo.y>hi.y||lo.z>hi.z)return 1e30f;float3 a=(lo-ro)*inv,b=(hi-ro)*inv;float3 mn=vmin(a,b),mx=vmax(a,b);float near=fmaxf(mn.x,fmaxf(mn.y,mn.z)),far=fminf(mx.x,fminf(mx.y,mx.z));return far>=fmaxf(near,.001f)&&near<maxT?fmaxf(near,.001f):1e30f;}
struct Hit{float t;int id;float3 n;};
__device__ Hit trace(const float* s,const float* nodes,float3 ro,float3 rd,float maxT=1000,bool shadow=false){
    float3 inv=make_float3(1/(fabsf(rd.x)<1e-8f?1e-8f:rd.x),1/(fabsf(rd.y)<1e-8f?1e-8f:rd.y),1/(fabsf(rd.z)<1e-8f?1e-8f:rd.z));
    int stack[32],top=0;stack[top++]=1;Hit hit;hit.t=maxT;hit.id=-1;hit.n=make_float3(0,0,0);
    while(top){int i=stack[--top];Node n=readNode(nodes,i);if(bound(ro,inv,n.lo,n.hi,hit.t)>=hit.t)continue;
        if(i>=CAP){if(n.shape<0)continue;Shape o=readShape(s,n.shape);if(shadow&&(o.mat==GLASS||o.mat==LIGHT))continue;
            float3 a=(o.lo-ro)*inv,b=(o.hi-ro)*inv,mn=vmin(a,b),mx=vmax(a,b);
            float near=fmaxf(mn.x,fmaxf(mn.y,mn.z)),far=fminf(mx.x,fminf(mx.y,mx.z));float t=near>.001f?near:far;
            if(o.mat==LEAF){float3 center=(o.lo+o.hi)*.5f,radius=(o.hi-o.lo)*.5f;float3 q=make_float3((ro.x-center.x)/radius.x,(ro.y-center.y)/radius.y,(ro.z-center.z)/radius.z),d=make_float3(rd.x/radius.x,rd.y/radius.y,rd.z/radius.z);float aa=dot(d,d),bb=dot(q,d),cc=dot(q,q)-1.0f,disc=bb*bb-aa*cc;if(disc<0)continue;t=(-bb-sqrtf(disc))/aa;if(t<.001f)t=(-bb+sqrtf(disc))/aa;}
            if(t>.001f&&t<hit.t){hit.t=t;hit.id=n.shape;float3 p=ro+rd*t,c=(o.lo+o.hi)*.5f,h=(o.hi-o.lo)*.5f;
                float3 v=make_float3((p.x-c.x)/fmaxf(.00001f,h.x),(p.y-c.y)/fmaxf(.00001f,h.y),(p.z-c.z)/fmaxf(.00001f,h.z));
                if(fabsf(v.x)>fabsf(v.y)&&fabsf(v.x)>fabsf(v.z))hit.n=make_float3(v.x>0?1.f:-1.f,0,0);else if(fabsf(v.y)>fabsf(v.z))hit.n=make_float3(0,v.y>0?1.f:-1.f,0);else hit.n=make_float3(0,0,v.z>0?1.f:-1.f);
                if(o.mat==LEAF){float3 center=(o.lo+o.hi)*.5f,radius=(o.hi-o.lo)*.5f;hit.n=norm(make_float3((p.x-center.x)/(radius.x*radius.x),(p.y-center.y)/(radius.y*radius.y),(p.z-center.z)/(radius.z*radius.z)));}
                if(shadow)return hit;}
        }else{float a=bound(ro,inv,readNode(nodes,i*2).lo,readNode(nodes,i*2).hi,hit.t),b=bound(ro,inv,readNode(nodes,i*2+1).lo,readNode(nodes,i*2+1).hi,hit.t);
            if(a<b){if(b<hit.t)stack[top++]=i*2+1;if(a<hit.t)stack[top++]=i*2;}else{if(a<hit.t)stack[top++]=i*2;if(b<hit.t)stack[top++]=i*2+1;}}
    }return hit;
}

__device__ float3 material(Shape o,float3 p,float3 n,float footprint){
    p=p-o.origin;float3 c=o.color;float u=fabsf(n.x)>.5f?p.z:p.x,v=fabsf(n.y)>.5f?p.z:p.y;
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
    if(o.mat==FABRIC)c=c*(1+.035f*sinf(u*420)*sinf(v*420)*micro);
    if(o.mat==CONCRETE||o.mat==PLASTER)c=c*(.98f+.04f*noise*micro);
    if(o.mat==ASPHALT){float d=fminf(fabsf(p.x),fabsf(p.z+14));c=c*(.92f+.12f*noise);if(fabsf(p.x)>12||p.z>15)c=make_float3(.22f,.27f,.14f)*(.9f+noise*.2f);}
    return c;
}
__device__ float3 sky(float3 rd){float t=clamp(rd.y*.7f+.35f);float3 c=lerp(make_float3(.76f,.79f,.76f),make_float3(.28f,.48f,.68f),t);float sun=powf(fmaxf(0,dot(rd,norm(make_float3(-.7f,1,-.5f)))),900);return c+make_float3(6,4.8f,3.1f)*sun;}
__device__ float3 shade(const float* s,const float* nodes,float3 ro,float3 rd,Hit h,unsigned int rng,float pixelScale,bool detailed){
    if(h.id<0)return sky(rd);Shape o=readShape(s,h.id);float3 p=ro+rd*h.t,n=h.n,c=material(o,p,n,h.t*pixelScale);
    if(o.mat==LIGHT)return o.color*3;
    float sx=s[5],sz=s[6];int floor=0;for(int f=1;f<(int)s[8];++f)if(p.y+.05f>=floorBase(s,f))floor=f;float base=floorBase(s,floor),ceiling=floorBase(s,floor+1);
    bool indoors=fabsf(p.x)<9.15f*sx&&p.z>-8.25f*sz&&p.z<11.2f*sz&&p.y<floorBase(s,(int)s[8])-.1f;
    float ambient=indoors?.20f:.40f;float3 illumination=make_float3(ambient*.9f,ambient*.95f,ambient);
    float3 sun=norm(make_float3(-.7f,1,-.5f));float nd=clamp(dot(n,sun));
    if(nd>0){float3 jitter=make_float3(randf(rng)-.5f,randf(rng+1)-.5f,randf(rng+2)-.5f)*.025f;float3 l=norm(sun+jitter);Hit sh=trace(s,nodes,p+n*.003f,l,80,true);if(sh.id<0)illumination=illumination+make_float3(2.4f,2.05f,1.55f)*nd;}
    if(indoors){
        int side=p.x<0?-1:1,back=p.z/sz<roomSplit(s,floor,side)?0:1;float rz=roomZ(s,floor,side,back)*sz;
        float3 lamp;if(fabsf(p.x)<1.85f*sx)lamp=make_float3(0,ceiling-.35f,(floorf((p.z/sz+6)/3.5f+.5f)*3.5f-6)*sz);else lamp=make_float3(side*5.2f*sx,ceiling-.3f,rz);
        if(p.z>5.4f*sz)lamp=make_float3(0,ceiling-.2f,8.8f*sz);
        float3 delta=lamp-p;float dist=sqrtf(dot(delta,delta));float3 l=delta/fmaxf(.01f,dist);float cosine=clamp(dot(n,l));
        if(cosine>0){Hit sh=trace(s,nodes,p+n*.005f,l,dist-.08f,true);if(sh.id<0)illumination=illumination+make_float3(1.0f,.81f,.59f)*(cosine*5.5f/(1+dist*dist*.55f));}
        // Broad diffuse fill from the nearest real window.
        float3 window=make_float3(side*8.9f*sx,base+1.85f,rz);float3 wl=norm(window-p);
        float facing=clamp(dot(n,wl));illumination=illumination+make_float3(.43f,.51f,.59f)*(facing/(1+fabsf(window.x-p.x)*.12f));
    }
    if(detailed){float3 random=norm(make_float3(randf(rng+3)*2-1,randf(rng+4)*2-1,randf(rng+5)*2-1));float3 ao=norm(n+random);if(dot(ao,n)<.01f)ao=n;
        Hit occ=trace(s,nodes,p+n*.004f,ao,1.1f,true);if(occ.id>=0)illumination=illumination*(.6f+.4f*clamp(occ.t/1.1f));}
    return c*illumination;
}
__global__ void render(const float* s,const float* nodes,const float* C,unsigned int* pixels,float* history,int w,int h,int quality){
    int x=(int)(blockIdx.x*blockDim.x+threadIdx.x),y=(int)blockIdx.y;if(x>=w||y>=h)return;int i=y*w+x;int sample=(int)C[9];Camera cam=readCam(C);unsigned int rng=mix(i^sample*747796405u);
    float3 f=make_float3(sinf(cam.yaw)*cosf(cam.pitch),sinf(cam.pitch),cosf(cam.yaw)*cosf(cam.pitch)),right=make_float3(cosf(cam.yaw),0,-sinf(cam.yaw)),up=cross(f,right);
    float jx=sample?randf(rng)-.5f:0,jy=sample?randf(rng+7)-.5f:0;
    float sx=(2*(x+.5f+jx)/w-1)*(float(w)/h)*.68f,sy=(1-2*(y+.5f+jy)/h)*.68f;
    float3 ro=cam.foot+make_float3(0,1.65f,0),rd=norm(f+right*sx+up*sy);Hit hit=trace(s,nodes,ro,rd);float3 color;
    if(hit.id>=0&&readShape(s,hit.id).mat==GLASS){
        float3 p=ro+rd*hit.t;Hit through=trace(s,nodes,p+rd*.06f,rd);color=shade(s,nodes,p+rd*.06f,rd,through,rng,1.f/h,quality>0);
        float3 reflected=rd-hit.n*(2*dot(rd,hit.n));float fresnel=.035f+.65f*powf(1-fabsf(dot(rd,hit.n)),5);
        color=lerp(color*make_float3(.94f,.98f,.98f),sky(reflected),fresnel);
    }else color=shade(s,nodes,ro,rd,hit,rng,1.f/h,quality>0);
    if(sample>0)color=lerp(make_float3(history[i*4],history[i*4+1],history[i*4+2]),color,1.f/(sample+1));history[i*4]=color.x;history[i*4+1]=color.y;history[i*4+2]=color.z;
    color=color*1.35f;
    // ACES-style filmic curve with display gamma.
    float vals[3]={color.x,color.y,color.z};unsigned int bytes[3];for(int k=0;k<3;++k){float v=vals[k];v=clamp((v*(2.51f*v+.03f))/(v*(2.43f*v+.59f)+.14f));bytes[k]=static_cast<unsigned int>(powf(v,1/2.2f)*255+.5f);}
    pixels[i]=0xff000000u|bytes[0]|(bytes[1]<<8)|(bytes[2]<<16);
}

__device__ bool overlap(float lo,float hi,float a,float b){return lo<b-.001f&&hi>a+.001f;}
__device__ bool freeBody(const float* s,float3 foot){for(int i=0;i<((int)s[1]);++i){Shape o=readShape(s,i);if(!o.solid)continue;if(overlap(foot.x-.26f,foot.x+.26f,o.lo.x,o.hi.x)&&overlap(foot.y+.015f,foot.y+1.78f,o.lo.y,o.hi.y)&&overlap(foot.z-.26f,foot.z+.26f,o.lo.z,o.hi.z))return false;}return true;}
__device__ Camera horizontal(const float* s,Camera c,float delta,int axis){
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
__global__ void simulate(const float* s,float* C,const float* I,int steps){if(threadIdx.x||blockIdx.x)return;Camera c=readCam(C);Input input;input.forward=I[0];input.side=I[1];input.dx=I[2];input.dy=I[3];input.sprint=(int)I[4];input.jump=(int)I[5];
    float3 startFoot=c.foot;
    c.yaw+=input.dx*.0022f;c.pitch=clamp(c.pitch-input.dy*.0022f,-1.45f,1.45f);
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
    }if(dot(c.foot-startFoot,c.foot-startFoot)>.00000001f||input.dx!=0||input.dy!=0)C[9]=0.0f;writeCam(C,c);
}

__global__ void accumulate(float* C){if(threadIdx.x||blockIdx.x)return;C[9]=fminf(63.0f,C[9]+1.0f);}


__global__ void initCamera(const float* s,float* C,int view){if(threadIdx.x||blockIdx.x)return;for(int i=0;i<16;++i)C[i]=0.0f;C[2]=-15.0f;
if(view==1){C[0]=15;C[1]=3;C[2]=-22;C[3]=-.65f;C[4]=.04f;}
if(view==2){C[0]=.2f;C[2]=-7;C[3]=.08f;C[4]=.02f;}
if(view==3){C[0]=-2.6f;C[2]=-6.5f;C[3]=-.87f;C[4]=-.06f;}
if(view==4){C[0]=-.3f;C[2]=3.8f;C[3]=.03f;C[4]=.18f;}
if(view==5){C[2]=4.7f;C[1]=floorBase(s,(int)s[8]-1);C[3]=PI;C[4]=-.03f;}C[0]*=s[5];C[2]*=s[6];}
