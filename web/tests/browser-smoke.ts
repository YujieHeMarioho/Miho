import {chromium} from 'playwright';
import assert from 'node:assert/strict';
import {demoWave} from '../src/audio';
const browser=await chromium.launch({executablePath:'/Applications/Google Chrome.app/Contents/MacOS/Google Chrome',headless:true,args:['--use-gl=angle','--use-angle=swiftshader','--enable-unsafe-swiftshader']});
try {
 const page=await browser.newPage({viewport:{width:1200,height:900}});
 const errors:string[]=[];page.on('pageerror',error=>errors.push(error.message));
 await page.goto(process.env.MIHO_TEST_URL ?? 'http://127.0.0.1:5173/');
 await page.locator('#stage canvas').waitFor();
 await page.screenshot({path:'/tmp/miho-web-desktop.png',fullPage:true});
 await page.locator('[data-color="#aa83ec"]').click();
 assert.equal(await page.locator('[data-color="#aa83ec"]').getAttribute('aria-pressed'),'true');
 await page.locator('#demo').click();
 await page.waitForFunction(()=>document.querySelector('#toggle')?.textContent==='暂停');
 await page.locator('#toggle').click();
 assert.equal(await page.locator('#toggle').textContent(),'播放');
 await page.locator('#toggle').click();
 await page.waitForFunction(()=>document.querySelector('#toggle')?.textContent==='暂停');
 await page.locator('#toggle').click();
 const buffer=Buffer.from(await demoWave().arrayBuffer());
 for(const name of ['first.wav','second.wav']){
  await page.locator('#file').setInputFiles({name,mimeType:'audio/wav',buffer});
  assert.equal(await page.locator('#track').textContent(),name);
  await page.locator('#toggle').click();
  await page.waitForFunction(()=>document.querySelector('#toggle')?.textContent==='暂停');
  await page.locator('#toggle').click();
 }
 await page.locator('#demo').click();
 await page.waitForFunction(()=>document.querySelector('#status')?.textContent?.includes('播放结束'),{},{timeout:16000});
 assert.equal(await page.locator('#toggle').textContent(),'播放');
 await page.locator('#toggle').click();
 await page.waitForFunction(()=>document.querySelector('#toggle')?.textContent==='暂停');
 await page.locator('#toggle').click();
 await page.setViewportSize({width:390,height:844});
 await page.screenshot({path:'/tmp/miho-web-mobile.png',fullPage:true});
 assert.equal(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth),true);
 await page.goto('about:blank');
 assert.deepEqual(errors,[]);
 console.log('Browser smoke PASS: WebGL, colors, playback/pause/replay, two file swaps, audio end, mobile layout, teardown; no page errors.');
} finally {await browser.close()}
