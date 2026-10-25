/** Contract001: Unicode15.1/UAX29r43, scalar offsets; no host ICU or normalization. */
import { GRAPHEME_RANGES } from './grapheme-data';
export function scalarValues(text: string): number[] | null {
  const result: number[]=[];
  for(let i=0;i<text.length;i++) {
    const c=text.charCodeAt(i);
    if(c>=0xd800 && c<=0xdbff) { const d=text.charCodeAt(++i); if(!(d>=0xdc00 && d<=0xdfff)) return null; result.push(0x10000+(c-0xd800)*1024+d-0xdc00); }
    else { if(c>=0xdc00 && c<=0xdfff) return null; result.push(c); }
  }
  return result;
}
function has(cp:number,key:string):boolean {
  const ranges=GRAPHEME_RANGES[key]??[]; let lo=0,hi=ranges.length/2-1;
  while(lo<=hi) { const mid=(lo+hi)>>1; if(cp<ranges[mid*2])hi=mid-1;else if(cp>ranges[mid*2+1])lo=mid+1;else return true; }
  return false;
}
function gcb(cp:number):string {
  if(cp>=0xac00 && cp<=0xd7a3)return (cp-0xac00)%28===0?'LV':'LVT';
  for(const key of ['CR','LF','Control','L','V','T','Extend','ZWJ','Regional_Indicator','Prepend','SpacingMark'])if(has(cp,key))return key;
  return 'Other';
}
export function graphemeBoundaries(text:string):number[]|null {
  const c=scalarValues(text);if(c===null)return null; const g=c.map(gcb),out=[0];
  for(let i=1;i<c.length;i++) {
    const a=g[i-1],b=g[i];let join=false;
    if(a==='CR' && b==='LF')join=true; // GB3
    else if(['Control','CR','LF'].includes(a)||['Control','CR','LF'].includes(b))join=false; // GB4/5
    else if(a==='L'&&['L','V','LV','LVT'].includes(b))join=true; // GB6
    else if(['LV','V'].includes(a)&&['V','T'].includes(b))join=true; // GB7
    else if(['LVT','T'].includes(a)&&b==='T')join=true; // GB8
    else if(['Extend','ZWJ','SpacingMark'].includes(b)||a==='Prepend')join=true; // GB9/9a/9b
    else {
      if(has(c[i],'InCB_Consonant')) { let j=i-1,link=false;while(j>=0&&(has(c[j],'InCB_Extend')||has(c[j],'InCB_Linker'))){link ||= has(c[j],'InCB_Linker');j--;}join=link&&j>=0&&has(c[j],'InCB_Consonant'); } // GB9c
      if(!join&&a==='ZWJ'&&has(c[i],'Extended_Pictographic')) {let j=i-2;while(j>=0&&g[j]==='Extend')j--;join=j>=0&&has(c[j],'Extended_Pictographic');} // GB11
      if(!join&&a==='Regional_Indicator'&&b===a){let n=0,j=i-1;while(j>=0&&g[j--]==='Regional_Indicator')n++;join=n%2===1;} // GB12/13
    }
    if(!join)out.push(i);
  }
  if(c.length)out.push(c.length);return out;
}
export function isContentSpace(cp:number):boolean { return cp===0x20||cp===0x85||cp===0xa0||cp===0x1680||(cp>=0x2000&&cp<=0x200a)||[0x2028,0x2029,0x202f,0x205f,0x3000,0xfeff].includes(cp); }
export function normalizeContentText(text:string|null,max:number,legacy=false):string|null {
  if(!Number.isSafeInteger(max)||max<1)throw new Error('content_text_invalid');
  if(text===null)return null;const c=scalarValues(text);if(c===null)throw new Error('content_text_invalid');
  if(c.some(p=>p<=0x1f||p===0x7f||(!legacy&&((p>=0x80&&p<=0x9f)||p===0x2028||p===0x2029))))throw new Error('content_text_invalid');
  let start=0,end=c.length;while(start<end&&isContentSpace(c[start]))start++;while(end>start&&isContentSpace(c[end-1]))end--;
  if(end-start>max)throw new Error('content_text_invalid');return end===start?null:String.fromCodePoint(...c.slice(start,end));
}
export function contentTextValid(text:string|null,max:number,legacy=false):boolean {try{return normalizeContentText(text,max,legacy)===text;}catch{return false;}}
export function heroFormatValid(text:string|null,start:number|null,end:number|null,breakBefore:number|null):boolean {
  if(start===null&&end===null&&breakBefore===null)return true;
  if(text===null||!contentTextValid(text,120,true))return false;
  const c=scalarValues(text)!;if(c.some(p=>[0x85,0x2028,0x2029].includes(p)))return false;
  const bounds=new Set(graphemeBoundaries(text)!);
  if((start===null)!==(end===null))return false;
  if(start!==null&&end!==null) {if(!Number.isSafeInteger(start)||!Number.isSafeInteger(end)||start<0||end<=start||end>c.length||end-start>60||isContentSpace(c[start])||isContentSpace(c[end-1])||(start>0&&!isContentSpace(c[start-1]))||(end<c.length&&!isContentSpace(c[end]))||!bounds.has(start)||!bounds.has(end))return false;}
  if(breakBefore!==null){if(!Number.isSafeInteger(breakBefore)||breakBefore<1||breakBefore>=c.length||isContentSpace(c[breakBefore])||!isContentSpace(c[breakBefore-1])||!bounds.has(breakBefore)||(start!==null&&end!==null&&start<breakBefore&&breakBefore<end))return false;}
  return true;
}
export function utf16SelectionToCodepoints(text:string,start:number,end:number):readonly[number,number]|null {
  const c=scalarValues(text);if(c===null||!Number.isSafeInteger(start)||!Number.isSafeInteger(end))return null;
  const units=[0];for(const cp of c)units.push(units.at(-1)!+(cp>0xffff?2:1));const a=units.indexOf(Math.min(start,end)),b=units.indexOf(Math.max(start,end));return a<0||b<0?null:[a,b];
}
