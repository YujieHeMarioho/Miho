import {test} from 'node:test';
import assert from 'node:assert/strict';
import {bandFeatures,modeTarget} from '../src/modes';
test('silence is idle in both modes',()=>{const f=bandFeatures(new Uint8Array(512),48000,1024);assert.deepEqual(f,{bass:0,voice:0,center:0});for(const mode of ['singer','music'] as const)assert.equal(modeTarget(mode,f,0).drive,0)});
test('low frequency drives music, not singer band',()=>{const spectrum=new Uint8Array(512);spectrum[2]=255;const f=bandFeatures(spectrum,48000,1024);assert.equal(modeTarget('singer',f,0).drive,0);assert.ok(modeTarget('music',f,0).drive>.3)});
test('mid-band energy drives singer without pretending to separate voice',()=>{const spectrum=new Uint8Array(512);spectrum[18]=255;const f=bandFeatures(spectrum,48000,1024);assert.ok(modeTarget('singer',f,0).drive>0);assert.equal(modeTarget('music',f,0).drive,0)});
test('spectrum center changes singer target direction',()=>{const a=new Uint8Array(512),b=new Uint8Array(512);a[10]=255;b[50]=255;assert.ok(modeTarget('singer',bandFeatures(a,48000,1024),0).tilt<0);assert.ok(modeTarget('singer',bandFeatures(b,48000,1024),0).tilt>0)});
test('repeated switches keep bounded targets with same input',()=>{const spectrum=new Uint8Array(512).fill(255),f=bandFeatures(spectrum,48000,1024);for(let i=0;i<100;i++){const t=modeTarget(i%2?'singer':'music',f,1);assert.ok(t.drive>=0&&t.drive<=1);assert.ok(Math.abs(t.tilt)<=1)}});
