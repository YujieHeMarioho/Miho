export interface MediaPort {
 src: string; volume: number; currentTime: number; duration: number;
 play(): Promise<void>; pause(): void; load(): void;
 addEventListener(type: string, listener: () => void): void;
 removeEventListener(type: string, listener: () => void): void;
}
export class AudioEngine {
 playing = false;
 loaded = false;
 private revision = 0;
 private url?: string;
 private disposed = false;
 private ended = () => { this.playing = false; this.changed(); };
 constructor(public media: MediaPort, private resume: () => Promise<void>,
   private urls: {createObjectURL(blob: Blob): string; revokeObjectURL(url: string): void},
   private changed: () => void = () => {}) {
   media.addEventListener('ended', this.ended);
 }
 select(blob: Blob) {
   if (this.disposed) throw new Error('播放器已关闭');
   this.pause();
   this.media.src = '';
   this.media.load();
   if (this.url) this.urls.revokeObjectURL(this.url);
   this.url = this.urls.createObjectURL(blob);
   this.media.src = this.url; this.media.load(); this.loaded = true;
   this.changed();
 }
 async play() {
   if (!this.loaded || this.disposed) return;
   const revision = ++this.revision;
   await this.resume();
   if (revision !== this.revision || this.disposed) return;
   if (Number.isFinite(this.media.duration) && this.media.currentTime >= this.media.duration) this.media.currentTime = 0;
   try {
     await this.media.play();
     if (revision !== this.revision || this.disposed) { if (!this.playing) this.media.pause(); return; }
     this.playing = true; this.changed();
   } catch (error) {
     if (revision === this.revision) { this.playing = false; this.changed(); throw error; }
   }
 }
 pause() { ++this.revision; this.media.pause(); this.playing = false; this.changed(); }
 dispose() {
   if (this.disposed) return;
   this.pause(); this.disposed = true;
   this.media.removeEventListener('ended', this.ended);
   this.media.src = ''; this.media.load();
   if (this.url) this.urls.revokeObjectURL(this.url);
   this.url = undefined; this.loaded = false;
 }
}
export const tracks = [
 {id:'little',name:'Little Miho',style:'轻快旋律 · 120 BPM',bpm:120,notes:[261.63,329.63,392,329.63,293.66,349.23,440,392]},
 {id:'night',name:'月光慢步',style:'柔和氛围 · 80 BPM',bpm:80,notes:[220,261.63,329.63,293.66,261.63,220,196,246.94]},
 {id:'pulse',name:'霓虹脉冲',style:'电子鼓点 · 140 BPM',bpm:140,notes:[130.81,130.81,164.81,196,130.81,146.83,164.81,196]},
 {id:'voice',name:'合成唱句',style:'元音音色 · 无真实歌声',bpm:90,notes:[220,246.94,293.66,329.63,293.66,261.63,246.94,220]}
] as const;
// Original synthesized melodies, not commercial recordings or actual singing.
export function demoWave(id: string = 'little'): Blob {
 const track=tracks.find(t=>t.id===id);
 if(!track)throw new Error('Unknown demo track');
 const rate = 24000, seconds = 12, count = rate * seconds;
 const buffer = new ArrayBuffer(44 + count * 2), view = new DataView(buffer);
 const text = (at: number, value: string) => [...value].forEach((c, i) => view.setUint8(at+i,c.charCodeAt(0)));
 text(0,'RIFF'); view.setUint32(4,36+count*2,true); text(8,'WAVE'); text(12,'fmt ');
 view.setUint32(16,16,true); view.setUint16(20,1,true); view.setUint16(22,1,true);
 view.setUint32(24,rate,true); view.setUint32(28,rate*2,true); view.setUint16(32,2,true); view.setUint16(34,16,true);
 text(36,'data'); view.setUint32(40,count*2,true);
 const beat=60/track.bpm;
 for(let i=0;i<count;i++) {
   const t=i/rate, age=t%beat, frequency=track.notes[Math.floor(t/beat)%track.notes.length];
   const attack=Math.min(1,age/.02), phase=2*Math.PI*frequency*t;
   let value=0;
   if(id==='night')value=.16*attack*Math.exp(-age*2)*(Math.sin(phase)+.4*Math.sin(phase*1.5))+.05*Math.sin(2*Math.PI*110*t);
   else if(id==='voice') {
    const envelope=attack*Math.min(1,(beat-age)/.08);
    // Deterministic vowel-like harmonics: no speech model, lyrics or singer imitation.
    for(let h=1;h<=10;h++) {const f=h*frequency;const weight=.6*Math.exp(-(((f-750)/400)**2))+.3*Math.exp(-(((f-1500)/500)**2));value+=.085*envelope*weight*Math.sin(phase*h);}
   } else {
    const envelope=attack*Math.exp(-age*5);
    value=.22*envelope*(Math.sin(phase)+.2*Math.sin(phase*2));
    value+=(id==='pulse'?.35:.28)*Math.sin(2*Math.PI*65*age)*Math.exp(-age*35);
    if(id==='pulse') {const hatAge=t%(beat/2);value+=.04*(Math.sin(2*Math.PI*5000*hatAge)+Math.sin(2*Math.PI*7100*hatAge))*Math.exp(-hatAge*55);}
   }
   const fade=Math.min(1,t/.04,(seconds-t)/.2);
   view.setInt16(44+i*2,Math.round(Math.max(-1,Math.min(1,value*fade))*32767),true);
 }
 return new Blob([buffer],{type:'audio/wav'});
}
