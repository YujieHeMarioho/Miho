import * as THREE from 'three';
import {AudioEngine, demoWave} from './audio';
import './style.css';
const element = <T extends HTMLElement>(id:string) => document.getElementById(id) as T;
const stage=element<HTMLDivElement>('stage'), toggle=element<HTMLButtonElement>('toggle'), status=element('status');
const media=new Audio(); media.preload='metadata'; media.volume=.65;
let context: AudioContext|undefined, analyser: AnalyserNode|undefined, source: MediaElementAudioSourceNode|undefined;
let frame=0, last=0, energy=0, disposed=false;
const spectrum=new Uint8Array(128), waveform=new Uint8Array(256);
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
function sphere(x:number,y:number,z:number,sx:number,sy:number,sz:number, material:THREE.Material){const m=new THREE.Mesh(new THREE.SphereGeometry(1,40,24),material);m.position.set(x,y,z);m.scale.set(sx,sy,sz);body.add(m);return m;}
sphere(0,0,0,.84,.84,.84,skin);sphere(-.24,.78,0,.23,.35,.15,skin);sphere(.26,.77,0,.22,.32,.15,skin);
function box(x:number,y:number,z:number,w:number,h:number,d:number,material:THREE.Material){const m=new THREE.Mesh(new THREE.BoxGeometry(w,h,d),material);m.position.set(x,y,z);body.add(m);return m;}
box(-.99,0,0,.25,.51,.35,leather);box(.99,0,0,.25,.51,.35,leather);
const arc=new THREE.Mesh(new THREE.TorusGeometry(.98,.045,12,48,Math.PI),leather);arc.position.y=.03;body.add(arc);
function lens(x:number){
 const shape=new THREE.Shape();shape.moveTo(-.32,.22);shape.lineTo(.32,.22);shape.lineTo(.27,-.18);shape.lineTo(-.27,-.18);shape.closePath();
 const mesh=new THREE.Mesh(new THREE.ExtrudeGeometry(shape,{depth:.04,bevelEnabled:true,bevelSegments:3,steps:1,bevelSize:.025,bevelThickness:.02}),black);
 mesh.position.set(x,.10,.87);body.add(mesh);
}
lens(-.37);lens(.37);box(0,.17,.90,.19,.04,.04,black);
const halo=new THREE.Mesh(new THREE.SphereGeometry(1,32,20),new THREE.MeshBasicMaterial({color:0x83ead6,transparent:true,opacity:.04,side:THREE.BackSide,depthWrite:false}));halo.scale.setScalar(.88);body.add(halo);
try { renderer=new THREE.WebGLRenderer({alpha:true,antialias:true,powerPreference:'low-power'});renderer.setPixelRatio(Math.min(devicePixelRatio,1.5));stage.prepend(renderer.domElement); }
catch { element('fallback').hidden=false; }
function render(){renderer?.render(scene,camera)}
function resize(){const {width,height}=stage.getBoundingClientRect();camera.aspect=width/Math.max(1,height);camera.updateProjectionMatrix();renderer?.setSize(width,height,false);render()}
const resizeObserver=new ResizeObserver(resize);resizeObserver.observe(stage);
const reduced=matchMedia('(prefers-reduced-motion: reduce)');
function clock(n:number){if(!Number.isFinite(n))return '0:00';return `${Math.floor(n/60)}:${Math.floor(n%60).toString().padStart(2,'0')}`}
function timing(){element('time').textContent=`${clock(media.currentTime)} / ${clock(media.duration)}`}
const engine=new AudioEngine(media,async()=>{
 if(!context){context=new AudioContext();analyser=context.createAnalyser();analyser.fftSize=256;source=context.createMediaElementSource(media);source.connect(analyser);analyser.connect(context.destination);}
 if(context.state!=='running')await context.resume();
},URL,()=>{toggle.disabled=!engine.loaded;toggle.textContent=engine.playing?'暂停':'播放';toggle.setAttribute('aria-label',toggle.textContent);if(engine.playing){status.textContent='正在跟随音乐 · 本地频谱分析';schedule()}else{cancelAnimationFrame(frame);frame=0;energy=0;body.scale.setScalar(1);body.position.y=0;body.rotation.set(0,0,0);(halo.material as THREE.MeshBasicMaterial).opacity=.04;bars.forEach(b=>b.style.height='2px');render();}});
function schedule(){if(!frame&&!disposed)frame=requestAnimationFrame(tick)}
function tick(now:number){frame=0;if(!engine.playing||disposed)return;if(now-last<33){schedule();return;}last=now;
 analyser?.getByteFrequencyData(spectrum);analyser?.getByteTimeDomainData(waveform);
 let sum=0;for(let i=0;i<128;i++)sum+=((waveform[i]-128)/128)**2;
 const rms=Math.sqrt(sum/128);energy+=(Math.min(1,rms*4)-energy)*.25;
 if(!reduced.matches){body.scale.setScalar(1+energy*.14);body.position.y=Math.abs(Math.sin(now*.006))*energy*.14;body.rotation.z=Math.sin(now*.002)*energy*.16;body.rotation.x=Math.sin(now*.004)*energy*.13;}
 (halo.material as THREE.MeshBasicMaterial).opacity=.025+energy*.1;halo.scale.setScalar(.88+energy*.04);
 bars.forEach((bar,i)=>{const index=Math.min(127,Math.floor(Math.pow(i/23,2)*127));bar.style.height=`${2+spectrum[index]/255*28}px`;});timing();render();schedule();}
async function play(){try{await engine.play()}catch(error){status.textContent=`无法播放：${error instanceof Error?error.message:'请换一个音频文件'}`}}
element('demo').addEventListener('click',()=>{engine.select(demoWave());element('track').textContent='Little Miho · 原创合成旋律';void play()});
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
window.addEventListener('pagehide',event=>{engine.pause();if(event.persisted)return;disposed=true;resizeObserver.disconnect();document.removeEventListener('visibilitychange',visibility);engine.dispose();source?.disconnect();analyser?.disconnect();void context?.close();scene.traverse(node=>{if(node instanceof THREE.Mesh){node.geometry.dispose();const materials=Array.isArray(node.material)?node.material:[node.material];materials.forEach(m=>m.dispose());}});renderer?.dispose();});
resize();
