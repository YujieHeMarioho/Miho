export type Mode = 'singer' | 'music';
export function bandFeatures(spectrum: Uint8Array, sampleRate: number, fftSize: number) {
 let bass=0,bassCount=0,voice=0,voiceCount=0,weighted=0,voiceWeight=0;
 for(let i=1;i<spectrum.length;i++) {
  const hz=i*sampleRate/fftSize, value=spectrum[i]/255;
  if(hz>=40&&hz<300){bass+=value*value;bassCount++;}
  if(hz>=300&&hz<=3000){voice+=value*value;voiceWeight+=value;voiceCount++;weighted+=value*hz;}
 }
 return {bass:Math.sqrt(bass/Math.max(1,bassCount)),voice:Math.sqrt(voice/Math.max(1,voiceCount)),
  center:voiceWeight>0?Math.max(-1,Math.min(1,(weighted/voiceWeight-1400)/1400)):0};
}
export function modeTarget(mode: Mode, bands: ReturnType<typeof bandFeatures>, rms: number) {
 // Bands are derived from the mixture. This does NOT isolate vocals or track pitch.
 return mode==='singer'
  ? {drive:Math.min(1,bands.voice*1.5),tilt:bands.center,nod:bands.voice*.25}
  : {drive:Math.min(1,bands.bass*1.25+rms*.5),tilt:0,nod:bands.bass*.4};
}
