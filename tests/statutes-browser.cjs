const {chromium,devices}=require('playwright');
const assert=require('node:assert/strict');
const base=process.env.CLASSIC_ORIGIN || 'http://127.0.0.1:10009/classic/';
(async()=>{
  const browser=await chromium.launch();
  try {
    for (const [name,options] of [['desktop',{viewport:{width:1440,height:900}}],['phone',devices['Pixel 7']]]) {
      const page=await browser.newPage(options);
      const errors=[];
      page.on('pageerror',e=>errors.push(e.message));
      page.setDefaultTimeout(35000);
      const statutes=page.locator('#statutes');
      const click=name=>statutes.getByRole('link',{name}).first().click();
      await page.goto(base);
      await page.getByRole('link',{name:'Illinois Compiled Statutes',exact:true}).click();
      await statutes.locator('time').waitFor();
      assert.equal(await statutes.locator('.bar').count(),9);
      assert.ok(await statutes.locator('.statute-index a').count()>=65);
      await click(/CHAPTER\s+5\s+GENERAL PROVISIONS/i);
      await click(/Open Meetings Act/i);
      await statutes.locator('.statute-toc summary').click();
      await click(/^5 ILCS 120\/2\.06$/);
      assert.match(page.url(),/#s-/);
      const citation=await page.locator(':target').textContent();
      assert.match(citation,/5 ILCS 120\/2\.06/);
      assert.match(await statutes.locator('.statute-text').innerText(),/Source:\s*P\.A\./);
      await click(/^Illinois Compiled Statutes$/);
      await click(/CHAPTER\s+105\s+SCHOOLS/i);
      await click(/^105 ILCS 5\/\s*School Code\./i);
      await click(/^Article 1 - Short Title/i);
      await statutes.locator('.statute-text').waitFor();
      assert.match(await statutes.locator('.statute-text').innerText(),/105 ILCS 5\/1-1/);
      assert.ok(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth));
      await page.goBack();
      await statutes.getByRole('link',{name:/Article 1 - Short Title/i}).waitFor();
      assert.equal(new URL(page.url()).origin,new URL(base).origin);
      assert.deepEqual(errors,[]);
      console.log(name,'chapter index, Open Meetings Act section and School Code article passed');
      await page.close();
    }
  } finally {await browser.close();}
})().catch(e=>{console.error(e);process.exitCode=1;});
