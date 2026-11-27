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
        await page.locator('.tenure-value').first().waitFor({timeout:220000});
        const values=await page.locator('.tenure-value').allTextContents();
        const months=values.map(v=>v==='Unavailable'?-1:Number(/(\d+) yr/.exec(v)?.[1]||0)*12+Number(/(\d+) mo/.exec(v)?.[1]||0));
        const missing=await list.evaluateAll(rs=>rs.filter(r=>r.querySelector('.tenure-value')?.textContent==='Unavailable').map(r=>r.querySelector('a').getAttribute('href')));
        console.log(chamber,'missing service dates',missing);
        for(const path of missing) {
          const u=new URL(path,base);
          const res=await fetch('https://dansversion-legislative-feed.onrender.com/classic/api/chamber?'+u.searchParams);
          if(res.ok){const data=await res.json();const pos=data.markup.indexOf('member-photo-col');console.log('Profile service field',path,data.markup.slice(pos,pos+1000).replace(/<[^>]+>/g,' ').replace(/\s+/g,' ').slice(0,300));}
        }
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
