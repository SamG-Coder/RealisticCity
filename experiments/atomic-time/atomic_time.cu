// Native CUDA research experiment. No browser, JavaScript, or shader transpiler.
// Exact time skipping: additive CA scaling (Moore, Quasi-Linear CA, section 3).
// Reversible collisions: HPP lattice gas (Margolus, Crystalline Computation).
#include <cuda_runtime.h>
#include <algorithm>
#include <chrono>
#include <cmath>
#include <cstdint>
#include <fstream>
#include <iostream>
#include <stdexcept>
#include <string>
#include <vector>

using U = uint32_t;
using Tick = uint64_t;
using State = std::vector<U>;
#define CU(x) do { cudaError_t e=(x); if(e!=cudaSuccess) throw std::runtime_error(std::string(#x)+": "+cudaGetErrorString(e)); } while(0)
#define HD __host__ __device__

HD U mix(U x) { x^=x>>16; x*=0x7feb352du; x^=x>>15; x*=0x846ca68bu; return x^(x>>16); }
// Involutive nonlinear relabelling of three bits: (a,b,c) -> (a,b,c XOR a*b).
// This is a deliberately simple conjugacy, NOT Moore/Pnin's general algorithm.
HD U relabel(U v) { return v ^ (((v&1u)*((v>>1)&1u))<<2); }
HD U seedCell(U i,U seed) { return mix(i^seed)&7u; }

struct Device {
    U* p=nullptr; size_t n;
    explicit Device(size_t count):n(count) { CU(cudaMalloc(&p,n*sizeof(U))); }
    ~Device() { cudaFree(p); }
    Device(const Device&)=delete;
    void put(const State& s) { if(s.size()!=n) throw std::runtime_error("size mismatch"); CU(cudaMemcpy(p,s.data(),n*sizeof(U),cudaMemcpyHostToDevice)); }
    State get() const { State s(n); CU(cudaMemcpy(s.data(),p,n*sizeof(U),cudaMemcpyDeviceToHost)); return s; }
};

__global__ void generate(U* out,U n,U seed) {
    U i=blockIdx.x*blockDim.x+threadIdx.x;
    if(i<n) out[i]=relabel(seedCell(i,seed));
}

// F^(2^k)(x)[i] = x[i-2^k] XOR x[i+2^k] on a periodic ring.
// Applying the relabelling on both sides preserves composition exactly.
__global__ void jumpKernel(const U* in,U* out,U n,U shift) {
    U i=blockIdx.x*blockDim.x+threadIdx.x;
    if(i<n) {
        U left=(i+n-shift)%n,right=(i+shift)%n;
        out[i]=relabel(relabel(in[left])^relabel(in[right]));
    }
}

int jump(U*& a,U*& b,U n,Tick t) {
    U shift=1%n; int passes=0;
    while(t) {
        if(t&1) { jumpKernel<<<(n+255)/256,256>>>(a,b,n,shift); CU(cudaGetLastError()); std::swap(a,b); ++passes; }
        shift=static_cast<U>((2ull*shift)%n); t>>=1;
    }
    return passes;
}

State seeded(U n,U seed) { State s(n); for(U i=0;i<n;++i) s[i]=relabel(seedCell(i,seed)); return s; }

// Independent truth-table oracle: expanded nonlinear one-tick rule.
// c' = cL XOR cR XOR (aL*bR) XOR (aR*bL).
U scalarRule(U l,U r) {
    U a=(l^r)&1u, b=((l^r)>>1)&1u;
    U c=((l>>2)^(r>>2)^((l&1u)*((r>>1)&1u))^((r&1u)*((l>>1)&1u)))&1u;
    return a|(b<<1)|(c<<2);
}
State cpuSteps(State a,Tick ticks) {
    State b(a.size());
    while(ticks--) { for(size_t i=0;i<a.size();++i) b[i]=scalarRule(a[(i+a.size()-1)%a.size()],a[(i+1)%a.size()]); a.swap(b); }
    return a;
}
State gpuJump(const State& s,Tick ticks) {
    Device x(s.size()),y(s.size()); x.put(s); U *a=x.p,*b=y.p; jump(a,b,static_cast<U>(s.size()),ticks);
    State out(s.size()); CU(cudaMemcpy(out.data(),a,out.size()*sizeof(U),cudaMemcpyDeviceToHost)); return out;
}
void requireEqual(const State& a,const State& b,const std::string& label) {
    if(a!=b) { auto p=std::mismatch(a.begin(),a.end(),b.begin()); throw std::runtime_error(label+" mismatch at "+std::to_string(p.first-a.begin())); }
}

// Independent distant-time oracle using odd binomial coefficients (submasks of t).
// For sparse-bit t this reads only 2^popcount(t) initial cells. NOT constant cost
// for arbitrary t: reject requests that would expand to excessive work.
U directSeedQuery(U i,U n,U seed,Tick t) {
    int bits=0; for(Tick v=t;v;v>>=1) bits+=static_cast<int>(v&1);
    if(bits>20) throw std::runtime_error("direct query work limit exceeded");
    U value=0; Tick sub=t;
    for(;;) {
        U index=static_cast<U>((i+static_cast<Tick>(n)+2*(sub%n)-(t%n))%n);
        value^=seedCell(index,seed);
        if(sub==0) break;
        sub=(sub-1)&t;
    }
    return relabel(value);
}

// HPP direction bits: E=1, N=2, W=4, S=8. Only head-on pairs scatter.
HD U collide(U v) { return (v==5u || v==10u) ? (v^15u) : v; }
HD int idx(int x,int y,int w,int h) { return ((y+h)%h)*w+(x+w)%w; }
HD bool wall(int x,int y,int w,int h,bool rooms) {
    if(!rooms) return false;
    return x==0 || y==0 || x==w-1 || y==h-1 || (x==w/2 && (y<h/2-3 || y>h/2+3));
}

// Gather-only streaming, including reversible bounce-back at fixed room walls.
// Forward = collision(stream(state)); inverse = unstream(collision(state)).
__global__ void gasKernel(const U* in,U* out,int w,int h,bool rooms,bool inverse) {
    int i=static_cast<int>(blockIdx.x*blockDim.x+threadIdx.x); if(i>=w*h) return;
    int x=i%w,y=i/w;
    if(wall(x,y,w,h,rooms)) { out[i]=0; return; }
    int dx[4]={1,0,-1,0},dy[4]={0,-1,0,1}; U value=0;
    for(int d=0;d<4;++d) {
        int sx=(x+(inverse?dx[d]:-dx[d])+w)%w;
        int sy=(y+(inverse?dy[d]:-dy[d])+h)%h;
        int source=idx(sx,sy,w,h),bit=d;
        if(wall(sx,sy,w,h,rooms)) { source=i; bit=(d+2)%4; }
        U v=in[source]; if(inverse) v=collide(v);
        if(v&(1u<<bit)) value|=1u<<d;
    }
    out[i]=inverse?value:collide(value);
}

State cpuGas(const State& in,int w,int h,bool rooms) {
    State moved(in.size(),0); const int dx[4]={1,0,-1,0},dy[4]={0,-1,0,1};
    // CPU oracle scatters; the GPU gathers. Their indexing is independent.
    for(int y=0;y<h;++y) for(int x=0;x<w;++x) {
        if(wall(x,y,w,h,rooms)) continue;
        for(int d=0;d<4;++d) if(in[y*w+x]&(1u<<d)) {
            int tx=(x+dx[d]+w)%w,ty=(y+dy[d]+h)%h,bit=d;
            if(wall(tx,ty,w,h,rooms)) { tx=x;ty=y;bit=(d+2)%4; }
            moved[ty*w+tx]|=1u<<bit;
        }
    }
    for(U& v:moved) { if(v==5) v=10; else if(v==10) v=5; }
    return moved;
}
struct Totals { int count=0,px=0,py=0; };
Totals totals(const State& s) {
    Totals t; for(U v:s) { int e=v&1,n=(v>>1)&1,w=(v>>2)&1,b=(v>>3)&1; t.count+=e+n+w+b;t.px+=e-w;t.py+=b-n; } return t;
}

void gasTest(bool rooms) {
    const int w=47,h=39,ticks=257; State init(w*h);
    for(int y=0;y<h;++y) for(int x=0;x<w;++x) init[y*w+x]=wall(x,y,w,h,rooms)?0:mix(y*w+x+78123)&15;
    State cpu=init; Device x(init.size()),y(init.size());x.put(init);U *a=x.p,*b=y.p;
    for(int t=0;t<ticks;++t) {
        cpu=cpuGas(cpu,w,h,rooms);
        gasKernel<<<(w*h+255)/256,256>>>(a,b,w,h,rooms,false);CU(cudaGetLastError());std::swap(a,b);
    }
    State result(init.size());CU(cudaMemcpy(result.data(),a,result.size()*sizeof(U),cudaMemcpyDeviceToHost));
    requireEqual(result,cpu,"HPP CPU/GPU forward");
    Totals before=totals(init),after=totals(result);
    if(before.count!=after.count || (!rooms && (before.px!=after.px || before.py!=after.py))) throw std::runtime_error("HPP conservation failed");
    for(int t=0;t<ticks;++t) { gasKernel<<<(w*h+255)/256,256>>>(a,b,w,h,rooms,true);CU(cudaGetLastError());std::swap(a,b); }
    CU(cudaMemcpy(result.data(),a,result.size()*sizeof(U),cudaMemcpyDeviceToHost));
    requireEqual(result,init,"HPP reverse without history");
}

double bench(const State& initial,Tick t,bool fast,State& result) {
    Device x(initial.size()),y(initial.size());x.put(initial);U *a=x.p,*b=y.p;
    CU(cudaDeviceSynchronize());auto start=std::chrono::steady_clock::now();
    if(fast) jump(a,b,static_cast<U>(initial.size()),t);
    else for(Tick i=0;i<t;++i) { jumpKernel<<<(initial.size()+255)/256,256>>>(a,b,static_cast<U>(initial.size()),1);CU(cudaGetLastError());std::swap(a,b); }
    CU(cudaDeviceSynchronize());auto stop=std::chrono::steady_clock::now();
    result.resize(initial.size());CU(cudaMemcpy(result.data(),a,result.size()*sizeof(U),cudaMemcpyDeviceToHost));
    return std::chrono::duration<double,std::milli>(stop-start).count();
}

// Exact restricted mechanics: identical hard rods in 1D, velocities +/-1,
// elastic contacts and reflecting walls. In free coordinates y_i=x_i-i*d,
// equal-mass collisions exchange velocities. Fold independent ghost paths,
// rank them, then restore rod spacing. Physical IDs retain sorted order.
// This small demonstrator ranks in O(N^2), independent of elapsed ticks.
__global__ void rodsAtTime(const U* initial,const U* right,U* out,U n,U length,U diameter,Tick tick) {
    U i=blockIdx.x*blockDim.x+threadIdx.x;if(i>=n) return;
    Tick period=2ull*length,phase=tick%period;
    Tick u=(initial[i]+(right[i]?phase:period-phase))%period;
    U pos=static_cast<U>(u<=length?u:period-u),rank=0;
    for(U j=0;j<n;++j) {
        Tick v=(initial[j]+(right[j]?phase:period-phase))%period;
        U other=static_cast<U>(v<=length?v:period-v);
        rank+=(other<pos || (other==pos && j<i));
    }
    out[rank]=pos+rank*diameter;
}

// Independent event-driven reference in physical rod coordinates. Process every
// impact; no ghost paths or sorting. Half-integer event times are exact here.
State rodsOracle(const State& initial,const State& right,U length,U diameter,Tick tick) {
    if(tick>100000) throw std::runtime_error("event oracle time limit");
    const size_t n=initial.size();std::vector<double> x(n),v(n);
    for(size_t i=0;i<n;++i){x[i]=initial[i]+i*diameter;v[i]=right[i]?1:-1;}
    double time=0,end=static_cast<double>(tick),rightWall=length+(n-1)*diameter;
    size_t events=0;
    while(time<end) {
        double dt=end-time;
        if(v[0]<0)dt=std::min(dt,-x[0]/v[0]);
        if(v[n-1]>0)dt=std::min(dt,(rightWall-x[n-1])/v[n-1]);
        for(size_t i=0;i+1<n;++i)if(v[i]>v[i+1])dt=std::min(dt,(x[i+1]-x[i]-diameter)/(v[i]-v[i+1]));
        if(dt<0)throw std::runtime_error("negative collision time");
        for(size_t i=0;i<n;++i)x[i]+=v[i]*dt;
        time+=dt;
        if(x[0]==0 && v[0]<0)v[0]=-v[0];
        if(x[n-1]==rightWall && v[n-1]>0)v[n-1]=-v[n-1];
        for(size_t i=0;i+1<n;++i)if(x[i+1]-x[i]==diameter && v[i]>v[i+1])std::swap(v[i],v[i+1]);
        if(++events>1000000)throw std::runtime_error("event oracle did not converge");
    }
    State out(n);for(size_t i=0;i<n;++i){if(x[i]!=std::floor(x[i]))throw std::runtime_error("noninteger endpoint");out[i]=static_cast<U>(x[i]);}return out;
}

void rodsTest() {
    const U n=32,length=997,diameter=3;State initial(n),right(n);
    for(U i=0;i<n;++i){initial[i]=10+i*30+mix(i+21)%10;right[i]=mix(i+837)&1;}
    Device x(n),v(n),out(n);x.put(initial);v.put(right);
    for(Tick t:{0ull,1ull,19ull,100ull,997ull,4096ull,16384ull}) {
        rodsAtTime<<<1,64>>>(x.p,v.p,out.p,n,length,diameter,t);CU(cudaGetLastError());
        requireEqual(out.get(),rodsOracle(initial,right,length,diameter,t),"hard rods/event-driven oracle");
    }
    // +/-1 in a reflecting interval has an exact ghost period 2*length.
    Tick huge=UINT64_MAX;
    rodsAtTime<<<1,64>>>(x.p,v.p,out.p,n,length,diameter,huge);CU(cudaGetLastError());
    requireEqual(out.get(),rodsOracle(initial,right,length,diameter,huge%(2ull*length)),"hard rods distant time");
}

int main() {
    try {
        cudaDeviceProp info{};CU(cudaGetDeviceProperties(&info,0));
        std::cout<<"GPU: "<<info.name<<"\n";
        int cases=0;
        for(U n:{1u,2u,3u,17u,64u,257u}) for(U seed:{0u,7u,0xffffffffu}) {
            State initial=seeded(n,seed);
            Device generated(n);generate<<<(n+255)/256,256>>>(generated.p,n,seed);CU(cudaGetLastError());requireEqual(generated.get(),initial,"GPU seed");
            for(Tick t:{0ull,1ull,2ull,3ull,7ull,31ull,64ull,255ull,1023ull}) { requireEqual(gpuJump(initial,t),cpuSteps(initial,t),"jump/CPU");++cases; }
        }
        // Verify nonlinearity in stored coordinates (while disclosing conjugacy).
        if(scalarRule(1,2)==(scalarRule(1,0)^scalarRule(0,2))) throw std::runtime_error("nonlinearity witness failed");
        const U n=65521,seed=0x1234abcd; State initial=seeded(n,seed);
        const Tick sparse=(1ull<<60)+(1ull<<37)+5;
        State distant=gpuJump(initial,sparse);
        for(U i=0;i<n;i+=97) if(distant[i]!=directSeedQuery(i,n,seed,sparse)) throw std::runtime_error("distant seed oracle failed");
        const Tick huge=(1ull<<60)+123456789;
        requireEqual(gpuJump(initial,huge),gpuJump(gpuJump(initial,1ull<<60),123456789),"large-time composition");
        requireEqual(gpuJump(initial,UINT64_MAX),gpuJump(gpuJump(initial,UINT64_MAX-1023),1023),"64-bit time boundary");
        gasTest(false);gasTest(true);rodsTest();
        // Warm both paths, then report medians including launch/synchronization cost.
        State slow,fast;bench(initial,31,false,slow);bench(initial,31,true,fast);
        std::vector<double> slowMs,fastMs,hugeMs;
        for(int rep=0;rep<5;++rep) {
            slowMs.push_back(bench(initial,8191,false,slow));fastMs.push_back(bench(initial,8191,true,fast));requireEqual(slow,fast,"benchmark equality");
            hugeMs.push_back(bench(initial,huge,true,distant));
        }
        auto median=[](std::vector<double> v){ std::sort(v.begin(),v.end());return v[v.size()/2]; };
        int passes=0;for(Tick v=huge;v;v>>=1) passes+=static_cast<int>(v&1);
        std::ofstream report("results.json");
        report<<"{\n  \"gpu\": \""<<info.name<<"\",\n  \"cpu_oracle_cases\": "<<cases<<",\n  \"cells\": "<<n<<",\n  \"benchmark_ticks\": 8191,\n  \"step_passes\": 8191,\n  \"jump_passes\": 13,\n  \"step_median_ms\": "<<median(slowMs)<<",\n  \"jump_median_ms\": "<<median(fastMs)<<",\n  \"huge_tick\": \""<<huge<<"\",\n  \"huge_passes\": "<<passes<<",\n  \"huge_median_ms\": "<<median(hugeMs)<<",\n  \"hpp_forward_inverse_and_conservation\": true,\n  \"validation\": \"PASS\"\n}\n";
        if(!report) throw std::runtime_error("cannot write results.json");
        std::cout<<"PASS: "<<cases<<" CPU-oracle cases; sparse distant-time oracle; composition; UINT64_MAX; nonlinear witness; HPP forward/reverse/conservation; hard rods/event-driven oracle.\n"
                 <<"8191 ticks: step "<<median(slowMs)<<" ms; jump "<<median(fastMs)<<" ms ("<<median(slowMs)/median(fastMs)<<"x).\n"
                 <<"Tick "<<huge<<": "<<passes<<" passes; "<<median(hugeMs)<<" ms.\n";
        return 0;
    } catch(const std::exception& e) { std::cerr<<"FAIL: "<<e.what()<<"\n";return 1; }
}
