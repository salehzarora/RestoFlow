import test from 'node:test';
import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { welcomeVideoResponseEvidence, welcomeVideoCoverage } from './welcome-video-evidence.mjs';
const source=Buffer.from([0,1,2,3,4,5,6,7]);
const url='https://oqmevrndtivqxgyvcmwy.supabase.co/storage/v1/object/public/storefront-welcome-videos/'+ 'a'.repeat(32)+'/'+createHash('sha256').update(source).digest('hex')+'.mp4';
const actual=(args={})=>welcomeVideoResponseEvidence({url,status:200,contentRange:null,body:source,...args},source);
test('complete and ranged original browser bytes prove the whole resource only with complete coverage',()=>{
 const whole=actual(); assert.equal(welcomeVideoCoverage([whole],source.length),true);
 const first=actual({status:206,contentRange:'bytes 0-3/8',body:source.subarray(0,4)});
 const last=actual({status:206,contentRange:'bytes 4-7/8',body:source.subarray(4)});
 assert.equal(welcomeVideoCoverage([first],8),false);assert.equal(welcomeVideoCoverage([last,first],8),true);
 assert.equal(welcomeVideoCoverage([],8),false);
 for(const bad of [null,{}, {...whole,first:-1},{...whole,bytes:0},{...whole,status:0},{...whole,sha256:null}])assert.equal(welcomeVideoCoverage([bad],8),false);
});
test('aborted, bodiless, incomplete, wrong-byte and range-mismatched responses remain failures',()=>{
 for(const body of [null,undefined,Buffer.alloc(0),source.subarray(0,7),Buffer.from([9,1,2,3,4,5,6,7])]) assert.throws(()=>actual({body}));
 for(const status of [0,204,302,401,500])assert.throws(()=>actual({status}));
 for(const contentRange of [null,'bytes 0-7/9','bytes 1-7/8','bytes 7-0/8','bytes 0-8/8','bytes 00-7/8'])assert.throws(()=>actual({status:206,contentRange}));
 assert.throws(()=>actual({contentRange:'bytes 0-7/8'}));
});
test('a different public object or private source is not accepted from HTTP200 alone',()=>{
 for(const value of [url.replace('https://oqmevrndtivqxgyvcmwy.supabase.co','https://other.supabase.co'),url.replace('https://','https://user@'),url.replace('https://','https://user:password@'),url.replace('.mp4','.webm'),url.replace('/public/','/authenticated/'),url+'?download=1',url.replace(/a{32}/,'a'.repeat(31)),url.replace(/([0-9a-f]{64})\.mp4$/,'b'.repeat(64)+'.mp4')])assert.throws(()=>actual({url:value}));
});
