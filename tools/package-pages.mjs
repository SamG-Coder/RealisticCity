import fs from 'node:fs/promises';
import path from 'node:path';
import {fileURLToPath} from 'node:url';
const root=fileURLToPath(new URL('../',import.meta.url)),output=path.resolve(root,'dist');
if(path.dirname(output)!==path.resolve(root)||path.basename(output)!=='dist')throw Error('Invalid Pages output directory');
await fs.rm(output,{recursive:true,force:true});
await fs.mkdir(output,{recursive:true});
// Publish only browser assets, compiled kernels and the upstream source dependencies.
for(const entry of ['index.html','style.css','src','generated','vendor/cuda-webshader/src','vendor/cuda-webshader/LICENSE']){
 const target=path.join(output,entry);await fs.mkdir(path.dirname(target),{recursive:true});await fs.cp(path.join(root,entry),target,{recursive:true});
}
await fs.writeFile(path.join(output,'.nojekyll'),'');
console.log('GitHub Pages artifact:',output);
