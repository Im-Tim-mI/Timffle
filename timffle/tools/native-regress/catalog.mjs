// The extension's texts as Chrome resolves them for one language: the tests ask for a text by its key, so they
// do not depend on which language the browser runs in. A key missing from the language falls back to English,
// and $NAME$ placeholders are filled from the substitutions, like browser.i18n.getMessage.
import fs from 'node:fs';
import path from 'node:path';

export const read=(extensionDir,language)=>{try{return JSON.parse(fs.readFileSync(path.join(extensionDir,'_locales',language,'messages.json'),'utf8'));}catch{return {};}};
export const languages=(extensionDir)=>fs.readdirSync(path.join(extensionDir,'_locales')).filter(n=>fs.statSync(path.join(extensionDir,'_locales',n)).isDirectory()).sort();
/** The language Chrome picks the catalog of for a UI language such as "en_US" or "pt_BR": the exact folder, then the part before "_", then English. */
export const resolveLanguage=(extensionDir,uiLocale)=>{const have=new Set(languages(extensionDir));return [uiLocale,uiLocale.split('_')[0],'en'].find(l=>have.has(l));};
export function loadTexts(extensionDir,language){
 const own=read(extensionDir,language),fallback=read(extensionDir,'en');
 const t=(key,substitutions=[])=>{
  const entry=own[key]??fallback[key];
  if(!entry)throw new Error('no such text: '+key);
  return entry.message.replace(/\$([A-Za-z0-9_@]+)\$/g,(all,name)=>{
   const p=Object.entries(entry.placeholders??{}).find(([n])=>n.toLowerCase()===name.toLowerCase());
   return p?p[1].content.replace(/\$(\d)/g,(_,n)=>substitutions[Number(n)-1]??''):all;
  });
 };
 /** The text as it shows on a page: no <n> tags, white space collapsed the way a page's text content is read in the tests. */
 t.plain=(key,substitutions)=>t(key,substitutions).replace(/<\/?\d>/g,'').replace(/\s+/g,' ').trim();
 return t;
}
export const norm=(s)=>s.replace(/\s+/g,' ').trim();
