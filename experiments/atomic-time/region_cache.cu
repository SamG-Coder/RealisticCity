// Exact finite-horizon HPP region memoization. Native CUDA, no CPU cache.
#include <cuda_runtime.h>
#include <algorithm>
#include <chrono>
#include <cstdint>
#include <fstream>
#include <iostream>
#include <stdexcept>
#include <string>
#include <vector>
using U=uint32_t;
using State=std::vector<U>;
#define CU(x) do { auto cudaStatus=(x);if(cudaStatus!=cudaSuccess)throw std::runtime_error(std::string(#x)+": "+cudaGetErrorString(cudaStatus)); } while(0)
#define HD __host__ __device__
constexpr int B=16,MAX_K=8,MAX_PATCH=(B+2*MAX_K)*(B+2*MAX_K),OUT=B*B;
constexpr U WALL=16,RULE_VERSION=1;
HD U mix(U x){x^=x>>16;x*=0x7feb352du;x^=x>>15;x*=0x846ca68bu;return x^(x>>16);}
HD int wrap(int a,int n){int r=a%n;return r<0?r+n:r;}
HD U collision(U v){return v==5||v==10?v^15:v;}

template<class T> struct Buffer {
    T* p=nullptr;size_t n;
    explicit Buffer(size_t count):n(count){CU(cudaMalloc(&p,n*sizeof(T)));}
    ~Buffer(){cudaFree(p);}
    Buffer(const Buffer&)=delete;
    void zero(){CU(cudaMemset(p,0,n*sizeof(T)));}
};
struct Entry {U valid,horizon,hash;U key[MAX_PATCH];U result[OUT];};
struct Counters {unsigned long long hits,misses,hashRejects,keyRejects,computedCells,published;};

__global__ void stepKernel(const U* in,U* out,int w,int h){
    int i=blockIdx.x*blockDim.x+threadIdx.x;if(i>=w*h)return;
    U self=in[i];if(self&WALL){out[i]=WALL;return;}
    int x=i%w,y=i/w,dx[4]={1,0,-1,0},dy[4]={0,-1,0,1};U v=0;
    for(int d=0;d<4;++d){U s=in[wrap(y-dy[d],h)*w+wrap(x-dx[d],w)];
        if(s&WALL){if(self&(1u<<((d+2)%4)))v|=1u<<d;}else v|=s&(1u<<d);}
    out[i]=collision(v);
}

// Cache is immutable during this dispatch. Every tile reads its entire causal
// halo at the start of the interval. No boundary history is needed within K ticks.
// A separate publication dispatch elects exactly one writer per direct-map slot.
__global__ void regions(const U* in,U* out,int w,int h,int k,Entry* cache,U capacity,
                        U* claims,U* tileSlots,U* tileHashes,U* tileMiss,Counters* stats,bool useCache){
    __shared__ U a[MAX_PATCH],b[MAX_PATCH];
    __shared__ U slot,hash,hit,partial[256],different;
    int tile=blockIdx.x,tx=tile%((w+B-1)/B),ty=tile/((w+B-1)/B);
    int tid=threadIdx.x,side=B+2*k,area=side*side;
    for(int i=tid;i<area;i+=blockDim.x)a[i]=in[wrap(ty*B+i/side-k,h)*w+wrap(tx*B+i%side-k,w)];
    __syncthreads();
    if(useCache){
        U localHash=0;for(int i=tid;i<area;i+=blockDim.x)localHash^=mix(a[i]^mix(static_cast<U>(i)+0x9e3779b9u));
        partial[tid]=localHash;__syncthreads();
        for(int stride=128;stride;stride>>=1){if(tid<stride)partial[tid]^=partial[tid+stride];__syncthreads();}
    }
    if(tid==0){
        hash=useCache?mix(partial[0]^RULE_VERSION^static_cast<U>(k)):0;hit=0;slot=0;different=0;
        if(useCache){
            slot=hash%capacity;const Entry& e=cache[slot];
            if(e.valid && e.horizon==static_cast<U>(k)){
                if(e.hash!=hash)atomicAdd(&stats->hashRejects,1ull);
                else hit=1;
            }
        }
    }
    __syncthreads();
    if(hit)for(int i=tid;i<area;i+=blockDim.x)if(cache[slot].key[i]!=a[i])atomicOr(&different,1u);
    __syncthreads();
    if(tid==0){
        if(different){hit=0;atomicAdd(&stats->keyRejects,1ull);}
        if(useCache){
            tileSlots[tile]=slot;tileHashes[tile]=hash;tileMiss[tile]=!hit;
            if(!hit)atomicMin(claims+slot,static_cast<U>(tile));
        }
        atomicAdd(hit?&stats->hits:&stats->misses,1ull);
        if(!hit){unsigned long long updates=0;for(int t=1;t<=k;++t)updates+=(side-2*t)*(side-2*t);atomicAdd(&stats->computedCells,updates);}
    }
    __syncthreads();
    if(hit){
        for(int i=tid;i<OUT;i+=blockDim.x){int x=tx*B+i%B,y=ty*B+i/B;if(x<w&&y<h)out[y*w+x]=cache[slot].result[i];}
        return;
    }
    U* src=a;U* dst=b;
    for(int t=1;t<=k;++t){
        for(int i=tid;i<area;i+=blockDim.x){int x=i%side,y=i/side;
            if(x<t||y<t||x>=side-t||y>=side-t)continue;
            U self=src[i],v=0;
            if(self&WALL)dst[i]=WALL;
            else {int offsets[4]={-1,side,1,-side};
                for(int d=0;d<4;++d){U s=src[i+offsets[d]];if(s&WALL){if(self&(1u<<((d+2)%4)))v|=1u<<d;}else v|=s&(1u<<d);}
                dst[i]=collision(v);}
        }
        __syncthreads();U* tmp=src;src=dst;dst=tmp;
    }
    for(int i=tid;i<OUT;i+=blockDim.x){int x=tx*B+i%B,y=ty*B+i/B;if(x<w&&y<h)out[y*w+x]=src[(i/B+k)*side+i%B+k];}
}

__global__ void publish(const U* in,const U* out,int w,int h,int k,Entry* cache,
                        const U* claims,const U* slots,const U* hashes,const U* misses,Counters* stats){
    U tile=blockIdx.x,slot=slots[tile];if(!misses[tile]||claims[slot]!=tile)return;
    int tx=tile%((w+B-1)/B),ty=tile/((w+B-1)/B),side=B+2*k,tid=threadIdx.x;
    Entry& e=cache[slot];
    for(int i=tid;i<side*side;i+=blockDim.x)e.key[i]=in[wrap(ty*B+i/side-k,h)*w+wrap(tx*B+i%side-k,w)];
    // The host requires tile-aligned dimensions, so every output is complete.
    for(int i=tid;i<OUT;i+=blockDim.x)e.result[i]=out[(ty*B+i/B)*w+tx*B+i%B];
    if(tid==0){e.horizon=k;e.hash=hashes[tile];e.valid=1;atomicAdd(&stats->published,1ull);}
}

struct Engine {
    int w,h,tiles;U capacity;Buffer<U> a,b,claims,slots,hashes,misses;Buffer<Entry> entries;Buffer<Counters> stats;
    Engine(int width,int height,U cap):w(width),h(height),tiles((w/B)*(h/B)),capacity(cap),a(w*h),b(w*h),claims(cap),slots(tiles),hashes(tiles),misses(tiles),entries(cap),stats(1){
        if(w<=0||h<=0||w%B||h%B||!cap)throw std::runtime_error("positive tile-aligned domain/capacity required");
        clear();
    }
    void clear(){entries.zero();stats.zero();}
    void put(const State& s){if(s.size()!=a.n)throw std::runtime_error("input size");CU(cudaMemcpy(a.p,s.data(),s.size()*sizeof(U),cudaMemcpyHostToDevice));stats.zero();}
    State get(){State s(a.n);CU(cudaMemcpy(s.data(),a.p,s.size()*sizeof(U),cudaMemcpyDeviceToHost));return s;}
    Counters counts(){Counters s{};CU(cudaMemcpy(&s,stats.p,sizeof(s),cudaMemcpyDeviceToHost));return s;}
    void advance(int ticks,int horizon,int mode){
        if(ticks<0||horizon<1||horizon>MAX_K)throw std::runtime_error("invalid time/horizon");
        while(ticks){int k=mode==0?1:std::min(ticks,horizon);
            if(mode==0)stepKernel<<<(w*h+255)/256,256>>>(a.p,b.p,w,h);
            else {
                if(mode==2)CU(cudaMemset(claims.p,0xff,capacity*sizeof(U)));
                regions<<<tiles,256>>>(a.p,b.p,w,h,k,entries.p,capacity,claims.p,slots.p,hashes.p,misses.p,stats.p,mode==2);
                CU(cudaGetLastError());
                if(mode==2)publish<<<tiles,256>>>(a.p,b.p,w,h,k,entries.p,claims.p,slots.p,hashes.p,misses.p,stats.p);
            }
            CU(cudaGetLastError());std::swap(a.p,b.p);ticks-=k;
        }
    }
};

State cpuStep(const State& in,int w,int h){
    State out(in.size());int dx[4]={1,0,-1,0},dy[4]={0,-1,0,1};
    for(int i=0;i<w*h;++i){if(in[i]&WALL){out[i]=WALL;continue;}
        for(int d=0;d<4;++d)if(in[i]&(1u<<d)){int j=wrap(i/w+dy[d],h)*w+wrap(i%w+dx[d],w),bit=d;
            if(in[j]&WALL){j=i;bit=(d+2)%4;}out[j]|=1u<<bit;}}
    for(U& v:out){if(v==5)v=10;else if(v==10)v=5;}return out;
}
void same(const State& a,const State& b,const std::string& msg){if(a!=b){size_t i=std::mismatch(a.begin(),a.end(),b.begin()).first-a.begin();throw std::runtime_error(msg+" cell "+std::to_string(i));}}
unsigned long long countParticles(const State& s){unsigned long long n=0;for(U v:s)for(int d=0;d<4;++d)n+=(v>>d)&1;return n;}
State scene(int w,int h,int kind){
    State s(w*h);for(int y=0;y<h;++y)for(int x=0;x<w;++x){
        // Repeated room grid, openings at regular intervals, finite outer walls.
        bool wall=x==0||y==0||x==w-1||y==h-1||((x%64==0)&&(y%64<28||y%64>35))||((y%64==0)&&(x%64<28||x%64>35));
        U v=0;if(kind==1 && mix(y*w+x+73)%1024==0)v=1u<<(mix(x+y*7)&3);
        if(kind==2)v=mix((y%32)*32+x%32+123)&15;
        if(kind==3)v=mix(y*w+x+1297)&15;
        // Synthetic active best case: uniform head-on pairs on a torus scatter
        // E/W -> N/S -> E/W forever. No room walls in this control scenario.
        if(kind==4){s[y*w+x]=5;continue;}
        s[y*w+x]=wall?WALL:v;
    }return s;
}

void validate(){
    int cases=0;for(U cap:{1u,17u,1024u}){Engine e(64,64,cap);
        for(int kind=0;kind<4;++kind)for(int k:{1,3,8}){
            State s=scene(64,64,kind),cpu=s;
            e.clear();e.put(s);e.advance(19,k,2);for(int t=0;t<19;++t)cpu=cpuStep(cpu,64,64);
            same(e.get(),cpu,"cached CPU oracle");if(countParticles(s)!=countParticles(cpu))throw std::runtime_error("particle conservation");
            // Reuse the populated cache from a different initial state, not only reset/replay.
            s[31*64+15]^=1;s[32*64+32]=WALL;e.put(s);e.advance(19,k,2);cpu=s;
            for(int t=0;t<19;++t)cpu=cpuStep(cpu,64,64);same(e.get(),cpu,"changed particle/geometry");++cases;
        }
    }
    // The halo MUST distinguish an incoming particle outside the tile interior.
    Engine e(64,64,1024);State s(4096,0);e.put(s);e.advance(8,8,2);e.put(s);e.advance(8,8,2);
    if(e.counts().hits!=16)throw std::runtime_error("warm empty cache must hit");
    s[24*64+15]=1;State cpu=s;for(int t=0;t<8;++t)cpu=cpuStep(cpu,64,64);
    e.put(s);e.advance(8,8,2);same(e.get(),cpu,"incoming halo particle");if(e.get()[24*64+23]!=1)throw std::runtime_error("particle did not cross tile edge");
    // Forge matching hashes with incorrect keys to exercise full-key rejection.
    std::vector<Entry> poisoned(e.capacity);CU(cudaMemcpy(poisoned.data(),e.entries.p,poisoned.size()*sizeof(Entry),cudaMemcpyDeviceToHost));
    for(auto& entry:poisoned)if(entry.valid)entry.key[0]^=1;
    CU(cudaMemcpy(e.entries.p,poisoned.data(),poisoned.size()*sizeof(Entry),cudaMemcpyHostToDevice));
    e.put(s);e.advance(8,8,2);same(e.get(),cpu,"forged hash full-key check");if(!e.counts().keyRejects)throw std::runtime_error("full-key rejection untested");
    // Horizon changes and zero time with retained cache.
    e.put(s);e.advance(0,8,2);same(e.get(),s,"zero time");e.advance(7,7,2);cpu=s;for(int t=0;t<7;++t)cpu=cpuStep(cpu,64,64);same(e.get(),cpu,"horizon change");
    // Randomized wall masks (including obstacles on tile and periodic edges).
    for(U seed=1;seed<=8;++seed){State random(4096);for(U i=0;i<4096;++i){U v=mix(i+seed*4099);random[i]=v%7==0?WALL:(v>>8)&15;}
        e.clear();e.put(random);e.advance(23,8,1);cpu=random;for(int t=0;t<23;++t)cpu=cpuStep(cpu,64,64);same(e.get(),cpu,"random walls tiled");
        e.put(random);e.advance(23,8,2);same(e.get(),cpu,"random walls cached");}
    std::cout<<"PASS: "<<cases<<" cold/edited CPU cases, tile-boundary crossing, forged hash, horizon, zero time, conservation.\n";
}

double timed(Engine& e,int ticks,int k,int mode){CU(cudaDeviceSynchronize());auto start=std::chrono::steady_clock::now();e.advance(ticks,k,mode);CU(cudaDeviceSynchronize());return std::chrono::duration<double,std::milli>(std::chrono::steady_clock::now()-start).count();}
double median(std::vector<double> a){std::sort(a.begin(),a.end());return a[a.size()/2];}
int main(int argc,char** argv){try{
    cudaDeviceProp prop{};CU(cudaGetDeviceProperties(&prop,0));std::cout<<"GPU: "<<prop.name<<"\n";validate();
    if(argc==2&&std::string(argv[1])=="--validate-only")return 0;
    constexpr int w=512,h=512,ticks=256,k=8;constexpr U cap=4096;
    Engine e(w,h,cap);std::ofstream csv("region-results.csv");csv<<"scenario,step_ms,tiled_ms,cache_cold_ms,cache_replay_ms,hit_rate,computed_cell_updates,uncached_tiled_updates,published_entries,cache_bytes\n";
    const char* names[]={"quiet","sparse","repeated","dense","periodic_collision"};
    for(int kind=0;kind<5;++kind){State initial=scene(w,h,kind),reference;std::vector<double> step,tiled,cold,warm;Counters c{};
        e.put(initial);timed(e,8,k,0);e.put(initial);timed(e,8,k,1); // warm CUDA paths
        for(int rep=0;rep<5;++rep){
            e.put(initial);step.push_back(timed(e,ticks,k,0));reference=e.get();
            e.put(initial);tiled.push_back(timed(e,ticks,k,1));same(e.get(),reference,"tiled reference");
            e.clear();e.put(initial);cold.push_back(timed(e,ticks,k,2));same(e.get(),reference,"cold reference");c=e.counts();
            e.put(initial);warm.push_back(timed(e,ticks,k,2));same(e.get(),reference,"replay reference");
        }
        unsigned long long per=0;for(int t=1;t<=k;++t)per+=(B+2*k-2*t)*(B+2*k-2*t);
        auto all=per*(w/B)*(h/B)*(ticks/k);double rate=static_cast<double>(c.hits)/(c.hits+c.misses);
        size_t bytes=cap*sizeof(Entry)+cap*sizeof(U)+3*(w/B)*(h/B)*sizeof(U)+sizeof(Counters);
        csv<<names[kind]<<','<<median(step)<<','<<median(tiled)<<','<<median(cold)<<','<<median(warm)<<','<<rate<<','<<c.computedCells<<','<<all<<','<<c.published<<','<<bytes<<'\n';
        std::cout<<names[kind]<<": step="<<median(step)<<" tiled="<<median(tiled)<<" cache="<<median(cold)<<" replay="<<median(warm)<<" ms; hits="<<100*rate<<"%; updates="<<c.computedCells<<'/'<<all<<"; memory="<<bytes<<" bytes\n";
    }
    if(!csv)throw std::runtime_error("report write failed");return 0;
}catch(const std::exception& e){std::cerr<<"FAIL: "<<e.what()<<'\n';return 1;}}
