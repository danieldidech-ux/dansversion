const { chromium, devices }=require('playwright');
const { createServer }=require('node:http');
const { readFile }=require('node:fs/promises');
const { once }=require('node:events');
const assert=require('node:assert/strict');
const {resolve}=require('node:path');
const live=process.argv.includes('--live');
const range='/Legislation/BillStatus?DocTypeID=SB&DocNum=';
const stamp={retrievedAt:'2026-09-16T01:00:00Z',stale:false};
const fixtures={
  'range-index':{...stamp,bills:Array.from({length:100},(_,i)=>({number:'SB0'+(301+i),title:'Official title '+(301+i),url:'https://ilga.gov'+range+(301+i)+'&LegID='+(20001+i)}))},
  members:{...stamp,members:Array.from({length:118},(_,i)=>({name:'Representative '+(i+1),district:i+1,url:'https://www.ilga.gov/House/Members/Details/'+(100+i)}))},
  summary:{...stamp,complete:true,summary:{senateSponsor:'Senate sponsor',sponsorStatus:'verified'}},
  'member-service':{...stamp,periods:['January 2019 – Present']}
};
const files={'/':['tests/reader-screen.html','text/html'],'/web/reader-panels.mjs':['web/reader-panels.mjs','text/javascript'],'/web/reader-panels.css':['web/reader-panels.css','text/css']};
const requests=[];
const server=createServer(async(req,res)=>{
  try {
    const url=new URL(req.url,'http://localhost');
    if (files[url.pathname]){
      const [file,type]=files[url.pathname];
      res.writeHead(200,{'content-type':type});return res.end(await readFile(resolve(__dirname,'..',file)));
    }
    const route=url.pathname.replace('/api/reader/','');
    if (!Object.hasOwn(fixtures,route)){res.writeHead(404);return res.end();}
    requests.push(route);
    const {handleReaderRequest}=await import('../web/reader-proxy.mjs');
    const env={ILGA_FEED_ORIGIN:'https://test-feed.invalid',ILGA_FEED_TOKEN:process.env.ILGA_FEED_TOKEN || 'fixture-only'};
    const bridged=await handleReaderRequest(new Request(url),env,async(upstream,options)=>{
      if(live){
        const response=await fetch('http://127.0.0.1:10009'+upstream.pathname+upstream.search,options);
        if(!response.ok) console.error('Feed response',route,response.status,await response.clone().text());
        return response;
      }
      return Response.json(fixtures[route]);
    });
    res.writeHead(bridged.status,Object.fromEntries(bridged.headers));
    res.end(await bridged.text());
  } catch(error){res.writeHead(500);res.end(String(error));}
});
async function main(){
  server.listen(0,'127.0.0.1');await once(server,'listening');
  const origin='http://127.0.0.1:'+server.address().port;
  const browser=await chromium.launch();
  try {
    for(const [device,opts] of [['phone',devices['Pixel 7']],['desktop',{viewport:{width:1440,height:900}}]]){
      const context=await browser.newContext(opts);
      for(const [path,kind] of [['','bill'],['?house=1','member']]){
        requests.length=0;
        const page=await context.newPage();
        const faults=[];page.on('pageerror',e=>faults.push(e.message));
        await page.goto(origin+'/'+path);
        const rows=page.locator('li');
        await rows.first().waitFor({timeout:35000});
        const count=await rows.count();assert.ok(count>=40);
        if(kind==='bill') {
          assert.equal(count,100);
          assert.match(await rows.first().innerText(),/SB0?301/);
          assert.match(await rows.last().innerText(),/SB0?400/);
        }
        assert.deepEqual(requests,[kind==='bill'?'range-index':'members']);
        const row=rows.nth(kind==='bill'?74:40);
        const links=row.locator('a');
        const selected=links.nth(kind==='bill'?1:0);
        if(kind==='bill')assert.equal(await selected.getAttribute('href'),await links.first().getAttribute('href'));
        await selected.scrollIntoViewIfNeeded();await selected.focus();
        const label=await selected.innerText(),top=await page.evaluate(()=>scrollY);
        assert.ok(top>0);
        await selected.click();await page.waitForURL('**/?detail=*');
        await page.goBack();
        await page.waitForFunction(label=>document.activeElement?.textContent===label,label);
        assert.ok(Math.abs(await page.evaluate(()=>scrollY)-top)<8);
        assert.ok(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth));
        const detail=row.locator('details');await detail.locator('summary').click();
        await detail.locator('time').waitFor({timeout:35000});
        assert.ok(await detail.locator('time').getAttribute('datetime'));
        assert.match(await page.locator('[role=status]').innerText(),/ILGA/);
        assert.equal(requests.filter(k=>k==='summary'||k==='member-service').length,1);
        assert.deepEqual(faults,[]);
        console.log(device,kind,count,'clickable entries; on-demand details, timestamp, width and Back passed');
        await page.close();
      }
      await context.close();
    }
  } finally {await browser.close();}
}
main().catch(e=>{console.error(e);process.exitCode=1;}).finally(()=>server.close());
