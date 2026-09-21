import fs from 'node:fs/promises';
import {queryGrammar} from './query-grammar.mjs';
import {compile,serializableArtifact} from '../vendor/cuda-webshader/src/compiler/compiler.js';
import {createHash} from 'node:crypto';
const authored=await fs.readFile(new URL('../kernels/building.cu',import.meta.url),'utf8');
const source=queryGrammar(authored);
await fs.mkdir(new URL('../generated/',import.meta.url),{recursive:true});
const entries={prepareDistricts:64,generateScene:1,probeOutdoor:1,probeRay:1,probeStreet:1,describeLayout:1,morton:64,sortPairs:64,leaves:64,parents:64,initCamera:1,simulate:1,accumulate:1,farVisibility:64,movingShadows:64,render:64,temporalResolve:64,rememberFrame:64};
for(const [entry,size] of Object.entries(entries)){
 try {const artifact=serializableArtifact(compile(source,{entry,workgroupSize:[size,1,1],optimize:'specialize'}));artifact.sourceHash=createHash('sha256').update(source).digest('hex');await fs.writeFile(new URL('../generated/'+entry+'.json',import.meta.url),JSON.stringify(artifact));console.log('OK',entry,artifact.wgsl.length,artifact.metadata.bindings.map(b=>b.name));}
 catch(e){console.error(entry,e.stack);process.exit(1);}
}
