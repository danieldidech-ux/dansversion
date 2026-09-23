"""Verified feed previews and private, authenticated problem reports."""
import json,time,uuid,re
from contextlib import closing
from flask import request,jsonify,g,current_app

def preview(report):
 if report.get('status')!='ready':return None
 if report.get('kind')=='quarterly':
  summary=report.get('summary') or {}
  return dict(kind='quarterly',period=report.get('period'),receipts=summary.get('receipts'),expenditures=summary.get('expenditures'),ending_cash=summary.get('ending_cash'))
 contributions=report.get('contributions') or []
 if contributions:
  names=list(dict.fromkeys(re.split(r'\s+(?:Occupation|Employer):',x['contributor'],maxsplit=1)[0].strip() for x in contributions))
  return dict(kind='a1',includes_in_kind=any('in-kind' in x.get('contribution_type','').lower() for x in contributions),total=report.get('total'),contribution_count=len(contributions),contributors=names[:2],contributor_count=len(names))
 return None

def install(app,store,authenticated):
 with closing(store.connect()) as db,db:
  db.execute('''CREATE TABLE IF NOT EXISTS problem_reports(id TEXT PRIMARY KEY,device_id TEXT NOT NULL,created REAL NOT NULL,category TEXT NOT NULL,message TEXT NOT NULL,context TEXT NOT NULL,status TEXT NOT NULL DEFAULT 'new')''')
  db.execute('CREATE INDEX IF NOT EXISTS problem_reports_device ON problem_reports(device_id,created)')
 @app.after_app_request
 def add_previews(response):
  if request.method!='GET' or response.status_code!=200 or not response.is_json:return response
  data=response.get_json()
  if not isinstance(data,dict) or not isinstance(data.get('filings'),list):return response
  rows=data['filings'];ids=[r['seq'] for r in rows if isinstance(r,dict) and 'seq' in r]
  if ids:
   with closing(store.connect()) as db:
    records=db.execute('SELECT seq,payload FROM shared_reports WHERE seq IN ('+','.join('?' for _ in ids)+')',ids).fetchall()
   previews={}
   for seq,payload in records:
    try:previews[seq]=preview(json.loads(payload))
    except (ValueError,KeyError,TypeError):continue
   for row in rows:row['preview']=previews.get(row.get('seq'))
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
