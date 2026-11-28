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
test('service periods are retrieved only on request and preserve their check time after failure',async()=>{
  let html='<h1>Member</h1><p>104th General Assembly (2025-2026)</p><div>January 2019 – Present</div><h2>Member Details</h2>';
  const {reader,calls,advance}=setup(()=>html);
  assert.equal(calls.length,0);
  const url='https://www.ilga.gov/House/Members/Details/3347';
  const record=await reader.service(url);
  assert.deepEqual(record.periods,['January 2019 – Present']);
  advance();html='<h2>Member Details</h2>';
  const stale=await reader.service(url,true);
  assert.equal(stale.stale,true);assert.equal(stale.retrievedAt,record.retrievedAt);
});

test('bill colors follow dated actions, substantive assignments and terminal outcomes',async()=>{
  const check=async(actions,expected,type='SB')=>{
    const html=summary()+ '<table>'+actions.map(([chamber,text],i)=>'<tr><td>5/'+(i+1)+'/2026</td><td>'+chamber+'</td><td>'+text+'</td></tr>').join('')+'</table>';
    const {reader}=setup(()=>html);
    const result=(await reader.summary(bill(301).replace('DocTypeID=SB','DocTypeID='+type))).summary;
    assert.equal(result.billStatus,expected,JSON.stringify(actions));
    return result;
  };
  await check([['Senate','Referred to Assignments']],'');
  await check([['Senate','Assigned to Executive']],'committee');
  await check([['Senate','Assigned to Executive'],['Senate','Rule 3-9(a) / Re-referred to Assignments']],'');
  await check([['Senate','Assigned to Executive'],['Senate','Do Pass Executive; 010-000-000']],'');
  await check([['Senate','Assigned to Executive'],['Senate','Floor Amendment No. 1 Referred to Assignments']],'committee');
  assert.equal((await check([['House','Arrive in House']],'both')).bothChambers,true);
  await check([['Senate','Arrive in Senate']],'both','HB');
  await check([['House','Arrive in House'],['House','Assigned to Judiciary - Civil Committee']],'committee');
  await check([['Senate','Passed Both Houses']],'passed');
  await check([['Senate','Sent to the Governor']],'passed');
  await check([['Senate','Passed Both Houses'],['Senate','Governor Approved'],['Senate','Public Act 104-0001']],'signed');
  await check([['Senate','Passed Both Houses'],['Senate','Governor Vetoed']],'vetoed');
  await check([['Senate','Governor Amendatory Veto']],'vetoed');
  const result=await check([['Senate','Governor Vetoed'],['Senate','Total Veto Stands'],['Senate','Public Act 104-0001']],'vetoed');
  assert.equal(result.governorSigned,false);
});
test('Public Acts groups real rows, preserves gaps and returns only the selected batch',async()=>{
  const rows=[[101,'HB 1075'],[100,'SB 0126'],[1,'HB 0010']];
  const {reader,calls}=setup(()=>rows.map(([n,bill])=>{
    const act='104-'+String(n).padStart(4,'0');
    return '<tr><td>'+link('/Legislation/PublicActs/View/'+act,act)+'</td><td>'+bill+'</td></tr>';
  }).join(''));
  const index=await reader.publicActs();
  assert.deepEqual(index.ranges,[{first:1,last:100},{first:101,last:101}]);
  assert.deepEqual(index.acts,[]);
  assert.deepEqual((await reader.publicActs(1)).acts.map(a=>a.number),['HB0010','SB0126']);
  const [act]=(await reader.publicActs(101)).acts;
  assert.equal(act.actUrl,'https://www.ilga.gov/Legislation/PublicActs/View/104-0101');
  assert.equal(act.number,'HB1075');
  assert.equal(calls.length,1);
});
