// Lower the authored emitter to a read-only query sink. No distant proxy geometry.
export function queryGrammar(source){
 const names=['between','leg','table','chair','plant','art','specialRoom','furnishRoom','room','sideWindow','emitBuilding'];
 const extracts=names.map(name=>{const pattern=new RegExp('__device__ void '+name+'\\('),start=source.search(pattern);if(start<0)throw Error('Missing shared generator '+name);let open=source.indexOf('{',start),depth=1,end=open+1;for(;depth;end++){if(source[end]==='{')depth++;if(source[end]==='}')depth--;}return source.slice(start,end);});
 // Queries currently match nonresident exteriors. Remove resident-only blocks before
 // WGSL generation so the GPU driver need not optimize the entire furniture grammar.
 let building=extracts[extracts.length-1];
 for(const marker of ['if(resident){','if(resident&&f<floors-1){','if(resident)for(int j=0;j<4;++j){']){
  const start=building.indexOf(marker);if(start<0)throw Error('Shared residency guard changed: '+marker);
  let open=building.indexOf('{',start),depth=1,end=open+1;for(;depth;end++){if(building[end]==='{')depth++;if(building[end]==='}')depth--;}
  building=building.slice(0,start)+building.slice(end);
 }
 extracts[extracts.length-1]=building;
 let generated=extracts.join('\n');
 for(const name of [...names,'box'])generated=generated.replace(new RegExp('\\b'+name+'\\(','g'),(name==='emitBuilding'?'queryBuilding':name==='box'?'queryBox':'query_'+name)+'(');
 return source.replace('// QUERY_GRAMMAR_INSERT',generated);
}
