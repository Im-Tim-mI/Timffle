// Every language of the extension, in a real (headless) Chrome running in that language: the pages show the texts of
// that language's catalog, in the right script and direction, and nothing sticks out of its box. It does not need
// the socket helper or a network; the flows themselves are covered by ask-tests.mjs (run with TEST_LOCALE=<language>).
//   node locale-tests.mjs <unpacked extension dir> [language ...]     (default: all languages of the extension)
// SHOTS=<dir> also writes a picture of the question window and of the settings page for each language.
import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import path from 'node:path';
import crypto from 'node:crypto';
import {Chrome,delay} from './chrome-cdp-native.mjs';
import {languages,loadTexts,norm,resolveLanguage} from './catalog.mjs';

const root=path.dirname(new URL(import.meta.url).pathname);
const [extensionDir,...wanted]=process.argv.slice(2);
assert.ok(extensionDir,'Usage: node locale-tests.mjs extension-dir [language ...]');
const manifest=JSON.parse(await fs.readFile(path.join(extensionDir,'manifest.json'),'utf8'));
const digest=crypto.createHash('sha256').update(Buffer.from(manifest.key,'base64')).digest('hex').slice(0,32);
const ID=[...digest].map(c=>'abcdefghijklmnop'[parseInt(c,16)]).join('');
const output=path.join(root,'locales-'+Date.now());
await fs.mkdir(output,{recursive:true,mode:0o700});
const shots=process.env.SHOTS?path.resolve(process.env.SHOTS):undefined;
if(shots)await fs.mkdir(shots,{recursive:true});
const results=[];
const add=(name,pass,detail={})=>{const r={name,pass,...detail};results.push(r);console.log(JSON.stringify(r));};
const RTL=new Set(['ar','he']);
// Chrome has no interface language for these, so it runs in English whatever the system asks for (Firefox has them). Their
// catalogs are checked by the unit tests; here the browser is only expected to fall back to English.
const NO_CHROME_UI=new Set(['bs','eo','gl','tt']);
// The Logitech discount box is a Taiwanese shop's code: the English and Chinese interfaces show it, no other language does.
const SHOWS_PROMO=new Set(['en','zh_CN','zh_TW']);
const LINK='https://store.logitech.tw/discount/LOGITIM';
// Whether the box is out of sight: hidden, not drawn, no height.
const PROMO_GONE=`(()=>{const s=document.getElementById('promo');return {hidden:s.hidden,display:getComputedStyle(s).display,height:s.getBoundingClientRect().height}})()`;
const isGone=(s)=>s.hidden===true&&s.display==='none'&&s.height===0;
const all=languages(extensionDir);
const todo=wanted.length?wanted:all;
for(const language of todo)assert.ok(all.includes(language),'the extension has no language '+language);

// What a page shows for every marked element, read in the page.
const READ=`(()=>{
 const text=(n)=>n.textContent;
 return {
  lang:document.documentElement.lang,dir:document.documentElement.dir,title:document.title,
  marked:[...document.querySelectorAll('[data-i18n]')].map(n=>({key:n.dataset.i18n,text:text(n)})),
  rich:[...document.querySelectorAll('[data-i18n-rich]')].map(n=>({key:n.dataset.i18nRich,text:text(n),links:[...n.querySelectorAll('a')].map(a=>({text:a.textContent,href:a.href})),bold:[...n.querySelectorAll('strong')].map(b=>b.textContent)})),
  overflowX:document.documentElement.scrollWidth-document.documentElement.clientWidth,
  bodyWidth:document.body.getBoundingClientRect().width
 };
})()`;

for(const language of todo){
 const t0=Date.now();
 const T=loadTexts(extensionDir,language);
 let chrome;
 try{
  chrome=new Chrome(path.join(output,language),{recordEvents:false,fontConfig:process.env.TEST_FONTCONFIG||undefined,locale:language});
  const attach=async(targetId)=>{const {sessionId}=await chrome.send('Target.attachToTarget',{targetId,flatten:true});for(const m of ['Page.enable','Runtime.enable'])await chrome.send(m,{},sessionId);return sessionId;};
  const open=async(url,width,height)=>{
   const {targetId}=await chrome.send('Target.createTarget',{url:'about:blank'});
   const sessionId=await attach(targetId);
   await chrome.send('Emulation.setDeviceMetricsOverride',{width,height,deviceScaleFactor:1,mobile:false},sessionId);
   await chrome.send('Page.navigate',{url},sessionId);
   return {targetId,sessionId};
  };
  // The page is sized to its content for the picture: a capture beyond the viewport puts a right-to-left page in the wrong place.
  const picture=async(page,name)=>{if(!shots)return;
   const size=await chrome.eval(page.sessionId,'({w:innerWidth,h:Math.ceil(document.documentElement.scrollHeight)})');
   await chrome.send('Emulation.setDeviceMetricsOverride',{width:size.w,height:size.h,deviceScaleFactor:1,mobile:false},page.sessionId);
   await delay(150);
   const s=await chrome.send('Page.captureScreenshot',{format:'png'},page.sessionId);await fs.writeFile(path.join(shots,language+'-'+name+'.png'),Buffer.from(s.data,'base64'));};
  const loaded=await chrome.send('Extensions.loadUnpacked',{path:path.resolve(extensionDir)});
  assert.equal(loaded.id,ID);

  // The language Chrome really runs the extension in (it must be the one asked for).
  const probe=await open('chrome-extension://'+ID+'/options.html',860,1700);
  await chrome.wait(probe.sessionId,'(()=>{const s=document.querySelector("#socket-proxy-status");return s&&s.dataset.state})()',20000);
  const ui=await chrome.eval(probe.sessionId,'chrome.i18n.getMessage("@@ui_locale")');
  if(NO_CHROME_UI.has(language)){
   add(language+':chrome-has-no-interface-language-for-this-one-and-falls-back-to-english',ui==='en_US'||ui==='en',{ui});
   const fallback=await chrome.eval(probe.sessionId,READ);
   const en=loadTexts(extensionDir,'en');
   add(language+':the-fallback-pages-show-english-not-keys',fallback.marked.every(m=>m.text===en(m.key)||['timffle_loading','timffle_helper_checking'].includes(m.key)),{wrong:fallback.marked.filter(m=>m.text!==en(m.key)).slice(0,3)});
   await chrome.send('Target.closeTarget',{targetId:probe.targetId});
   continue;
  }
  add(language+':browser-runs-in-this-language',resolveLanguage(extensionDir,ui)===language,{ui});

  // ---- settings page
  const o=await chrome.eval(probe.sessionId,READ);
  const expectLang=ui.replace('_','-');
  add(language+':settings-page-language-and-direction',o.lang===expectLang&&o.dir===(RTL.has(language)?'rtl':'ltr'),{lang:o.lang,dir:o.dir,expectLang});
  const wrong=o.marked.filter(m=>m.text!==T(m.key));
  // The status line and the helper line are rewritten by the page itself once it has read its settings.
  const own=wrong.filter(m=>!['timffle_loading','timffle_helper_checking'].includes(m.key));
  add(language+':settings-page-shows-its-catalog',o.marked.length>=20&&own.length===0,{count:o.marked.length,wrong:own.slice(0,3)});
  const att=o.rich.find(r=>r.key==='timffle_attribution');
  add(language+':attribution-keeps-both-links',!!att&&norm(att.text)===T.plain('timffle_attribution'),{att});
  add(language+':attribution-links-point-to-ruffle-and-timffle',!!att&&att.links.length===2&&att.links[0].text==='Ruffle'&&/^https:\/\/ruffle\.rs\/?$/.test(att.links[0].href)&&att.links[1].text==='Timffle'&&att.links[1].href==='https://github.com/Im-Tim-mI/Timffle/issues',{links:att?.links});
  add(language+':settings-page-fits-its-width',o.overflowX<=0,{overflowX:o.overflowX,bodyWidth:o.bodyWidth});
  add(language+':settings-page-title-is-the-ruffle-translation-or-english',o.title===(loadTexts(extensionDir,language)('settings_page')),{title:o.title});
  await chrome.wait(probe.sessionId,`(()=>{const s=document.querySelector("#socket-helper-status");return s&&s.textContent!==${JSON.stringify(T('timffle_helper_checking'))}})()`,15000);
  const helperText=await chrome.eval(probe.sessionId,'document.querySelector("#socket-helper-status").textContent');
  // No helper is installed in this run: the status is the "not installed" one (or the "unavailable" one), never blank or the key.
  add(language+':helper-status-is-a-catalog-text',[T('timffle_helper_missing'),T('timffle_helper_unavailable'),T('timffle_helper_incompatible')].includes(helperText),{helperText});
  // The helper is missing, so the button that opens the install page is shown, in the language, and inside the page.
  const installButton=await chrome.eval(probe.sessionId,'(()=>{const b=document.querySelector("#socket-helper-install"),r=b.getBoundingClientRect();return {hidden:b.hidden,text:b.textContent,visible:r.width>0&&r.height>0,right:r.right,page:document.documentElement.clientWidth}})()');
  add(language+':settings-page-install-button-follows-the-missing-helper',installButton.hidden===false&&installButton.visible&&installButton.text===T('timffle_helper_notice_button')&&installButton.right<=installButton.page,{installButton});
  // The discount box: shown in English and Chinese only (texts of the language, the banner of the language loaded at its real size, both links exact); out of sight in every other language.
  if(SHOWS_PROMO.has(language)){
  const promo=await chrome.eval(probe.sessionId,`(()=>{const section=document.getElementById('promo'),img=section.querySelector('img'),links=[...section.querySelectorAll('a')];
   return {title:section.querySelector('h2').textContent,note:section.querySelector('.promo-note').textContent,alt:img.alt,src:img.getAttribute('src'),loaded:img.complete&&img.naturalWidth===720&&img.naturalHeight===405,shown:Math.round(img.getBoundingClientRect().width),
    links:links.map(a=>({href:a.href,text:a.textContent,target:a.target,rel:a.rel})),fits:section.getBoundingClientRect().right<=document.documentElement.clientWidth+1}})()`);
  add(language+':settings-page-discount-box',promo.title===T('timffle_promo_title')&&promo.note===T('timffle_promo_disclaimer')&&promo.alt===T('timffle_promo_image_alt')&&promo.src==='images/'+T('timffle_promo_image')&&promo.loaded&&promo.shown>300&&promo.fits&&promo.links.length===2&&promo.links.every(l=>l.href===LINK&&l.target==='_blank'&&l.rel==='noopener noreferrer')&&promo.links[1].text===T('timffle_promo_link'),{promo});
  }else{
   const gone=await chrome.eval(probe.sessionId,PROMO_GONE);
   add(language+':settings-page-has-no-discount-box',isGone(gone),{gone});
  }
  await picture(probe,'settings');
  await chrome.send('Target.closeTarget',{targetId:probe.targetId});

  // ---- question window (opened without a pending question: the "expired" page is shown; the question itself is
  // shown by hand here, because it needs a real website to ask)
  const q=await open('chrome-extension://'+ID+'/prompt.html?id=00000000-0000-4000-8000-000000000000',540,680);
  await chrome.wait(q.sessionId,'!document.getElementById("expired").hidden',20000);
  const p=await chrome.eval(q.sessionId,READ);
  add(language+':question-window-language-and-direction',p.lang===expectLang&&p.dir===(RTL.has(language)?'rtl':'ltr'),{lang:p.lang,dir:p.dir});
  add(language+':question-window-title-is-translated',p.title===T('timffle_prompt_page_title'),{title:p.title});
  add(language+':question-window-shows-its-catalog',p.marked.length>=10&&p.marked.every(m=>m.text===T(m.key)),{count:p.marked.length,wrong:p.marked.filter(m=>m.text!==T(m.key)).slice(0,3)});
  const warn=p.rich.find(r=>r.key==='timffle_prompt_warning');
  add(language+':question-warning-is-bold-in-the-right-place',!!warn&&warn.bold.length===1&&norm(warn.text)===T.plain('timffle_prompt_warning')&&T('timffle_prompt_warning').includes('<1>'+warn.bold[0]+'</1>'),{warn});
  // Show the question itself, with a long made-up website and the page it is embedded in, as the real one would be.
  await chrome.eval(q.sessionId,`(()=>{document.getElementById('prompt-origin').textContent='https://a-long-example-website.example:8443';document.getElementById('prompt-embedded-origin').textContent='https://another-long-example-website.example';document.getElementById('prompt-embedded').hidden=false;document.getElementById('expired').hidden=true;document.getElementById('prompt').hidden=false;})()`);
  await delay(150);
  const m=await chrome.eval(q.sessionId,`(()=>{
   const box=(e)=>{const r=e.getBoundingClientRect();return {x:r.x,y:r.y,w:r.width,h:r.height,right:r.right,bottom:r.bottom}};
   const main=document.getElementById('prompt');
   const buttons=[...document.querySelectorAll('button[data-choice]')].map(b=>({id:b.id,...box(b),clipped:b.scrollWidth>b.clientWidth+1||[...b.children].some(c=>c.scrollWidth>c.clientWidth+1)}));
   return {overflowX:document.documentElement.scrollWidth-document.documentElement.clientWidth,mainWidth:box(main).w,buttons,embedded:document.getElementById('prompt-embedded').textContent.replace(/\\s+/g,' ').trim(),order:buttons.map(b=>b.id+':'+Math.round(b.x))};
  })()`);
  add(language+':question-window-fits-its-width',m.overflowX<=0&&m.buttons.every(b=>!b.clipped&&b.right<=541),{overflowX:m.overflowX,buttons:m.buttons.filter(b=>b.clipped||b.right>541)});
  // In a left-to-right language "Deny" is the first button on the left; in a right-to-left one it is on the right.
  const deny=m.buttons.find(b=>b.id==='deny-once'),allowOnce=m.buttons.find(b=>b.id==='allow-once');
  add(language+':question-buttons-follow-the-reading-direction',RTL.has(language)?deny.x>allowOnce.x:deny.x<allowOnce.x,{deny:deny.x,allow:allowOnce.x});
  add(language+':question-says-where-it-is-embedded',m.embedded===norm(T('timffle_prompt_embedded')+' https://another-long-example-website.example'),{embedded:m.embedded});
  await picture(q,'question');
  await chrome.send('Target.closeTarget',{targetId:q.targetId});

  // ---- "install the socket helper first" window (the same page; shown by hand like the question, because it needs a page that
  // has just tried to connect). The longest system name goes under the button, a long website above it.
  const n=await open('chrome-extension://'+ID+'/prompt.html?id=00000000-0000-4000-8000-000000000000',540,620);
  await chrome.wait(n.sessionId,'!document.getElementById("expired").hidden',20000);
  await chrome.eval(n.sessionId,`(()=>{document.getElementById('helper-origin').textContent='https://a-long-example-website.example:8443';document.getElementById('helper-embedded-origin').textContent='https://another-long-example-website.example';document.getElementById('helper-embedded').hidden=false;document.getElementById('helper-text').textContent=${JSON.stringify(T('timffle_helper_notice_incompatible'))};const f=document.getElementById('helper-for');f.textContent=${JSON.stringify(T('timffle_helper_download_for',['macOS Apple silicon']))};f.hidden=false;document.getElementById('helper-download').hidden=false;document.getElementById('expired').hidden=true;document.getElementById('helper').hidden=false;})()`);
  await delay(150);
  const w=await chrome.eval(n.sessionId,`(()=>{
   const box=(e)=>{const r=e.getBoundingClientRect();return {x:r.x,y:r.y,w:r.width,h:r.height,right:r.right,bottom:r.bottom}};
   const ids=['helper-download','helper-more','helper-close'];
   const controls=ids.map(id=>{const e=document.getElementById(id);return {id,...box(e),clipped:e.scrollWidth>e.clientWidth+1||[...e.children].some(c=>c.scrollWidth>c.clientWidth+1)}});
   const e=document.documentElement;
   return {overflowX:e.scrollWidth-e.clientWidth,height:Math.ceil(document.getElementById('helper').getBoundingClientRect().bottom),controls,title:document.getElementById('helper-title').textContent,embedded:document.getElementById('helper-embedded').textContent.replace(/\\s+/g,' ').trim(),text:document.getElementById('helper-text').textContent,dir:e.dir,order:controls.map(c=>c.id+':'+Math.round(c.y))};
  })()`);
  // A real window has Chrome's title bar above it: what is shown has to fit with that much to spare.
  add(language+':helper-window-fits-its-window',w.overflowX<=0&&w.controls.every(c=>!c.clipped&&c.right<=541&&c.x>=0)&&w.height<=580,{overflowX:w.overflowX,height:w.height,controls:w.controls.filter(c=>c.clipped||c.right>541)});
  add(language+':helper-window-heading-and-embedded-line',w.title===T('timffle_helper_prompt_title')&&w.embedded===norm(T('timffle_prompt_embedded')+' https://another-long-example-website.example')&&w.dir===(RTL.has(language)?'rtl':'ltr'),{title:w.title,embedded:w.embedded,dir:w.dir});
  add(language+':helper-window-buttons-are-one-below-the-other',w.controls[0].y<w.controls[1].y&&w.controls[1].y<w.controls[2].y,{order:w.order});
  await picture(n,'helper-window');
  await chrome.send('Target.closeTarget',{targetId:n.targetId});

  // ---- install page (no helper is installed in this run, so it says so)
  const hp=await open('chrome-extension://'+ID+'/helper.html',760,900);
  await chrome.wait(hp.sessionId,`(()=>{const s=document.getElementById('helper-page-status');return s&&s.dataset.state&&s.textContent!==${JSON.stringify(T('timffle_helper_checking'))}})()`,20000);
  const h=await chrome.eval(hp.sessionId,READ);
  add(language+':install-page-language-and-direction',h.lang===expectLang&&h.dir===(RTL.has(language)?'rtl':'ltr'),{lang:h.lang,dir:h.dir});
  add(language+':install-page-title-is-translated',h.title===T('timffle_helper_page_title'),{title:h.title});
  // The status line is rewritten by the page itself once it has asked the helper.
  const hwrong=h.marked.filter(x=>x.text!==T(x.key)&&x.key!=='timffle_helper_checking');
  const hstatus=await chrome.eval(hp.sessionId,'document.getElementById("helper-page-status").textContent');
  add(language+':install-page-shows-its-catalog',h.marked.length>=6&&hwrong.length===0&&[T('timffle_helper_missing'),T('timffle_helper_unavailable')].includes(hstatus),{count:h.marked.length,wrong:hwrong.slice(0,3),hstatus});
  // One group for each system: its download links (the labels and file names are the same in every language), then its line.
  const groups=await chrome.eval(hp.sessionId,`(async()=>{for(let i=0;i<50&&document.querySelectorAll('.helper-files li').length<7;i++)await new Promise(r=>setTimeout(r,100));return [...document.querySelectorAll('.helper-systems > li')].map(li=>({family:li.dataset.family,links:[...li.querySelectorAll('.helper-files li')].map(item=>({label:item.querySelector('a').textContent,file:item.querySelector('code').textContent,dir:item.querySelector('code').dir})),text:li.querySelector('p').textContent,code:li.querySelector('p code')?.textContent,codeDir:li.querySelector('p code')?.dir}))})()`);
  const linuxCommand='tar xzf timffle-helper-linux-x64.tar.gz && ./timffle-helper-linux-x64';
  add(language+':install-page-lines-keep-their-commands-and-file-names',groups.length===3&&norm(groups[0].text)===T.plain('timffle_helper_step_windows')&&norm(groups[1].text)===T.plain('timffle_helper_step_macos')&&norm(groups[2].text)===T.plain('timffle_helper_step_linux',[linuxCommand])&&groups[2].code===linuxCommand&&groups[2].codeDir==='ltr'&&groups.flatMap(g=>g.links).length===7&&groups.flatMap(g=>g.links).every(l=>l.dir==='ltr'&&/^timffle-helper-(windows|macos|linux)-[a-z0-9]+\.(exe|zip|tar\.gz)$/.test(l.file)),{groups});
  const download=h.rich.find(r=>r.key==='timffle_helper_page_download');
  add(language+':install-page-link-goes-to-the-releases-page',!!download&&download.links.length===1&&download.links[0].href==='https://github.com/Im-Tim-mI/Timffle-Helper/releases/tag/v1.3.0'&&norm(download.text)===T.plain('timffle_helper_page_download'),{download});
  add(language+':install-page-fits-its-width',h.overflowX<=0,{overflowX:h.overflowX});
  // A narrow window (a phone-sized one) too.
  await chrome.send('Emulation.setDeviceMetricsOverride',{width:360,height:900,deviceScaleFactor:1,mobile:false},hp.sessionId);
  await delay(200);
  const narrow=await chrome.eval(hp.sessionId,'document.documentElement.scrollWidth-document.documentElement.clientWidth');
  add(language+':install-page-fits-a-narrow-window',narrow<=0,{narrow});
  await chrome.send('Emulation.setDeviceMetricsOverride',{width:760,height:900,deviceScaleFactor:1,mobile:false},hp.sessionId);
  await picture(hp,'install');
  await chrome.send('Target.closeTarget',{targetId:hp.targetId});

  // ---- popup page (as a tab: the socket section stays hidden without a website tab, but its texts are in place)
  const pop=await open('chrome-extension://'+ID+'/popup.html',320,600);
  await chrome.wait(pop.sessionId,'document.documentElement.lang!==""&&!!document.querySelector(".socket-title")?.textContent',20000);
  const pp=await chrome.eval(pop.sessionId,READ);
  add(language+':popup-shows-its-catalog',pp.marked.length>=2&&pp.marked.every(x=>x.text===T(x.key)),{marked:pp.marked.map(x=>x.key)});
  add(language+':popup-language-and-direction',pp.lang===expectLang&&pp.dir===(RTL.has(language)?'rtl':'ltr'),{lang:pp.lang,dir:pp.dir});
  // No helper is installed in this run, so the popup tells the visitor to install it: in the language, inside the popup, with the accent border on the side the text starts. The popup is 340 px wide whatever the window of this test.
  const notice=await chrome.wait(pop.sessionId,`(()=>{const n=document.getElementById('helper-notice');if(!n||document.readyState!=='complete'||getComputedStyle(n).display==='none'||n.getBoundingClientRect().height===0)return false;const button=document.getElementById('helper-notice-button'),body=document.body.getBoundingClientRect(),r=n.getBoundingClientRect(),b=button.getBoundingClientRect(),css=getComputedStyle(n);const small=document.querySelector('.helper-notice-small'),sr=small.getBoundingClientRect();return {text:document.getElementById('helper-notice-text').textContent,button:button.textContent,forText:document.getElementById('helper-notice-for').textContent,more:document.getElementById('helper-notice-more').textContent,smallInside:sr.left>=r.left-1&&sr.right<=r.right+1,smallSpills:small.scrollWidth>small.clientWidth+1,inside:r.left>=body.left-1&&r.right<=body.right+1&&b.left>=r.left-1&&b.right<=r.right+1,spills:n.scrollWidth>n.clientWidth+1,clipped:button.scrollWidth>button.clientWidth+1,left:css.borderLeftWidth,right:css.borderRightWidth,height:Math.round(r.height)}})()`,15000);
  add(language+':popup-notice-says-the-helper-is-missing',notice.text===T('timffle_helper_notice_missing')&&notice.button===T('timffle_helper_notice_button'),{notice});
  // Under the button: which system it downloads for (this computer's, one of the seven) and the way to the other installers; both stay inside the notice.
  const LABELS=['Windows 64-bit','Windows ARM64','Windows 32-bit','macOS Apple silicon','macOS Intel','Linux x64','Linux ARM64'];
  add(language+':popup-notice-names-the-system-and-the-other-installers',LABELS.some(label=>notice.forText===T('timffle_helper_download_for',[label]))&&notice.more===T('timffle_helper_download_more')&&notice.smallInside&&!notice.smallSpills,{notice});
  add(language+':popup-notice-fits-and-follows-the-reading-direction',notice.inside&&!notice.spills&&!notice.clipped&&(RTL.has(language)?notice.right==='4px'&&notice.left==='0px':notice.left==='4px'&&notice.right==='0px'),{notice});
  // The discount box (English and Chinese only) is open when the popup opens (the popup then scrolls); it shows the texts of the language and can be folded, which gives the room back. Out of sight in every other language.
  if(SHOWS_PROMO.has(language)){
  await picture(pop,'popup-discount');
  const pr=await chrome.eval(pop.sessionId,`(()=>{const d=document.getElementById('promo'),img=d.querySelector('img'),sum=d.querySelector('summary');const bodyHeight=()=>document.body.getBoundingClientRect().height;
   const before={open:d.open,height:bodyHeight(),summaryHeight:Math.round(sum.getBoundingClientRect().height),summaryCut:sum.scrollWidth>sum.clientWidth,summary:sum.textContent,title:d.querySelector('.promo-title').textContent,alt:img.alt,src:img.getAttribute('src'),loaded:img.complete&&img.naturalWidth===720,shown:Math.round(img.getBoundingClientRect().width),note:d.querySelector('.promo-note').textContent,link:d.querySelectorAll('a')[1].textContent,hrefs:[...d.querySelectorAll('a')].map(a=>a.href)};
   d.open=false;
   return new Promise(r=>setTimeout(()=>r({before,shrank:Math.round(before.height-bodyHeight()),open:d.open}),150))})()`);
  add(language+':popup-discount-box-is-open-and-can-be-folded',pr.before.open===true&&pr.before.summaryHeight<=28&&!pr.before.summaryCut&&pr.before.summary===T('timffle_promo_summary')&&pr.before.title===T('timffle_promo_title')&&pr.before.alt===T('timffle_promo_image_alt')&&pr.before.src==='images/'+T('timffle_promo_image')&&pr.before.loaded&&pr.before.shown>200&&pr.before.note===T('timffle_promo_disclaimer')&&pr.before.link===T('timffle_promo_link')&&pr.before.hrefs.every(h=>h===LINK)&&pr.open===false&&pr.shrank>=140,{pr});
  }else{
   const gone=await chrome.eval(pop.sessionId,PROMO_GONE);
   add(language+':popup-has-no-discount-box',isGone(gone),{gone});
  }
  await chrome.send('Target.closeTarget',{targetId:pop.targetId});
 }catch(error){
  add(language+':run',false,{error:String(error?.message??error)});
 }finally{
  await chrome?.close();
 }
 console.error(language+' done in '+Math.round((Date.now()-t0)/1000)+'s');
}
const failed=results.filter(r=>!r.pass);
await fs.writeFile(path.join(output,'results.json'),JSON.stringify(results,null,1));
console.log(JSON.stringify({summary:{languages:todo.length,checks:results.length,failed:failed.length,failures:failed.map(r=>r.name)}}));
process.exit(failed.length?1:0);
