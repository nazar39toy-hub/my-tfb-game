"""Deterministic domain tests; these do not substitute for Roblox Studio tests."""
from pathlib import Path
from lupa import LuaRuntime
ROOT = Path(__file__).resolve().parents[1]
lua = LuaRuntime(unpack_returned_tuples=True)
modules = {}
def require(name):
    if name not in modules:
        modules[name] = lua.execute((ROOT/'src'/f'{name}.lua').read_text())
    return modules[name]
lua.globals().script = lua.table_from({'Parent': lua.table_from({n:n for n in ['WorldConfig','World','Tournaments','Players']})})
lua.globals().require = require
lua.globals().W = require('World')
lua.globals().T = require('Tournaments')
tests = {
'320 stable original clubs, 20 persistent divisions and 30 symmetric rounds': r'''
 local w=W.new(1701); assert(W.validate(w)); local names,ids={},{}; local total=0
 for _,country in ipairs(W.config.COUNTRIES) do
  for div=1,country.divisions do
   local clubs=W.league(w,country.id,div); assert(#clubs==16)
   local rounds=W.schedule(clubs); assert(#rounds==30); local directed={}; local homes={}
   for _,games in ipairs(rounds) do
    assert(#games==8); local played={}
    for _,g in ipairs(games) do
     assert(g[1]~=g[2] and not played[g[1]] and not played[g[2]])
     played[g[1]]=true; played[g[2]]=true
     local key=g[1]..':'..g[2]; assert(not directed[key]); directed[key]=true; homes[g[1]]=(homes[g[1]] or 0)+1
    end
   end
   for _,a in ipairs(clubs) do
    total=total+1; assert(not ids[a.id] and not names[a.name]); ids[a.id]=true; names[a.name]=true; assert(homes[a.id]==15)
    for _,b in ipairs(clubs) do if a.id~=b.id then assert(directed[a.id..':'..b.id] and directed[b.id..':'..a.id]) end end
   end
  end
 end
 assert(total==320 and W.club(w,W.START_CLUB).division==6)
''',
'96 and 32 real-club cup fields, preliminary seeding and five-round brackets': r'''
 local w=W.new(29); local ids={}
 for div=1,6 do for _,c in ipairs(W.league(w,'asteria',div)) do ids[#ids+1]=c.id end end
 local cup=T.newCup(ids,881,'cup','test96'); local round=T.nextRound(cup)
 assert(#round.byes==32 and #round.games==32)
 local seen={}; for _,id in ipairs(round.byes) do assert(not seen[id]); seen[id]=true end
 for _,g in ipairs(round.games) do assert(not seen[g.homeId] and not seen[g.awayId]); seen[g.homeId]=true; seen[g.awayId]=true end
 local rounds=0; while not cup.winner do assert(T.advance(cup,w)); rounds=rounds+1 end
 assert(rounds==7 and seen[cup.winner]); assert(not T.advance(cup,w))
 local small={}; for i=1,32 do small[i]=ids[i] end
 cup=T.newCup(small,11,'cup','test32'); assert(#T.nextRound(cup).byes==0)
 rounds=0; while not cup.winner do T.advance(cup,w); rounds=rounds+1 end assert(rounds==5)
''',
'International qualification is unique with explicit duplicate-winner fallback': r'''
 local w=W.new(10); local all,cups={},{}
 for _,c in ipairs(W.config.COUNTRIES) do all[c.id]={[1]=W.simulateLeague(w,c.id,1)}; cups[c.id]=all[c.id][1][1].id end
 local q,super=W.qualify(all,cups); assert(#q.champions==16 and #q.challenge==16)
 local seen={}; for _,id in ipairs(q.champions) do assert(not seen[id]); seen[id]=true end
 for _,id in ipairs(q.challenge) do assert(not seen[id]); seen[id]=true end
 for _,c in ipairs(W.config.COUNTRIES) do
  assert(super[c.id][1]~=super[c.id][2]); assert(super[c.id][2]==all[c.id][1][2].id)
  assert(seen[all[c.id][1][4].id])
 end
''',
'Unified fixture order, no menu RNG changes, duplicate finalization rejected': r'''
 local w=W.new(91); local id=W.START_CLUB; local state=T.new(w,id,1,112)
 local op=T.next(state,w,id); assert(op.kind=='friendly' and op.date==1)
 for i=1,20 do local again=T.next(state,w,id); assert(again.matchId==op.matchId and state.date==0) end
 local r=T.finish(state,w,id,op,2,1); assert(r and not r.title)
 local duplicate,why=T.finish(state,w,id,op,2,1); assert(not duplicate and why=='STALE_MATCH')
 local lastDate=1; local league=0; local cup=0
 while true do
  local nextOp=T.next(state,w,id); if not nextOp then break end
  assert(nextOp.date>lastDate); lastDate=nextOp.date
  if nextOp.kind=='league' then league=league+1; assert(nextOp.round==league)
  elseif nextOp.kind=='cup' then cup=cup+1 end
  T.finish(state,w,id,nextOp,0,1,false)
 end
 assert(state.done and league==30 and cup==1 and lastDate==120)
 for _,c in ipairs(W.config.COUNTRIES) do assert(w.cupWinners[c.id] and w.clubs[w.cupWinners[c.id]]) end
''',
'35 seasons preserve identities, 16-club divisions, reciprocal promotion and growing records': r'''
 local w=W.new(771); local originalNames={}; for id,c in pairs(w.clubs) do originalNames[id]=c.name end
 local first=W.club(w,W.START_CLUB); local initialRating=first.rating; local id=W.START_CLUB
 for season=1,35 do
  local club=W.club(w,id); local clubs=W.league(w,club.country,club.division); local tableRows,byId={},{}
  for _,c in ipairs(clubs) do
   local row={id=c.id,name=c.name,rating=c.rating,pts=0,gf=0,ga=0,w=0,d=0,l=0,played=0}; tableRows[#tableRows+1]=row; byId[c.id]=row
  end
  local schedule=W.schedule(clubs)
  -- The actual played user results and all NPC round results feed the same league table.
  local input={country=club.country,division=club.division,table=tableRows}
  local state=T.new(w,id,w.season,w.seed+season)
  local nextOp=T.next(state,w,id)
  while nextOp do
   if nextOp.kind=='league' then
    local rng=W.rng(w.seed+season*701+nextOp.round*29)
    for _,game in ipairs(schedule[nextOp.round]) do
     local x,y
     if game[1]==id then x,y=2,1 elseif game[2]==id then x,y=1,2 else x,y=W.simScore(rng,w.clubs[game[1]].rating,w.clubs[game[2]].rating) end
     W.record(byId[game[1]],byId[game[2]],x,y)
    end
   end
   T.finish(state,w,id,nextOp,2,1,true); nextOp=T.next(state,w,id)
  end
  local country=club.country; local division=club.division; local order={}
  for i,r in ipairs(W.sorted(tableRows)) do order[r.id]=i end
  W.advanceSeason(w,input,id); assert(W.validate(w)); assert(w.season==season+1)
  for cid,c in pairs(w.clubs) do assert(c.name==originalNames[cid]); assert(c.rating>=36 and c.rating<=94); assert(c.records.played==season*30) end
  for cid,rank in pairs(order) do
   local expected=division
   if rank<=2 and division>1 then expected=division-1 elseif rank>=15 and division<6 then expected=division+1 end
   assert(w.clubs[cid].division==expected)
  end
  assert(#w.qualifications.champions==16 and #w.qualifications.challenge==16)
 end
 assert(w.records.seasons==35 and #w.history==35 and w.clubs[id].division==1)
 assert(first.generation>1 and first.records.played==1050)
''',
'Simulated penalty shootouts record football kicks and reproducible winners': r'''
 for seed=1,100 do
  local win,p=T.penalties(W.rng(seed),70,70); local same,q=T.penalties(W.rng(seed),70,70)
  assert(win==same and p.home==q.home and p.away==q.away and p.home~=p.away and #p.kicks>=6)
  local a,b=0,0; for _,kick in ipairs(p.kicks) do if kick.scored then if kick.team==1 then a=a+1 else b=b+1 end end end
  assert(a==p.home and b==p.away)
 end
''',
}
for name, body in tests.items():
    lua.execute(body)
    print('PASS',name)
print(f'PASS {len(tests)} world test groups (Lua via lupa; no Studio)')
