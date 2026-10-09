import * as THREE from 'three';
import {AudioEngine, demoWave, tracks} from './audio';
import {bandFeatures, modeTarget, type Mode} from './modes';
import {RoundedBoxGeometry} from 'three/addons/geometries/RoundedBoxGeometry.js';
import './style.css';
const element = <T extends HTMLElement>(id:string) => document.getElementById(id) as T;
const stage=element<HTMLDivElement>('stage'), toggle=element<HTMLButtonElement>('toggle'), status=element('status');
const media=new Audio(); media.preload='metadata'; media.volume=.65;
let context: AudioContext|undefined, analyser: AnalyserNode|undefined, source: MediaElementAudioSourceNode|undefined;
let frame=0, last=0, energy=0, previousBass=0, disposed=false;
let mode:Mode='music';
const spectrum=new Uint8Array(512), waveform=new Uint8Array(1024);
const bars=Array.from({length:24},()=>{const bar=document.createElement('i');element('bars').append(bar);return bar});
let renderer: THREE.WebGLRenderer|undefined;
const scene=new THREE.Scene(), camera=new THREE.PerspectiveCamera(38,1,.1,100);
camera.position.set(0,.35,6.8);
scene.add(new THREE.HemisphereLight(0xe5faff,0x1c2436,2.4));
const light=new THREE.DirectionalLight(0xffffff,3);light.position.set(-3,4,5);scene.add(light);
const turntable=new THREE.Group(), body=new THREE.Group();turntable.add(body);scene.add(turntable);
const skin=new THREE.MeshStandardMaterial({color:0x05b3e4,roughness:.7});
const leather=new THREE.MeshStandardMaterial({color:0x70442e,roughness:.65});
const black=new THREE.MeshStandardMaterial({color:0x171e24,roughness:.35});
const gold=new THREE.MeshStandardMaterial({color:0xe6b85d,roughness:.4});
const hatMaterial=new THREE.MeshStandardMaterial({color:0x315f60,roughness:.9});
const rig=new THREE.Group();body.add(rig);
const haloMaterial=new THREE.MeshBasicMaterial({color:0x83ead6,transparent:true,opacity:.04,side:THREE.BackSide,depthWrite:false});
const halo=new THREE.Mesh(new THREE.SphereGeometry(1,32,20),haloMaterial);body.add(halo);
const presets={
 classic:{name:'经典咪虎',color:'#05b3e4'},bean:{name:'薄荷豆豆',color:'#78cbb0'},
 bunny:{name:'兔耳粉团',color:'#ef8dae'},crown:{name:'皇冠圆方',color:'#aa83ec'}
} as const;
function mesh(geometry:THREE.BufferGeometry,material:THREE.Material,x:number,y:number,z:number){const node=new THREE.Mesh(geometry,material);node.position.set(x,y,z);rig.add(node);return node;}
function sphere(x:number,y:number,z:number,sx:number,sy:number,sz:number, material:THREE.Material){const node=mesh(new THREE.SphereGeometry(1,40,24),material,x,y,z);node.scale.set(sx,sy,sz);return node;}
function box(x:number,y:number,z:number,w:number,h:number,d:number,material:THREE.Material){return mesh(new THREE.BoxGeometry(w,h,d),material,x,y,z);}
function glassesLens(x:number){const shape=new THREE.Shape();shape.moveTo(-.32,.22);shape.lineTo(.32,.22);shape.lineTo(.27,-.18);shape.lineTo(-.27,-.18);shape.closePath();mesh(new THREE.ExtrudeGeometry(shape,{depth:.04,bevelEnabled:true,bevelSegments:3,steps:1,bevelSize:.025,bevelThickness:.02}),black,x,.10,.87);}
function appearance(id:keyof typeof presets){
 rig.traverse(node=>{if(node instanceof THREE.Mesh)node.geometry.dispose()});rig.clear();
 const preset=presets[id];skin.color.set(preset.color);
 if(id==='crown')mesh(new RoundedBoxGeometry(1.64,1.64,1.64,4,.24),skin,0,0,0);
 else sphere(0,0,0,id==='bean'?.78:.84,id==='bean'?.91:.84,id==='bean'?.78:.84,skin);
 if(id==='classic') {
  sphere(-.24,.78,0,.23,.35,.15,skin);sphere(.26,.77,0,.22,.32,.15,skin);
  box(-.99,0,0,.25,.51,.35,leather);box(.99,0,0,.25,.51,.35,leather);
  mesh(new THREE.TorusGeometry(.98,.045,12,48,Math.PI),leather,0,.03,0);
  glassesLens(-.37);glassesLens(.37);box(0,.17,.90,.19,.04,.04,black);
 } else {
  for(const x of [-.29,.29])sphere(x,.12,.86,.08,.10,.04,black);
  if(id==='bean') {
   sphere(0,.73,-.04,.77,.35,.72,hatMaterial);
   mesh(new THREE.TorusGeometry(.7,.075,12,48),hatMaterial,0,.66,0).rotation.x=Math.PI/2;
   sphere(0,1.08,-.04,.13,.13,.13,hatMaterial);
  } else if(id==='bunny') {
   sphere(-.31,1.04,-.04,.18,.53,.15,skin);sphere(.31,1.04,-.04,.18,.53,.15,skin);
  } else {
   mesh(new THREE.TorusGeometry(.44,.055,12,32),gold,0,.91,0).rotation.x=Math.PI/2;
   for(let i=0;i<5;i++){const angle=i/5*Math.PI*2;mesh(new THREE.ConeGeometry(.12,.32,4),gold,Math.cos(angle)*.42,1.06,Math.sin(angle)*.42);}
   for(const x of [-.29,.29])mesh(new THREE.TorusGeometry(.19,.027,10,32),black,x,.12,.92);
   box(0,.12,.92,.2,.035,.03,black);
  }
 }
 halo.scale.set(id==='bean'?.83:.88,id==='bean'?.96:.88,.88);
 stage.setAttribute('aria-label',preset.name+' · 可旋转的三维角色');
 document.querySelectorAll<HTMLButtonElement>('[data-color]').forEach(b=>b.setAttribute('aria-pressed',String(b.dataset.color===preset.color)));
 renderer?.render(scene,camera);
}
appearance('classic');
try { renderer=new THREE.WebGLRenderer({alpha:true,antialias:true,powerPreference:'low-power'});renderer.setPixelRatio(Math.min(devicePixelRatio,1.5));stage.prepend(renderer.domElement); }
catch { element('fallback').hidden=false; }
function render(){renderer?.render(scene,camera)}
function resize(){const {width,height}=stage.getBoundingClientRect();camera.aspect=width/Math.max(1,height);camera.updateProjectionMatrix();renderer?.setSize(width,height,false);render()}
const resizeObserver=new ResizeObserver(resize);resizeObserver.observe(stage);
const reduced=matchMedia('(prefers-reduced-motion: reduce)');
function clock(n:number){if(!Number.isFinite(n))return '0:00';return `${Math.floor(n/60)}:${Math.floor(n%60).toString().padStart(2,'0')}`}
function timing(){element('time').textContent=`${clock(media.currentTime)} / ${clock(media.duration)}`}
const engine=new AudioEngine(media,async()=>{
 if(!context){context=new AudioContext();analyser=context.createAnalyser();analyser.fftSize=1024;source=context.createMediaElementSource(media);source.connect(analyser);analyser.connect(context.destination);}
 if(context.state!=='running')await context.resume();
},URL,()=>{toggle.disabled=!engine.loaded;toggle.textContent=engine.playing?'暂停':'播放';toggle.setAttribute('aria-label',toggle.textContent);if(engine.playing){status.textContent=mode==='singer'?'歌手模式 · 混音人声频段响应':'背景音乐模式 · 低频与重音响应';schedule()}else{cancelAnimationFrame(frame);frame=0;energy=0;previousBass=0;body.scale.setScalar(1);body.position.y=0;body.rotation.set(0,0,0);(halo.material as THREE.MeshBasicMaterial).opacity=.04;bars.forEach(b=>b.style.height='2px');render();}});
function schedule(){if(!frame&&!disposed)frame=requestAnimationFrame(tick)}
function tick(now:number){frame=0;if(!engine.playing||disposed)return;if(now-last<33){schedule();return;}last=now;
 analyser?.getByteFrequencyData(spectrum);analyser?.getByteTimeDomainData(waveform);
 let sum=0;for(let i=0;i<waveform.length;i++)sum+=((waveform[i]-128)/128)**2;
 const rms=Math.sqrt(sum/waveform.length), bands=bandFeatures(spectrum,context?.sampleRate??48000,1024);
 const target=modeTarget(mode,bands,rms), hit=Math.max(0,bands.bass-previousBass);previousBass=bands.bass;
 energy+=(target.drive-energy)*.25;
 if(!reduced.matches){
  body.scale.setScalar(1+energy*.14);
  const y=mode==='singer'?energy*.05:energy*.12+hit*.15;
  const roll=mode==='singer'?target.tilt*energy*.22:hit*.12;
  const nod=mode==='singer'?target.nod*.2:target.nod+hit*.25;
  body.position.y+=(y-body.position.y)*.25;
  body.rotation.z+=(roll-body.rotation.z)*.2;
  body.rotation.x+=(nod-body.rotation.x)*.25;
  body.rotation.y+=((mode==='singer'?target.tilt*energy*.18:0)-body.rotation.y)*.2;
 }
 haloMaterial.opacity=.025+energy*.1;
 bars.forEach((bar,i)=>{const hz=mode==='singer'?300+(i/23)*2700:40*Math.pow(100,i/23);const index=Math.min(spectrum.length-1,Math.round(hz*1024/(context?.sampleRate??48000)));bar.style.height=`${2+spectrum[index]/255*28}px`;});timing();render();schedule();}
async function play(){try{await engine.play()}catch(error){status.textContent=`无法播放：${error instanceof Error?error.message:'请换一个音频文件'}`}}
const song=element<HTMLSelectElement>('song');
for(const track of tracks){const option=document.createElement('option');option.value=track.id;option.textContent=track.name+' · '+track.style;song.append(option);}
function selectDemo(autoplay:boolean){const selected=tracks.find(t=>t.id===song.value)!;engine.select(demoWave(selected.id));element('track').textContent=selected.name+' · 原创合成短曲';status.textContent='示例已载入，点击播放。';timing();if(autoplay)void play();}
element('demo').addEventListener('click',()=>selectDemo(true));
song.addEventListener('change',()=>selectDemo(engine.playing));
element<HTMLSelectElement>('character').addEventListener('change',event=>{appearance((event.target as HTMLSelectElement).value as keyof typeof presets);render()});
for(const button of document.querySelectorAll<HTMLButtonElement>('[data-mode]'))button.addEventListener('click',()=>{
 mode=button.dataset.mode as Mode;
 document.querySelectorAll('[data-mode]').forEach(b=>b.setAttribute('aria-pressed',String(b===button)));
 element('mode-help').textContent=mode==='singer'?'300–3000 Hz 频段演示 · 不做人声分离':'低频与重音驱动 · 无 AI 节拍跟踪';
 status.textContent=engine.playing?(mode==='singer'?'歌手模式 · 混音人声频段响应':'背景音乐模式 · 低频与重音响应'):'模式已切换，播放音频体验。';
 render();
});
element<HTMLInputElement>('file').addEventListener('change',event=>{const input=event.target as HTMLInputElement,file=input.files?.[0];if(!file)return;engine.select(file);element('track').textContent=file.name;status.textContent='本地音频已载入，点击播放。';input.value='';timing()});
toggle.addEventListener('click',()=>{if(engine.playing){engine.pause();status.textContent='已暂停 · 咪虎歇一会儿';}else void play()});
element<HTMLInputElement>('volume').addEventListener('input',event=>{media.volume=Number((event.target as HTMLInputElement).value)});
media.addEventListener('ended',()=>{status.textContent='播放结束 · 可以再次播放';timing()});
media.addEventListener('loadedmetadata',timing);
media.addEventListener('error',()=>{engine.pause();status.textContent='此文件无法解码，请选择浏览器支持的 MP3、WAV 或其他音频。'});
let dragging=false, x=0, y=0;
stage.addEventListener('pointerdown',event=>{dragging=true;x=event.clientX;y=event.clientY;stage.setPointerCapture(event.pointerId)});
stage.addEventListener('pointermove',event=>{if(!dragging)return;turntable.rotation.y+=(event.clientX-x)*.01;turntable.rotation.x=THREE.MathUtils.clamp(turntable.rotation.x+(event.clientY-y)*.006,-.5,.5);x=event.clientX;y=event.clientY;render()});
const release=()=>{dragging=false};stage.addEventListener('pointerup',release);stage.addEventListener('pointercancel',release);
stage.addEventListener('dblclick',()=>{turntable.rotation.set(0,0,0);render()});
for(const button of document.querySelectorAll<HTMLButtonElement>('[data-color]'))button.addEventListener('click',()=>{skin.color.set(button.dataset.color!);document.querySelectorAll('[data-color]').forEach(b=>b.setAttribute('aria-pressed',String(b===button)));render()});
const visibility=()=>{if(document.hidden){engine.pause();status.textContent='页面已隐藏，暂停以节省资源。'}};document.addEventListener('visibilitychange',visibility);
window.addEventListener('pagehide',event=>{engine.pause();if(event.persisted)return;disposed=true;resizeObserver.disconnect();document.removeEventListener('visibilitychange',visibility);engine.dispose();source?.disconnect();analyser?.disconnect();void context?.close();scene.traverse(node=>{if(node instanceof THREE.Mesh){node.geometry.dispose();const materials=Array.isArray(node.material)?node.material:[node.material];materials.forEach(m=>m.dispose());}});skin.dispose();leather.dispose();black.dispose();gold.dispose();hatMaterial.dispose();renderer?.dispose();});
resize();
