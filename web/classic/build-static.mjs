import {copyFile, mkdir, writeFile} from 'node:fs/promises';
import {resolve} from 'node:path';

const target=resolve('dist-ogilga');
await mkdir(target,{recursive:true});
for (const file of ['index.html','mast.png','classic.mjs','bill-rows.mjs','public-acts.mjs','chambers.mjs','statutes.mjs','service-time.mjs','service-House.json','service-Senate.json']) {
  await copyFile(new URL(file,import.meta.url),resolve(target,file));
}
await copyFile(new URL('../reader-panels.mjs',import.meta.url),resolve(target,'reader-panels.mjs'));
const base=new URL('/classic/api/',process.env.PUBLIC_FEED_ORIGIN);
if (base.protocol!=='https:') throw Error('Expected HTTPS feed');
await writeFile(resolve(target,'api-url.mjs'),'export const apiBase='+JSON.stringify(base.href)+';\n');
