from pathlib import Path
from lupa import LuaRuntime
import json
ROOT=Path(__file__).resolve().parents[1]
lua=LuaRuntime(unpack_returned_tuples=True)
C=lua.execute((ROOT/'src/Career.lua').read_text())
M=lua.execute((ROOT/'src/Match.lua').read_text())
lua.globals().C=C; lua.globals().M=M
results=[]
def test(name,code):
    lua.execute(code); results.append(name); print('PASS',name)
for f in (ROOT/'src').glob('*.lua'):
    loaded=lua.eval('function(s) local f,e=load(s); assert(f,e); return true end')(f.read_text())
    results.append('Syntax: '+f.name)
test('Round robin: 14 rounds, each pair home and away once', '''
 local s=C.schedule(); local pairs={}
 assert(#s==14)
 for _,r in ipairs(s) do
  assert(#r==4); local seen={}
  for _,g in ipairs(r) do assert(not seen[g[1]] and not seen[g[2]]); seen[g[1]]=true; seen[g[2]]=true
   local k=g[1]..':'..g[2]; assert(not pairs[k]); pairs[k]=true
  end
 end
 local n=0; for _ in pairs(pairs) do n=n+1 end
'''.replace('local pairs={}', 'local games={}').replace('pairs[k]', 'games[k]').replace('pairs(pairs)', 'pairs(games)')+' assert(n==56)')
test('Transfers: exact budget, no duplicate buys, lineup sale rejected', '''
 local p=C.new(101); local id=p.market[1].id; local price=p.market[1].price; p.cash=10000000; local before=p.cash
 assert(C.action(p,'buy',{id=id})); assert(p.cash==before-price); assert(#p.roster==19)
 local money=p.cash; assert(not C.action(p,'buy',{id=id})); assert(p.cash==money)
 assert(not C.action(p,'sell',{id=p.lineup[1]})); assert(C.action(p,'sell',{id=id})); assert(#p.roster==18)
 p.cash=0; local count=#p.roster; assert(not C.action(p,'buy',{id=p.market[1].id})); assert(#p.roster==count)
''')
test('Lineup swaps remain unique and formations contain 11 roles', '''
 local p=C.new(2); local a,b=p.lineup[1],p.lineup[2]
 assert(C.action(p,'swap',{slot=1,id=b})); assert(p.lineup[2]==a and p.lineup[1]==b)
 local bench=p.roster[18].id; assert(C.action(p,'swap',{slot=11,id=bench}))
 local seen={}; for _,id in ipairs(p.lineup) do assert(not seen[id]); seen[id]=true end
 assert(not C.action(p,'swap',{slot=0,id=bench})); assert(not C.action(p,'swap',{slot=0/0,id=bench}))
 for _,f in ipairs(C.formations) do assert(#C.roles(f)==11) end
''')
test('Academy once per season; upgrades price and level cap', '''
 local p=C.new(3); p.cash=100000000
 assert(C.action(p,'academy')); assert(#p.roster==19 and p.roster[19].age==16)
 assert(not C.action(p,'academy'))
 for i=1,9 do local cash=p.cash; assert(C.action(p,'upgrade',{key='training'})); assert(p.cash==cash-i*i*80000) end
 assert(not C.action(p,'upgrade',{key='training'})); assert(p.upgrades.training==10)
''')
test('Cup: win all three rounds, no replay and trophy reward', '''
 local p=C.new(8)
 for i=1,3 do local op=C.next(p,'cup'); assert(op); C.finish(p,op,2,1) end
 assert(p.cupDone and p.trophies==1); assert(not C.next(p,'cup'))
''')
test('Season promotion, prize money, retirement and new calendar', '''
 local p=C.new(9); p.roster[1].age=35; local old=p.lineup[1]
 for i=1,14 do local op=C.next(p,'league'); assert(op); C.finish(p,op,4,0) end
 assert(p.round==15); assert(not C.next(p,'league')); assert(p.league[1].pts==42)
 for _,t in ipairs(p.league) do assert(t.played==14) end
 assert(not C.action(p,'season')); C.finish(p,C.next(p,'cup'),0,1)
 assert(C.action(p,'season')); assert(p.season==2 and p.division==2 and p.round==1)
 assert(p.lineup[1]~=old and C.find(p,p.lineup[1]).age==17)
''')
test('Twenty full careers: economy, roster and fitness invariants', '''
 for seed=1,20 do
  local p=C.new(seed); local rng=C.rng(seed+5)
  for season=1,12 do
   for round=1,14 do
    local op=C.next(p,'league'); local x,y=C.sim(rng,C.strength(p),op.rating); C.finish(p,op,x,y)
    if round%3==0 then C.action(p,'rest') end
    for _,q in ipairs(p.roster) do assert(q.fitness>=0 and q.fitness<=100) end
   end
   while p.cupAlive and not p.cupDone do local op=C.next(p,'cup'); C.finish(p,op,1,1,{}, {},rng()<.5) end
   assert(C.action(p,'season')); assert(p.cash>=0 and #p.lineup==11 and #p.history<=40)
   assert(p.division>=1 and p.division<=3)
  end
 end
''')
test('Match commands, finite bounds, 22 players, ending', '''
 for seed=1,30 do
  local p=C.new(seed); local m=M.new(p,C.next(p,'league'),C,seed)
  assert(#m.players==22)
  for tick=1,4200 do
   if tick%30==0 then M.command(m,'pass',{}) end
   if tick%45==0 then M.command(m,'shoot',{y=32}) end
   if tick%15==0 then M.switch(m); M.command(m,'tackle',{}) end
   m.input={x=math.sin(tick*.05),y=math.cos(tick*.04)}
   M.step(m,.05)
   for _,q in ipairs(m.players) do assert(q.x==q.x and q.x>=0 and q.x<=100 and q.y>=0 and q.y<=64) end
   if m.ended then break end
  end
  assert(m.ended and m.t>=120 and m.home>=0 and m.away>=0)
 end
''')
test('Goal detection, own goals, out of bounds and score snapshots', '''
 local p=C.new(45); local m=M.new(p,C.next(p,'league'),C,45)
 m.pause=0; m.owner=nil; m.ball={x=99.9,y=32,vx=49,vy=0}; m.lastTouch=10
 M.step(m,.05); assert(m.home==1 and m.scorers[p.lineup[10]]==1 and m.owner==21)
 m.pause=0; m.owner=nil; m.ball={x=.1,y=32,vx=-49,vy=0}; m.lastTouch=15
 M.step(m,.05); assert(m.away==1)
 m.pause=0; m.owner=nil; m.ball={x=99.9,y=5,vx=49,vy=0}
 M.step(m,.05); assert(m.home==1 and m.owner==12)
 local snap=M.snapshot(m); assert(#snap.players==22 and snap.home==1 and snap.away==1)
''')
(ROOT/'TEST_RESULTS.json').write_text(json.dumps({'runtime':str(lua.eval('_VERSION'))+' via lupa; not Roblox Studio','passed':results,'count':len(results)},ensure_ascii=False,indent=2))
print(f'ALL {len(results)} CHECK GROUPS PASSED')
