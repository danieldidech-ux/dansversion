const {chromium,devices}=require('playwright');
const assert=require('node:assert/strict');
const base=process.env.CLASSIC_ORIGIN||'http://127.0.0.1:10009/classic/';
(async()=>{
  const browser=await chromium.launch();
  try {
    for (const [device,config] of [['phone',devices['Pixel 7']],['desktop',{viewport:{width:1440,height:900}}]]) {
      const page=await browser.newPage(config);
      page.setDefaultTimeout(40000);
      const pageBody=page.locator('#chamberPage'), list=page.locator('#memberRows tr');
      const open=async query=>{await page.goto(base+'?'+new URLSearchParams(query));};
      for (const chamber of ['House','Senate']) {
        const homeLink=async label=>{
          await page.goto(base);
          await page.locator('#'+chamber.toLowerCase()).getByRole('link',{name:label,exact:true}).click();
          await pageBody.locator('time').waitFor();
        };
        await homeLink('Rules');
        assert.ok(await pageBody.locator('li a[href$=".pdf" i]').count()>0);
        await homeLink('Committees');
        const comm=pageBody.locator('table a[href*="view=committees"]').first();
        await comm.click();await pageBody.locator('time').waitFor();
        const profile=pageBody.locator('table a[href*="view=profile"]').first();
        await profile.waitFor();
        await pageBody.getByRole('link',{name:'Hearings',exact:true}).click();
        await pageBody.locator('time').waitFor();
        await pageBody.getByRole('link',{name:'Bills',exact:true}).first().click();
        await pageBody.locator('time').waitFor();
        await open({view:'members',chamber});
        await list.first().waitFor();
        const names=await list.locator('td:first-child a').allTextContents();
        if(chamber==='House')assert.match(names[0],/Ammons/);
        await page.locator('#sort').selectOption('Tenure');
        await page.locator('.tenure-value').first().waitFor({timeout:5000});
        const ranks=await list.locator('.rank-cell').allTextContents();
        assert.deepEqual(ranks,Array.from({length:names.length},(_,i)=>String(i+1)));
        if (chamber==='House') {
          const rankOf=async name=>Number(await list.filter({hasText:name}).locator('.rank-cell').textContent());
          const didech=await rankOf('Daniel Didech');
          assert.ok(await rankOf('Jennifer Gong-Gershowitz')<didech);
          assert.ok(await rankOf('Patrick Windhorst')<await rankOf('Kam Buckner'));
          await page.locator('#filterMembers').fill('Didech');
          assert.equal(await rankOf('Daniel Didech'),didech);
          await page.locator('#filterMembers').fill('');
        }
        if (chamber==='Senate') {
          const rezin=list.filter({hasText:'Sue Rezin'});
          if (await rezin.count()) assert.match(await rezin.locator('.tenure-value').innerText(),/\d+ yr/);
        }
        const values=await page.locator('.tenure-value').allTextContents();
        const months=values.map(v=>v==='Unavailable'?-1:Number(/(\d+) yr/.exec(v)?.[1]||0)*12+Number(/(\d+) mo/.exec(v)?.[1]||0));
        const missing=await list.evaluateAll(rs=>rs.filter(r=>r.querySelector('.tenure-value')?.textContent==='Unavailable').map(r=>r.querySelector('a').getAttribute('href')));
        console.log(chamber,'missing service dates',missing.length);
        assert.ok(months.filter(n=>n>=0).length>names.length*.9);
        assert.deepEqual(months,[...months].sort((a,b)=>b-a));
        await page.locator('#sort').selectOption('Alphabetical');
        assert.deepEqual(await list.locator('td:first-child a').allTextContents(),names);
        await list.first().locator('a').click();
        await pageBody.locator('time').waitFor();
        assert.ok(await pageBody.getByText('Sponsored legislation',{exact:true}).isVisible());
        assert.ok(await pageBody.getByText('Committee assignments',{exact:true}).isVisible());
        console.log(device,chamber,'rules, committees, profiles, surname order and tenure passed;',months.filter(v=>v>=0).length,'of',names.length,'dated');
      }
      const cold=await browser.newPage(config);
      // A slow or unavailable live feed must never block the first ranking.
      await cold.route('**/api/tenure?*',route=>route.abort());
      await cold.goto(base+'?view=members&chamber=House&sort=tenure');
      await cold.locator('#memberRows .rank-cell').last().waitFor({timeout:5000});
      assert.equal(await cold.locator('#memberRows .rank-cell').last().textContent(),'118');
      assert.ok(await cold.evaluate(()=>document.documentElement.scrollWidth<=innerWidth));
      console.log(device,'cold House ranks 1–118 visible in',Math.round(await cold.evaluate(()=>performance.now())),'ms');
      await cold.close();
      await page.goto(base+'?view=profile&chamber=House&id=3347#committee-assignments');
      const assignments=page.locator('#committee-assignments[open] .assignment-list');
      await assignments.waitFor();
      for (const [parent,children] of [
        ['Revenue & Finance',['Finance Subcommittee','Income Tax Subcommittee','Sales Tax Subcommittee']],
        ['Gaming',['Special Topics Subcommittee']],
        ['Judiciary - Civil',['Commercial & Property Law Sub']],
        ['Elem Sec Ed: Adm., Lic. & Charter',['Teacher Policy & Research']]
      ]) {
        const group=assignments.locator(':scope > li').filter({has:page.getByRole('link',{name:parent,exact:true})});
        for (const child of children) assert.ok(await group.locator('ul').getByRole('link',{name:child,exact:true}).isVisible());
      }
      const metadata=assignments.locator('.assignment-meta').first();
      assert.equal(await metadata.isVisible(),false);
      assert.equal(await assignments.getByText(/^Subcommittees?$/).count(),0);
      await page.getByLabel('Show chairs and codes').check();
      assert.ok(await metadata.isVisible());
      assert.ok(await assignments.locator('.assignment-meta a').first().isVisible());
      await page.getByLabel('Show chairs and codes').uncheck();
      assert.ok(await assignments.evaluate(el=>el.scrollWidth<=el.clientWidth+1));
      await open({view:'legislation'});
      await pageBody.locator('time').waitFor();
      const ranges=pageBody.locator('.range-grid a');
      assert.ok(await ranges.count()>120);
      await pageBody.getByRole('link',{name:/^AM 1040001/}).click();
      await page.locator('#billRows tr').first().waitFor();
      assert.match(await page.locator('#billRows tr').first().innerText(),/AM1040/);
      assert.equal(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth),true);
      await page.close();
    }
  } finally {await browser.close();}
})().catch(e=>{console.error(e);process.exitCode=1;});
