const {chromium}=require('playwright');
const {pathToFileURL}=require('node:url');
const {resolve}=require('node:path');
const assert=require('node:assert/strict');
(async()=>{
const browser=await chromium.launch();
try{
for(const [name,w,h] of [['Desktop',1200,820],['Phone',390,844]]){
  const page=await browser.newPage({viewport:{width:w,height:h}});
  const errors=[];page.on('pageerror',e=>errors.push(e.message));
  await page.goto(pathToFileURL(resolve('classic-proof/DansVersion-Classic.html')).href);
  await page.locator('.mast img').evaluate(i=>i.decode());
  assert.ok(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth));
  await page.screenshot({path:'classic-proof/DansVersion-Classic-'+name+'.png',fullPage:false});
  await page.getByRole('link',{name:'Bills & Resolutions',exact:true}).click();
  assert.equal(await page.locator('#billRows tr').count(),100);
  await page.locator('#filterBills').fill('0315');assert.equal(await page.locator('#billRows tr').count(),1);
  await page.locator('#bills .back').click();
  await page.locator('#house a').first().click();assert.ok(await page.locator('#memberRows tr').count()>80);
  await page.locator('#filterMembers').fill('Didech');assert.equal(await page.locator('#memberRows tr').count(),1);
  assert.equal(await page.locator('#memberRows tr td').nth(1).innerText(),'59');
  assert.deepEqual(errors,[]);console.log(name,'home, all bill links, range filter and House member lookup passed');
  await page.close();
}
}finally{await browser.close()}
})().catch(e=>{console.error(e);process.exitCode=1});
