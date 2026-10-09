import {test} from 'node:test';
import assert from 'node:assert/strict';
import {AudioEngine,demoWave,tracks} from '../src/audio';
function fixture(){
 const listeners=new Map<string,()=>void>();let plays=0,pauses=0,creates=0;const revoked:string[]=[];
 const media={src:'',volume:1,currentTime:0,duration:12,play:async()=>{plays++},pause:()=>{pauses++},load:()=>{},addEventListener:(type:string,listener:()=>void)=>listeners.set(type,listener),removeEventListener:(type:string)=>listeners.delete(type)};
 let resume=async()=>{};
 const engine=new AudioEngine(media,()=>resume(),{createObjectURL:()=>`blob:${++creates}`,revokeObjectURL:url=>revoked.push(url)});
 return {engine,media,listeners,revoked,get plays(){return plays},get pauses(){return pauses},resume:(value:()=>Promise<void>)=>{resume=value}};
}
test('switching files revokes previous URL and pauses',()=>{const f=fixture();f.engine.select(new Blob());f.engine.select(new Blob());assert.deepEqual(f.revoked,['blob:1']);assert.equal(f.media.src,'blob:2');assert.equal(f.engine.playing,false)});
test('repeated play pause and replay after ended',async()=>{const f=fixture();f.engine.select(new Blob());for(let i=0;i<4;i++){await f.engine.play();assert.equal(f.engine.playing,true);f.engine.pause();assert.equal(f.engine.playing,false)}await f.engine.play();f.media.currentTime=12;f.listeners.get('ended')!();assert.equal(f.engine.playing,false);await f.engine.play();assert.equal(f.media.currentTime,0)});
test('pause during context resume cancels pending play',async()=>{const f=fixture();f.engine.select(new Blob());let resolve!:()=>void;f.resume(()=>new Promise<void>(r=>resolve=r));const playing=f.engine.play();f.engine.pause();resolve();await playing;assert.equal(f.plays,0);assert.equal(f.engine.playing,false)});
test('file switch during resume does not play old request',async()=>{const f=fixture();f.engine.select(new Blob());let resolve!:()=>void;f.resume(()=>new Promise<void>(r=>resolve=r));const playing=f.engine.play();f.engine.select(new Blob());resolve();await playing;assert.equal(f.plays,0)});
test('rejected playback leaves paused and can retry',async()=>{const f=fixture();f.engine.select(new Blob());f.media.play=async()=>{throw Error('decode')};await assert.rejects(f.engine.play());assert.equal(f.engine.playing,false);f.media.play=async()=>{};await f.engine.play();assert.equal(f.engine.playing,true)});
test('dispose is idempotent and cancels pending resume',async()=>{const f=fixture();f.engine.select(new Blob());let resolve!:()=>void;f.resume(()=>new Promise<void>(r=>resolve=r));const playing=f.engine.play();f.engine.dispose();f.engine.dispose();resolve();await playing;assert.deepEqual(f.revoked,['blob:1']);assert.equal(f.listeners.size,0);assert.equal(f.media.src,'');assert.equal(f.plays,0)});
test('resume is requested for each play',async()=>{const f=fixture();let count=0;f.resume(async()=>{count++});f.engine.select(new Blob());await f.engine.play();f.engine.pause();await f.engine.play();assert.equal(count,2)});
test('demo is a valid 12-second PCM WAV',async()=>{const blob=demoWave();const v=new DataView(await blob.arrayBuffer());assert.equal(blob.type,'audio/wav');assert.equal(v.getUint32(24,true),24000);assert.equal(v.getUint32(40,true),12*24000*2);assert.equal(blob.size,576044)});

test('four original demo arrangements have distinct PCM and valid headers',async()=>{const waves=await Promise.all(tracks.map(t=>demoWave(t.id).arrayBuffer()));assert.equal(waves.length,4);for(const wave of waves){const view=new DataView(wave);assert.equal(view.getUint32(24,true),24000);assert.equal(wave.byteLength,576044);}for(let i=0;i<waves.length;i++)for(let j=i+1;j<waves.length;j++)assert.notDeepEqual(Buffer.from(waves[i]),Buffer.from(waves[j]));});
test('unknown demo track is rejected',()=>{assert.throws(()=>demoWave('missing'))});
