const assert = require('node:assert/strict');
const {chromium,devices} = require('playwright');
const base = process.env.CLASSIC_ORIGIN || 'http://127.0.0.1:10009/classic/';
async function main() {
  const browser = await chromium.launch();
  try {
    for (const [name, device] of [['phone',devices['Pixel 7']],['desktop',{viewport:{width:1440,height:900}}]]) {
      const page = await browser.newPage(device);
      const requests=[], errors=[];
      page.on('request',r=>{if(r.url().includes('/classic/api/')) requests.push(new URL(r.url()).pathname.split('/').pop());});
      page.on('pageerror',e=>errors.push(e.message));
      for (const bill of [true,false]) {
        requests.length = 0;
        await page.goto(base);
        assert.ok(await page.locator('.mast img').evaluate(img=>img.complete && img.naturalWidth>0));
        await page.locator(bill?'#legislation a':'#house a').first().click();
        if (bill) await page.getByRole('link',{name:'SB 0301–0400',exact:true}).click();
        const section=page.locator(bill?'#bills':'#members');
        const rows=section.locator('tbody tr');
        await rows.first().waitFor({timeout:65000});
        if(bill) assert.deepEqual(requests.filter(r=>r!=='sponsors'),['chamber','range']); else assert.deepEqual(requests,['members']);
        const n=await rows.count();
        if(bill) {
          assert.equal(n,100);
          assert.equal(await rows.first().locator('a').first().innerText(),'SB0301');
          assert.equal(await rows.last().locator('a').first().innerText(),'SB0400');
          assert.equal(await rows.evaluateAll(rs=>rs.every(row=>row.querySelectorAll('a').length===2 && row.querySelectorAll('a')[0].href===row.querySelectorAll('a')[1].href)),true);
        } else {
          assert.ok(n>100);
          await section.locator('#sort').selectOption({label:'District'});
          assert.equal(await rows.first().locator('td').nth(1).innerText(),'1');
        }
        if(bill) assert.equal(await section.locator('[role=status] time').count(),0); else assert.ok(await section.locator('[role=status] time').getAttribute('datetime'));
        const chosen=bill?rows.filter({hasText:'SB0315'}):rows.filter({hasText:'Didech'});
        assert.equal(await chosen.count(),1);
        if(bill) {
          await page.waitForFunction(()=>{const row=[...document.querySelectorAll('#billRows tr')].find(r=>r.textContent.includes('SB0315'));return row?.querySelector('.bill-sponsors em')?.textContent.includes('Daniel Didech');},null,{timeout:180000});
          assert.equal(await chosen.locator('details').count(),0);
          assert.match(await chosen.locator('.bill-sponsors > div').first().innerText(),/Mary Edly-Allen/);
          assert.equal(await chosen.locator('.bill-sponsors em').innerText(),'Daniel Didech');
          assert.doesNotMatch(await chosen.locator('.bill-sponsors').innerText(),/Senate:|House:/);
          assert.equal(await chosen.getAttribute('class'),'bill-signed');
          assert.equal(await chosen.evaluate(row=>getComputedStyle(row).backgroundColor),'rgb(247, 237, 187)');
          await page.waitForFunction(()=>![...document.querySelectorAll('.bill-sponsors')].some(c=>c.textContent==='Loading sponsors…'),null,{timeout:240000});
        } else {
          const detail=chosen.locator('details');
          await detail.locator('summary').click();
          await detail.locator('time').waitFor({timeout:65000});
          assert.ok(await detail.locator('p').innerText());
          assert.deepEqual(requests,['members','service']);
        }
        const target=rows.nth(74).locator('a').nth(bill?1:0);
        await target.scrollIntoViewIfNeeded();
        const href=await target.getAttribute('href'), label=await target.innerText();
        assert.match(href,bill?/\/Legislation\/BillStatus/i:/view=profile&chamber=House/i);
        const top=await page.evaluate(()=>scrollY);
        assert.ok(top>0);
        // Isolate browser history from third-party navigation and redirect timing.
        if (bill) await page.route(href,route=>route.fulfill({contentType:'text/html',body:'<title>Official record</title>'}));
        await target.click();
        await page.waitForURL(new URL(href,page.url()).href);
        if (!bill) await page.locator('#chamberPage time').waitFor();
        await page.goBack();
        await page.waitForFunction(label=>document.activeElement?.textContent===label,label);
        assert.ok(Math.abs(await page.evaluate(()=>scrollY)-top)<10);
        if (!bill) assert.equal(await page.locator('#sort').inputValue(),'District');
        assert.ok(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth));
        assert.deepEqual(errors,[]);
        console.log(name,bill?'SB 301–400':'House directory',n,'rows; live data, disclosure, timestamp and Back passed');
      }
      await page.close();
    }
  } finally {await browser.close();}
}
main().catch(e=>{console.error(e);process.exitCode=1;});
