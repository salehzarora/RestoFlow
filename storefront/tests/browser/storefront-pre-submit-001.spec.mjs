// Actual LIVE decoder + synthetic loopback backend. Never seed carts or submit.
// Intended tracked addition: this SPEC, reusing the existing cart helper API.
import {settings,boundaryEvidence,childEnvironment} from './helpers/cart-navigation-boundary-001.mjs';
import {startFixture,guardBrowser,cartSnapshot,privacyState,appOrigin,SLUGS,ITEM,REQUIRED,EXTRA,NOTE,EXPECTED_PRICE,itemName,messages} from './helpers/cart-navigation-001.mjs';
import {createRequire} from 'node:module';
import {mkdirSync,existsSync,writeFileSync,readFileSync} from 'node:fs';
import path from 'node:path';
import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
if(settings.phase!=='test'||existsSync(settings.outputDir))throw Error('fresh_presubmit_output_required');
mkdirSync(settings.outputDir,{recursive:true});
const require=createRequire(path.join(settings.sourceDir,'package.json'));
const {chromium,expect}=require('@playwright/test');
const CUSTOMER={fullName:'Synthetic Browser Customer',phone:'0500000000',orderNotes:'Synthetic order note only ملاحظة בלבד'};
const unsupported={ar:'طلب الاستلام غير متاح في هذا المتصفح.',he:'הזמנת איסוף אינה זמינה בדפדפן זה.',en:'Pickup checkout is unavailable in this browser.'};
const rows=[];let fixture,browser;
function save(name,value){writeFileSync(path.join(settings.outputDir,name),JSON.stringify(value,null,2)+'\n',{flag:'wx'});}
async function noPersistence(page){const state=await privacyState(page);assert.deepEqual(state.cartKeys,[]);assert.ok(state.values.every(x=>x.value===null));assert.deepEqual(await page.evaluate(()=>window.__preSubmitWriteAttempts??[]),[]);return state;}
async function noDocument(page,before,navigations,index){assert.deepEqual(await page.evaluate(()=>({token:window.__preSubmitSentinel??null,timeOrigin:performance.timeOrigin})),before);assert.deepEqual(navigations.slice(index),[]);}
async function expectedPath(page,pathname){await page.waitForURL(url=>url.pathname===pathname,{timeout:12000});assert.equal(new URL(page.url()).pathname,pathname);}
async function visibleCart(page){await expect(page.locator('[data-sf-screen="cart"]:not([data-sf-pending])')).toBeVisible();await expect(page.locator('[data-sf-pending]')).toHaveCount(0);}
async function checkLine(page,identity){
 const line=page.locator('[data-sf-cart-line]');await expect(line).toHaveCount(1);
 await expect(line.locator('[data-sf-item]')).toHaveAttribute('data-sf-item',ITEM);await expect(line.locator('[data-sf-stepper] > span')).toHaveText('2');
 for(const text of [itemName(),NOTE,'Synth Classic','Synth Cheese',EXPECTED_PRICE])await expect(line).toContainText(text);
 const value=(await cartSnapshot(page,'[data-sf-cart-line]'))[0];if(identity)assert.equal(value.lineId,identity);return value;
}
async function addProduct(page){
 await page.locator(`#sf-menu [data-sf-item="${ITEM}"]`).click();const sheet=page.locator('[data-sf-sheet="product"]');await expect(sheet).toBeVisible();
 await expect(sheet.locator('h2')).toHaveText(itemName());await sheet.getByRole('radio').filter({hasText:'Synth Classic'}).click();await sheet.getByRole('checkbox').filter({hasText:'Synth Cheese'}).click();
 await sheet.locator('textarea').fill(NOTE);await sheet.locator('[data-sf-step="inc"]').click();await expect(sheet.locator('[data-sf-cta="product"]')).toHaveAttribute('aria-disabled','false');await sheet.locator('[data-sf-cta="product"]').click();await expect(sheet).toHaveCount(0);await expect(page.locator('[data-sf-cart-trigger] b')).toHaveText('2');
}
async function menuToCart(page,width,locale){
 if(width===1440){await page.locator('[data-sf-cart-trigger]').click();const dialog=page.locator('dialog[open]');await expect(dialog).toBeVisible();const edit=dialog.locator('a').filter({hasText:messages[locale].edit});await expect(edit).toBeVisible();await edit.focus();await edit.press('Enter');}
 else{const dock=page.locator('[data-sf-dock-cta="cart"]');await expect(dock).toBeVisible();await dock.click();}
 await visibleCart(page);return checkLine(page);
}
async function routeSettled(page,start){
 await page.waitForFunction(initial=>location.pathname!==initial,start,{timeout:12000});
 const trace=[];let stable=0,last='';
 for(let i=0;i<20;i++){const value=await page.evaluate(()=>({path:location.pathname,pending:document.querySelectorAll('[data-sf-pending]').length,screens:[...document.querySelectorAll('[data-sf-screen]')].map(x=>x.getAttribute('data-sf-screen'))}));trace.push(value);stable=value.path===last&&value.pending===0?stable+1:0;last=value.path;if(stable>=3)break;await page.waitForTimeout(100);}
 return trace;
}
async function oneJourney(locale,width,entry,canonical=false,full=true){
 const key=`${locale}-${width}-${entry}${canonical?'-canonical':''}`;
 const row={key,locale,width,entry,canonical,sourceSha:settings.sourceSha,sourceTree:settings.sourceTree,status:'FAIL',facts:{}};
 const context=await browser.newContext({viewport:{width,height:900},serviceWorkers:'block',locale,reducedMotion:'reduce'});
 const denied=await guardBrowser(context);
 await context.addInitScript(()=>{window.__preSubmitWriteAttempts=[];document.addEventListener('submit',event=>{event.preventDefault();event.stopImmediatePropagation();window.__preSubmitWriteAttempts.push('form-submit');},true);document.addEventListener('click',event=>{if(event.target instanceof Element&&event.target.closest('[data-sf-cta="send"]')){event.preventDefault();event.stopImmediatePropagation();window.__preSubmitWriteAttempts.push('send-activation');}},true);});
 const page=await context.newPage(),documents=[],requests=[],errors=[];
 page.on('request',request=>{const url=new URL(request.url());requests.push({path:url.pathname,method:request.method(),type:request.resourceType(),navigation:request.isNavigationRequest()});if(request.isNavigationRequest()&&request.frame()===page.mainFrame())documents.push(url.pathname);});
 page.on('pageerror',error=>errors.push(error.message));
 try{
  const prefix=canonical?'':`/${locale}`,base=`${prefix}/s/${SLUGS[0]}`;
  row.facts.menuStart=`${base}/menu`;await page.goto(`${appOrigin}${base}/menu`,{waitUntil:'domcontentloaded'});await expect(page.locator('html')).toHaveAttribute('lang',locale);await expect(page.locator('html')).toHaveAttribute('dir',locale==='en'?'ltr':'rtl');await addProduct(page);await noPersistence(page);
  let identity;
  if(entry==='cart-continue'){identity=(await menuToCart(page,width,locale)).lineId;}
  else{assert.equal(width,1440);await page.locator('[data-sf-cart-trigger]').click();await expect(page.locator('dialog[open]')).toBeVisible();const lines=await cartSnapshot(page,'dialog[open] [data-sf-aside-line]');assert.equal(lines.length,1);assert.equal(lines[0].itemId,ITEM);assert.equal(lines[0].qty,'2');identity=lines[0].lineId;}
  const cta=entry==='cart-continue'?page.locator('[data-sf-cta="cart-checkout"]'):page.locator('dialog[open] [data-sf-aside-cta="checkout"]');
  await expect(cta).toBeVisible();await expect(cta).not.toHaveAttribute('aria-disabled','true');
  row.facts.ctaBefore=await cta.evaluate(element=>({tag:element.tagName,type:element.getAttribute('type'),href:element.getAttribute('href'),ariaDisabled:element.getAttribute('aria-disabled'),text:element.textContent?.replace(/\s+/g,' ').trim()}));
  row.facts.beforePath=new URL(page.url()).pathname;row.facts.identity=identity;row.facts.beforeDocument=await page.evaluate(token=>{window.__preSubmitSentinel=token;return{token,timeOrigin:performance.timeOrigin};},`synthetic-${key}`);
  const docIndex=documents.length,requestIndex=requests.length;await cta.click();row.facts.routeTimeline=await routeSettled(page,row.facts.beforePath);
  row.facts.actualDestination=new URL(page.url()).pathname;row.facts.documents=documents.slice(docIndex);row.facts.routerRequests=requests.slice(requestIndex);row.facts.afterDocument=await page.evaluate(()=>({token:window.__preSubmitSentinel??null,timeOrigin:performance.timeOrigin}));
  row.facts.detailsVisible=await page.locator('[data-sf-screen="checkout"][data-sf-web-order="details"]:not([data-sf-pending])').isVisible();row.facts.cartAfter=await cartSnapshot(page,'[data-sf-cart-line]');const detailsFooter=page.locator('[data-sf-cta="to-review"]');row.facts.detailsFooter=await detailsFooter.count()?await detailsFooter.textContent():null;row.facts.unsupportedVisible=(await page.locator('body').innerText()).includes(unsupported[locale]);row.facts.privacy=await noPersistence(page);
  // Evidence is saved before desired-contract assertions. No URL is forced.
  save(`${key}-arrival.json`,row.facts);
  assert.equal(row.facts.unsupportedVisible,false,'actual live checkout must not be unsupported; this is not route-regression proof');
  assert.equal(row.facts.actualDestination,`${base}/checkout`,'checkout must preserve the current locale root');
  assert.equal(row.facts.detailsVisible,true,'actual details screen must be visible after navigation');
  assert.ok(row.facts.detailsFooter?.includes(EXPECTED_PRICE),'details footer must retain the live quote');
  await noDocument(page,row.facts.beforeDocument,documents,docIndex);await expect(page.locator('[data-sf-pending]')).toHaveCount(0);
  if(entry==='header-direct'){
   await expect(page.locator('dialog[open]')).toHaveCount(0);
   await expect.poll(()=>page.evaluate(()=>{const style=getComputedStyle(document.body);return ['hidden','clip'].includes(style.overflow)||['hidden','clip'].includes(style.overflowY);})).toBe(false);
   row.facts.headerDialogAfter={openCount:await page.locator('dialog[open]').count(),bodyOverflow:await page.evaluate(()=>({overflow:getComputedStyle(document.body).overflow,overflowY:getComputedStyle(document.body).overflowY}))};
  }
  if(full){
   // Details intentionally does not render lines. Use its real back link.
   row.facts.detailsBackHref=await page.locator('[data-sf-back]').getAttribute('href');await page.locator('[data-sf-back]').click();await expectedPath(page,`${base}/cart`);await visibleCart(page);await checkLine(page,identity);await noDocument(page,row.facts.beforeDocument,documents,docIndex);
   await page.locator('[data-sf-item][data-sf-line]').click();const sheet=page.locator('[data-sf-sheet="product"]');await expect(sheet).toBeVisible();await expect(sheet.locator('textarea')).toHaveValue(NOTE);await expect(sheet.getByRole('radio').filter({hasText:'Synth Classic'})).toHaveAttribute('aria-checked','true');await expect(sheet.getByRole('checkbox').filter({hasText:'Synth Cheese'})).toHaveAttribute('aria-checked','true');await page.keyboard.press('Escape');await expect(sheet).toHaveCount(0);await checkLine(page,identity);
   await page.locator('[data-sf-cta="cart-checkout"]').click();await expectedPath(page,`${base}/checkout`);await expect(page.locator('[data-sf-web-order="details"]:not([data-sf-pending])')).toBeVisible();
   await page.locator('[data-sf-field="fullName"]').fill(CUSTOMER.fullName);await page.locator('[data-sf-field="phone"]').fill(CUSTOMER.phone);await page.locator('[data-sf-field="orderNotes"]').fill(CUSTOMER.orderNotes);const continueButton=page.locator('[data-sf-cta="to-review"]');await expect(continueButton).not.toHaveAttribute('aria-disabled','true');await continueButton.click();
   const review=page.locator('[data-sf-screen="review"][data-sf-live-checkout]');await expectedPath(page,`${base}/review`);await expect(review).toBeVisible();
   for(const text of [itemName(),NOTE,'Synth Classic','Synth Cheese',EXPECTED_PRICE,CUSTOMER.fullName,CUSTOMER.phone,CUSTOMER.orderNotes])await expect(review).toContainText(text);await expect(review.locator('[data-sf-item-note]')).toHaveText(NOTE);await expect(review.locator('[data-sf-cta="send"]')).toBeVisible();
   row.facts.review={path:new URL(page.url()).pathname,text:await review.innerText(),sendNeverActivated:true};
   await review.locator('[data-sf-edit="contact"]').click();await expectedPath(page,`${base}/checkout`);await expect(page.locator('[data-sf-web-order="details"]:not([data-sf-pending])')).toBeVisible();await expect(page.locator('[data-sf-field="fullName"]')).toHaveValue(CUSTOMER.fullName);await expect(page.locator('[data-sf-field="phone"]')).toHaveValue(CUSTOMER.phone);await expect(page.locator('[data-sf-field="orderNotes"]')).toHaveValue(CUSTOMER.orderNotes);
   await page.locator('[data-sf-back]').click();await expectedPath(page,`${base}/cart`);await visibleCart(page);await checkLine(page,identity);
   await page.locator('[data-sf-back]').click();await expectedPath(page,`${base}/menu`);await expect(page.locator('#sf-menu')).toBeVisible();await expect(page.locator('[data-sf-cart-trigger] b')).toHaveText('2');
   await noDocument(page,row.facts.beforeDocument,documents,docIndex);await noPersistence(page);
   // Re-enter through real menu/cart controls; the original in-memory draft survives.
   await menuToCart(page,width,locale);await expectedPath(page,`${base}/cart`);await checkLine(page,identity);
   await page.locator('[data-sf-cta="cart-checkout"]').click();await expectedPath(page,`${base}/checkout`);await expect(page.locator('[data-sf-web-order="details"]:not([data-sf-pending])')).toBeVisible();await expect(page.locator('[data-sf-cta="to-review"]')).toContainText(EXPECTED_PRICE);
   await expect(page.locator('[data-sf-field="fullName"]')).toHaveValue(CUSTOMER.fullName);await expect(page.locator('[data-sf-field="phone"]')).toHaveValue(CUSTOMER.phone);await expect(page.locator('[data-sf-field="orderNotes"]')).toHaveValue(CUSTOMER.orderNotes);
   row.facts.detailsReentry={path:new URL(page.url()).pathname,fullName:await page.locator('[data-sf-field="fullName"]').inputValue(),phone:await page.locator('[data-sf-field="phone"]').inputValue(),orderNotes:await page.locator('[data-sf-field="orderNotes"]').inputValue(),footer:await page.locator('[data-sf-cta="to-review"]').textContent(),identity};
   await noDocument(page,row.facts.beforeDocument,documents,docIndex);await noPersistence(page);
  }
  assert.deepEqual(denied,[]);assert.deepEqual(errors,[]);row.status='PASS';
 }catch(error){row.failure=String(error.message).slice(0,2500);row.blockedOrUnsupported=!!row.facts.unsupportedVisible||!row.facts.ctaBefore;await page.screenshot({path:path.join(settings.outputDir,`${key}-failure.png`),fullPage:false}).catch(()=>undefined);}
 finally{row.denied=denied;row.pageErrors=errors;row.allDocumentRequests=documents;row.requestFacts=requests;row.finalPath=new URL(page.url()).pathname;row.sendActivations=await page.evaluate(()=>window.__preSubmitWriteAttempts??[]).catch(()=>['page-unavailable']);save(`${key}.json`,row);await context.close();}
 return row;
}
try{
 fixture=await startFixture();browser=await chromium.launch({executablePath:settings.chromiumPath,headless:true,env:childEnvironment(),args:['--host-resolver-rules=MAP * ~NOTFOUND, EXCLUDE 127.0.0.1','--disable-background-networking','--disable-component-update','--no-first-run']});
 if(settings.mode==='old-desktop'){
  // Each original entry receives a fresh context even if the preceding fails.
  for(const entry of ['cart-continue','header-direct'])rows.push(await oneJourney('ar',1440,entry,false,false));
 }else{
  for(const locale of ['ar','he','en'])for(const width of [390,1440]){
   const primary=await oneJourney(locale,width,'cart-continue',false,true);const extras=[];
   if(width===1440)extras.push(await oneJourney(locale,width,'header-direct',false,true));
   if(locale==='ar')extras.push(await oneJourney(locale,width,'cart-continue',true,true));
   rows.push({key:`${locale}-${width}`,locale,width,status:[primary,...extras].every(x=>x.status==='PASS')?'PASS':'FAIL',primary,controls:extras});
  }
 }
 const allPass=rows.every(x=>x.status==='PASS');save('RESULT.json',{status:allPass?'PASS':settings.mode==='old-desktop'?'FAIL_OLD_DESIRED_CONTRACT':'FAIL',mode:settings.mode,sourceSha:settings.sourceSha,sourceTree:settings.sourceTree,runtimeArtifactSha256:settings.runtimeArtifactSha256,rows,rowsCount:rows.length,browserVersion:browser.version(),boundaryEvidence,specSha256:createHash('sha256').update(readFileSync(new URL(import.meta.url))).digest('hex'),mappingProof:fixture.mappingProof,rpcCalls:fixture.calls,rejectedRpcCalls:fixture.rejected,submitNeverActivated:true,browserOrBackendWrites:0,cartSeeding:false,localStoragePersistenceAdded:false,realDatabase:false,sourceMode:'actual LIVE decoder with synthetic loopback v4 backend'});process.exitCode=allPass?0:1;
}catch(error){save('INFRASTRUCTURE-FAILURE.json',{status:'FAIL',message:String(error.message).slice(0,1500),fixtureEvidence:error.fixtureEvidence??null});process.exitCode=1;}
finally{if(browser)await browser.close();if(fixture){const output=fixture.output();await fixture.stop();save('OWNED-CLEANUP.json',{stopReturned:true,nextPid:fixture.processId,appPort:settings.appPort,rpcPort:settings.rpcPort,syntheticServerOutput:output,independentPidAndListenerReadbackRequired:true});}}
