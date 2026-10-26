"""Deterministic domain regressions. Lua via lupa; not a Studio playtest."""
from pathlib import Path
import json, time
from lupa import LuaRuntime
ROOT=Path(__file__).resolve().parents[1]
lua=LuaRuntime(unpack_returned_tuples=True)
module_cache={}
parent=lua.table_from({p.stem:p.stem for p in (ROOT/'src').glob('*.lua')})
lua.globals().script=lua.table_from({'Parent':parent})
def require(name):
    name=str(name)
    if name not in module_cache:
        module_cache[name]=lua.execute((ROOT/'src'/f'{name}.lua').read_text())
    return module_cache[name]
lua.globals().require=require
lua.globals().M=require('Match')
lua.execute('''
C={}
function C.rng(seed)
 local state=math.max(1,math.floor(seed or 1)%2147483647)
 return function(a,b) state=state*48271%2147483647; local n=state/2147483647; if a then return math.floor(a+n*(b-a+1)) end; return n end
end
function C.find(p,id) for _,q in ipairs(p.roster) do if q.id==id then return q end end end
function C.effective(p,q,role) return q.rating*(q.pos==role and 1 or .82)*(.7+.3*q.fitness/100) end
function fixture(seed,home,kind)
 local p={formation='4-3-3',roster={},lineup={},style='possession',difficulty='normal'}
 local roles={'GK','DEF','DEF','DEF','DEF','MID','MID','MID','FWD','FWD','FWD','GK','DEF','MID','FWD','MID','DEF','FWD'}
 for i,role in ipairs(roles) do
  local q={id='p'..i,name='Player '..i,pos=role,rating=60,fitness=100,attributes={pace=60,shooting=60,passing=60,dribbling=60,defending=60,physical=60,goalkeeping=60}}
  p.roster[i]=q; if i<=11 then p.lineup[i]=q.id end
 end
 local op={name='Opponent',rating=60,home=home~=false,kind=kind or 'league',id='m'..seed}
 return p,op,M.new(p,op,C,seed)
end
''')
checks=[]
def test(name,code):
    start=time.perf_counter(); lua.execute(code); checks.append({'name':name,'status':'PASS','seconds':round(time.perf_counter()-start,3)}); print('PASS',name)

test('22 role-adjusted footballers and venue semantics', '''
 local p,o,m=fixture(1,true)
 assert(#m.players==22 and m.direction==1 and m.userHome)
 assert(m.players[2].rating>m.players[13].rating)
 p.roster[2].pos='FWD'
 local a=M.new(p,o,C,1)
 assert(a.players[2].rating<m.players[2].rating)
 local _,_,away=fixture(1,false)
 assert(away.direction==-1 and not away.userHome and away.players[1].x>50)
 assert(away.players[2].rating<away.players[13].rating)
''')
test('Halftime and extra-time switch ends', '''
 local p,o,m=fixture(2,true,'cup')
 m.pause=0; m.t=m.regulation/2; M.step(m,.05)
 assert(m.half==2 and m.direction==-1 and m.phase=='halftime')
 m.pause=0; m.t=m.regulation; M.step(m,.05)
 assert(m.extra and m.half==3 and not m.ended)
 m.pause=0; m.t=m.regulation+M.Config.extraTime/2; M.step(m,.05)
 assert(m.half==4 and m.direction==1)
 m.pause=0; m.t=m.extraEnd; M.step(m,.05)
 assert(m.phase=='penalties' and m.penalties.turn==1)
''')
test('Goals, assists and own goals are user-oriented on away venue', '''
 local _,_,m=fixture(3,false)
 m.pause=0; m.owner=nil; m.ball={x=.1,y=32,vx=-49,vy=0}; m.lastTouch=10; m.lastPass=8
 M.step(m,.05)
 assert(m.home==1 and m.away==0 and m.scorers.p10==1 and m.assists.p8==1)
 assert(m.replayId==1)
 m.pause=0; m.owner=nil; m.ball={x=.1,y=32,vx=-49,vy=0}; m.lastTouch=14; m.lastPass=nil
 M.step(m,.05)
 assert(m.home==2 and m.scorers.p10==1 and m.ownGoals.cpu3==1)
 local snap=M.snapshot(m); assert(snap.home==2 and not snap.userHome and snap.attackDirection==-1)
''')
test('Throw-ins, corners and goal kicks have correct beneficiary', '''
 local _,_,m=fixture(4,true)
 m.pause=0; m.owner=nil; m.lastTouch=10; m.ball={x=50,y=63.9,vx=0,vy=10}; M.step(m,.05)
 assert(m.restartKind=='throwIn' and m.players[m.owner].team==2)
 m.pause=0; m.owner=nil; m.lastTouch=13; m.ball={x=99.9,y=5,vx=15,vy=0}; M.step(m,.05)
 assert(m.restartKind=='corner' and m.players[m.owner].team==1 and m.stats[1].corners==1)
 m.pause=0; m.owner=nil; m.lastTouch=10; m.ball={x=99.9,y=5,vx=15,vy=0}; M.step(m,.05)
 assert(m.restartKind=='goalKick' and m.players[m.owner].team==2)
''')
test('Simplified offside on targeted forward pass', '''
 local _,_,m=fixture(5,true)
 m.pause=0; m.owner=8; m.players[8].x=55; m.players[10].x=94
 for i=12,22 do m.players[i].x=70 end
 assert(not M.kick(m,8,94,32,false,.7,10))
 assert(m.restartKind=='offside' and m.players[m.owner].team==2 and m.stats[1].offsides==1)
''')
test('Red cards remove players; substitutions cannot restore them', '''
 local _,_,m=fixture(6,true)
 M.sendOff(m,2)
 assert(not m.players[2].active and m.players[2].sentOff and m.redCards.p2==1)
 assert(not M.substitute(m,'p2','p13'))
 assert(M.substitute(m,'p3','p13'))
 assert(m.players[3].id=='p13' and m.players[3].active and m.substitutions==1)
 assert(not M.substitute(m,'p4','p13'))
 local s=M.snapshot(m); assert(s.players[2].active==false)
''')
test('Penalty shootout decisions, early finish and no repeated finish', '''
 local _,_,m=fixture(7,true,'cup'); M.startPenalties(m)
 for i=1,6 do
  if m.ended then break end
  m.penalties.execution=m.penalties.turn==1 and 0 or 1
  assert(M.penalty(m,{aim=.8,power=.8,dive=-1}))
 end
 assert(m.ended and m.penWin and m.penalties.scores[1]==3 and m.penalties.scores[2]==0)
 local count=#m.penalties.history; M.step(m,.05)
 assert(not M.penalty(m,{aim=0}) and #m.penalties.history==count)
''')
test('Snapshots and mode switching do not advance RNG', '''
 local _,_,a=fixture(8,true); local _,_,b=fixture(8,true)
 M.setMode(a,'simulate'); M.setMode(b,'simulate')
 M.snapshot(a); M.snapshot(a); M.setMode(a,'manual'); M.setMode(a,'highlights'); M.setMode(a,'simulate')
 for i=1,1000 do M.step(a,.05); M.step(b,.05) end
 assert(a.home==b.home and a.away==b.away and a.rng()==b.rng())
 for i=1,22 do assert(a.players[i].x==b.players[i].x and a.players[i].y==b.players[i].y) end
''')
test('Sprinting is bounded by stamina; invalid values cannot poison state', '''
 local _,_,a=fixture(9,true); local _,_,b=fixture(9,true)
 a.pause=0; b.pause=0; a.input={x=1,y=0}; b.input={x=1,y=0}; a.sprint=true
 for i=1,50 do M.step(a,.05); M.step(b,.05) end
 assert(a.players[10].fitness<b.players[10].fitness)
 a.input={x=0/0,y=math.huge}; M.step(a,.05); M.step(a,0/0)
 for _,p in ipairs(a.players) do assert(p.x==p.x and p.y==p.y and p.fitness>=0 and p.fitness<=100) end
''')
test('Deterministic complete simulation and bounded replay/events', '''
 for seed=1,4 do
  local p,o=fixture(seed,true,seed%2==0 and 'cup' or 'league')
  local a=M.simulate(p,o,C,seed); local b=M.simulate(p,o,C,seed)
  assert(a.ended and b.ended and a.t>=M.Config.duration)
  assert(a.home==b.home and a.away==b.away and a.penWin==b.penWin)
  assert(#a.events<=M.Config.eventLimit and #a.replay<=M.Config.replayFrames)
  for _,q in ipairs(a.players) do assert(q.x==q.x and q.x>=0 and q.x<=100 and q.y>=0 and q.y<=64) end
  local s=M.statistics(a)
  assert(s.playerOfMatch and s.teams[1].passAccuracy<=100 and s.teams[2].passAccuracy<=100)
  if a.home==a.away and o.kind=='cup' then assert(type(a.penWin)=='boolean') end
 end
''')
(ROOT/'tests'/'MATCH_RESULTS.json').write_text(json.dumps({'environment':'Lua via lupa; domain tests, not Roblox Studio','checks':checks},ensure_ascii=False,indent=2))
print(f'ALL {len(checks)} MATCH GROUPS PASSED')
