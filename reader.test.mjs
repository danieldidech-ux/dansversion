import { test } from 'node:test';
import assert from 'node:assert/strict';
import { createReader } from './reader.mjs';

const range = 'https://ilga.gov/Legislation/RegularSession/SB?GaId=18&SessionId=114&num1=0301&num2=0400';
const bill = n => 'https://ilga.gov/Legislation/BillStatus?DocTypeID=SB&DocNum='+n+'&LegID='+(20000+n)+'&GAID=18&SessionID=114';
const link = (url,text) => '<a href="'+url.replaceAll('&','&amp;')+'">'+text+'</a>';
const index = [301,302,410].map(n=>link(bill(n),'SB'+n)+link(bill(n),'Title '+n)).join('');
const summary = (sponsor='Member Name') => '<div class="tab-content"><h2>Official title</h2><div id="sponsorDiv">'+(sponsor?link('/Senate/Members/Details/3',sponsor):'<span>Sponsors</span>')+'</div></div>';
function setup(respond) {
  let time = Date.UTC(2026,10,22);
  const calls = [];
  const reader = createReader(async url => {
    calls.push(url);
    return {html:await respond(url), officialUrl:url, retrievedAt:new Date(time).toISOString()};
  },()=>time);
  return {reader,calls,advance:()=>{time+=61_000;}};
}
test('concurrent cold ranges share an index request and expose only official rows without sponsor fetches',async()=>{
  const {reader,calls}=setup(()=>index);
  const [a,b]=await Promise.all([reader.range(range),reader.range(range)]);
  assert.equal(calls.length,1);
  assert.deepEqual(a,b);
  assert.deepEqual(a.bills.map(r=>[r.number,r.url,r.title]),[[ 'SB0301',bill(301),'Title 301'],['SB0302',bill(302),'Title 302']]);
  assert.equal(a.complete,false);
});
test('a pending sponsor request cannot block a list, and a verified summary is reused by the list',async()=>{
  let release;
  const {reader}=setup(url=>url.includes('RegularSession')?index:new Promise(resolve=>{release=resolve;}));
  const pending=reader.summary(bill(301));
  const first=await reader.range(range);
  assert.equal(first.bills[0].detailStatus,'pending');
  release(summary());
  assert.equal((await pending).summary.primarySponsor,'Member Name');
  const second=await reader.range(range);
  assert.equal(second.bills[0].detailStatus,'verified');
  assert.equal(second.bills[1].detailStatus,'pending');
});
test('missing chief sponsor is explicitly incomplete',async()=>{
  const {reader}=setup(()=>summary(''));
  const s=await reader.summary(bill(301));
  assert.equal(s.complete,false);assert.equal(s.summary.sponsorStatus,'unavailable');
});
test('a failed or partial refresh retains a previous verification time',async()=>{
  let body=summary();
  const {reader,advance}=setup(()=>{if(!body) throw Error('timeout'); return body;});
  const original=await reader.summary(bill(301));
  for (const next of [summary(''),null]) {
    advance();body=next;
    const stale=await reader.summary(bill(301),true);
    assert.equal(stale.stale,true);assert.equal(stale.complete,false);
    assert.equal(stale.summary.primarySponsor,'Member Name');
    assert.equal(stale.retrievedAt,original.retrievedAt);
  }
});
test('confirmed empty and unrecognizable pages have distinct outcomes',async()=>{
  const empty=setup(()=>'<main><p>No bills were found</p></main>');
  assert.deepEqual((await empty.reader.range(range)).bills,[]);
  const malformed=setup(()=>'<main>Unavailable</main>');
  await assert.rejects(malformed.reader.range(range));
  const wrongSession=setup(()=>index.replaceAll('SessionID=114','SessionID=99'));
  await assert.rejects(wrongSession.reader.range(range));
});
test('member roster carries districts and official links without former members or profile fetches',async()=>{
  const row=(name,id)=>'<tr><td>'+link('/House/Members/Details/'+id,name)+'</td><td>59</td><td>D</td></tr>';
  const {reader,calls}=setup(()=>row('Current',1)+'<h2>Former Members</h2>'+row('Former',2));
  const result=await reader.members('House');
  assert.equal(calls.length,1);
  assert.deepEqual(result.members,[{name:'Current',district:59,party:'D',url:'https://www.ilga.gov/House/Members/Details/1'}]);
});
test('expired index falls back to the last successfully verified official rows',async()=>{
  let html=index;
  const {reader,advance}=setup(()=>html);
  const first=await reader.range(range);
  advance();html='<main>Upstream unavailable</main>';
  const second=await reader.range(range,true);
  assert.equal(second.indexStale,true);assert.equal(second.checkedAt,first.checkedAt);
  assert.deepEqual(second.bills,first.bills);
});
