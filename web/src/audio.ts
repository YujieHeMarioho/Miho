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
// Original synthesized melody: no third-party recording or copyrighted song.
export function demoWave(): Blob {
 const rate = 24000, seconds = 12, count = rate * seconds;
 const buffer = new ArrayBuffer(44 + count * 2), view = new DataView(buffer);
 const text = (at: number, value: string) => [...value].forEach((c, i) => view.setUint8(at+i,c.charCodeAt(0)));
 text(0,'RIFF'); view.setUint32(4,36+count*2,true); text(8,'WAVE'); text(12,'fmt ');
 view.setUint32(16,16,true); view.setUint16(20,1,true); view.setUint16(22,1,true);
 view.setUint32(24,rate,true); view.setUint32(28,rate*2,true); view.setUint16(32,2,true); view.setUint16(34,16,true);
 text(36,'data'); view.setUint32(40,count*2,true);
 const notes = [261.63,329.63,392,329.63,293.66,349.23,440,392];
 for(let i=0;i<count;i++) {
   const t=i/rate, age=t%0.5, frequency=notes[Math.floor(t/0.5)%notes.length];
   const envelope=Math.min(1,age/0.015)*Math.exp(-age*5);
   const melody=0.22*envelope*(Math.sin(2*Math.PI*frequency*t)+0.2*Math.sin(4*Math.PI*frequency*t));
   const kick=0.28*Math.sin(2*Math.PI*65*age)*Math.exp(-age*35);
   const fade=Math.min(1,(seconds-t)/0.2);
   view.setInt16(44+i*2,Math.round((melody+kick)*fade*32767),true);
 }
 return new Blob([buffer],{type:'audio/wav'});
}
