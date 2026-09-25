"""Verified feed previews and private, authenticated problem reports."""
import json,time,uuid,re
from contextlib import closing
from flask import request,jsonify,g,current_app

def preview(report):
 if report.get('status')!='ready':return None
 if report.get('kind')=='quarterly':
  summary=report.get('summary') or {}
  return dict(kind='quarterly',period=report.get('period'),beginning_cash=summary.get('beginning_cash'),receipts=summary.get('receipts'),expenditures=summary.get('expenditures'),ending_cash=summary.get('ending_cash'),cash_and_investments=summary.get('cash_and_investments'))
 contributions=report.get('contributions') or []
 if contributions:
  names=list(dict.fromkeys(re.split(r'\s+(?:Occupation|Employer):',x['contributor'],maxsplit=1)[0].strip() for x in contributions))
  return dict(kind='a1',includes_in_kind=any('in-kind' in x.get('contribution_type','').lower() for x in contributions),total=report.get('total'),contribution_count=len(contributions),contributors=names[:2],contributor_count=len(names))
 return None

def install(app,store,authenticated,reader):
 from summary_loader import SummaryLoader
 from subscriptions import lookup_filing
 loader=SummaryLoader(store,reader)
 @app.get('/v1/summary-previews')
 @authenticated
 def summary_previews():
  try:
   ids=list(dict.fromkeys(int(x) for x in request.args.get('ids','').split(',')))
   if not 1<=len(ids)<=50 or any(abs(x)>2**63-1 for x in ids):raise ValueError()
  except ValueError:return jsonify(error='Provide 1 to 50 valid report IDs.'),400
  results=[]
  with closing(store.connect()) as db:
   rows=[lookup_filing(db,seq) for seq in ids]
  for seq,row in zip(ids,rows):
   if row is None:results.append(dict(seq=seq,status='unsupported',preview=None));continue
   filing=dict(row);state=loader.snapshot(filing)
   if state['status']=='loading':loader.schedule(filing,priority=0)
   results.append(dict(seq=seq,**state))
  return jsonify(summaries=results)

 with closing(store.connect()) as db,db:
  db.execute('''CREATE TABLE IF NOT EXISTS problem_reports(id TEXT PRIMARY KEY,device_id TEXT NOT NULL,created REAL NOT NULL,category TEXT NOT NULL,message TEXT NOT NULL,context TEXT NOT NULL,status TEXT NOT NULL DEFAULT 'new')''')
  db.execute('CREATE INDEX IF NOT EXISTS problem_reports_device ON problem_reports(device_id,created)')
 @app.after_app_request
 def add_previews(response):
  if request.method!='GET' or response.status_code!=200 or not response.is_json:return response
  data=response.get_json()
  if not isinstance(data,dict) or not isinstance(data.get('filings'),list):return response
  rows=data['filings']
  for i,row in enumerate(rows):
   if not isinstance(row,dict) or 'seq' not in row:continue
   state=loader.snapshot(row)
   row['preview']=state['preview'];row['preview_status']=state['status']
   if i<8 and state['status']=='loading' and current_app.config.get('PRELOAD_SUMMARIES',True):loader.schedule(row)
  response.set_data(current_app.json.dumps(data));return response
 @app.post('/v1/me/problems')
 @authenticated
 def report_problem():
  if request.content_length and request.content_length>16000:return jsonify(error='Report is too long.'),413
  data=request.get_json(silent=True)
  if not isinstance(data,dict):return jsonify(error='Invalid report.'),400
  message=data.get('message');category=data.get('category');context=data.get('context',{})
  if not isinstance(message,str) or not 10<=len(message.strip())<=4000:return jsonify(error='Please enter between 10 and 4,000 characters.'),400
  if category not in ('Incorrect data','Missing report','App issue','Other'):return jsonify(error='Choose a problem type.'),400
  if not isinstance(context,dict) or any(not isinstance(k,str) or not isinstance(v,str) or len(v)>1000 for k,v in context.items()) or len(context)>10:return jsonify(error='Invalid context.'),400
  with closing(store.connect()) as db,db:
   if db.execute('SELECT count(*) FROM problem_reports WHERE device_id=? AND created>?',(g.device['id'],time.time()-3600)).fetchone()[0]>=5:return jsonify(error='Please wait before sending another report.'),429
   identifier=uuid.uuid4().hex[:12]
   db.execute('INSERT INTO problem_reports(id,device_id,created,category,message,context) VALUES (?,?,?,?,?,?)',(identifier,g.device['id'],time.time(),category,message.strip(),json.dumps(context)))
  current_app.logger.info('Problem report received: %s',identifier)
  return jsonify(id=identifier),201
 @app.get('/v1/me/problems')
 @authenticated
 def my_problems():
  with closing(store.connect()) as db:
   rows=[dict(r) for r in db.execute('SELECT id,created,category,message,context,status FROM problem_reports WHERE device_id=? ORDER BY created DESC LIMIT 50',(g.device['id'],))]
  return jsonify(reports=rows)
