"""System Lua 5.4 regressions. Not Roblox Studio."""
from pathlib import Path
import ctypes as c,json,time,ast
ROOT=Path(__file__).resolve().parents[1]
l=c.CDLL('liblua5.4.so.0');l.luaL_newstate.restype=c.c_void_p
for n,args,ret in [('luaL_openlibs',[c.c_void_p],None),('luaL_loadstring',[c.c_void_p,c.c_char_p],c.c_int),('lua_pcallk',[c.c_void_p,c.c_int,c.c_int,c.c_int,c.c_longlong,c.c_void_p],c.c_int),('lua_tolstring',[c.c_void_p,c.c_int,c.c_void_p],c.c_char_p),('lua_settop',[c.c_void_p,c.c_int],None)]:
 f=getattr(l,n);f.argtypes=args;f.restype=ret
state=l.luaL_newstate();l.luaL_openlibs(state)
def run(code):
 if l.luaL_loadstring(state,code.encode()) or l.lua_pcallk(state,0,0,0,0,None):
  err=l.lua_tolstring(state,-1,None).decode();l.lua_settop(state,0);raise RuntimeError(err)
 l.lua_settop(state,0)
run("script={Parent=setmetatable({},{__index=function(_,k)return k end})}; local cache={}; function require(n) if not cache[n] then cache[n]=assert(loadfile('"+str(ROOT/'src')+"/'..n..'.lua'))() end; return cache[n] end")
run('NATIVE_REQUIRE=require')
results=[]
def test(name,code):
 t=time.perf_counter()
 try:run(code.replace('/workspace/TouchlineDynasty',str(ROOT)));status='PASS';detail='assertions passed'
 except Exception as e:status='FAIL';detail=str(e)
 results.append(dict(name=name,status=status,detail=detail,seconds=round(time.perf_counter()-t,3)));print(status,name,detail,flush=True)
for p in sorted((ROOT/'src').glob('*.lua')):test('syntax '+p.name,'assert(loadfile('+json.dumps(str(p))+'))')
run("W=require('World');T=require('Tournaments');M=require('Match')")
for filename in ['test_world.py','test_match.py']:
 tree=ast.parse((ROOT/'tests'/filename).read_text())
 for node in ast.walk(tree):
  if isinstance(node,ast.Call) and isinstance(node.func,ast.Attribute) and node.func.attr=='execute' and node.args and isinstance(node.args[0],ast.Constant) and isinstance(node.args[0].value,str) and 'function fixture' in node.args[0].value:run(node.args[0].value)
 for node in tree.body:
  if isinstance(node,ast.Expr) and isinstance(node.value,ast.Call) and isinstance(node.value.func,ast.Name) and node.value.func.id=='test':
   test(ast.literal_eval(node.value.args[0]),ast.literal_eval(node.value.args[1]))
 for node in ast.walk(tree):
  if isinstance(node,ast.Assign) and any(isinstance(t,ast.Name) and t.id=='tests' for t in node.targets) and isinstance(node.value,ast.Dict):
   for k,v in zip(node.value.keys,node.value.values):test(ast.literal_eval(k),ast.literal_eval(v))
test('career 31 seasons with forfeit and duplicate finalization',r'''
C=require('Career');p=C.new(77);assert(C.validate(p));local count=0
for season=1,31 do
 local op=C.next(p)
 while op do
  local income,code=C.finish(p,op,0,3,{},{},false,{forfeit=true});assert(income~=nil,code)
  local cash=p.cash;local date=p.date;local twice=C.finish(p,op,0,3,{},{},false,{forfeit=true});assert(twice==0 and cash==p.cash and date==p.date)
  count=count+1;assert(count<3000);op=C.next(p)
 end
 local ok,err=C.action(p,'season',{});assert(ok,err);local valid,why=C.validate(p);assert(valid,why)
end
assert(p.season==32)
''')
test('goalkeeper reservation prevents a hole after roster turnover',r"""
local p=C.new(66);local reserve
for _,q in ipairs(p.roster)do if q.pos=='GK' and q.id~=p.lineup[1]then reserve=q;break end end
assert(reserve);local first=p.lineup[1];for i,q in ipairs(p.roster)do if q.id==first then table.remove(p.roster,i);break end end;p.lineup[2]=reserve.id
assert(C.repairLineup(p));assert(C.find(p,p.lineup[1]).pos=='GK');assert(C.validate(p))
""")
test('free agent immediate resale and no repeat purchase',r"""
local p=C.new(91);local bought=false;for _,q in ipairs(p.market) do if q.free then local id=q.id;local ok=C.action(p,'buy',{id=id});if ok then bought=true;local cash=p.cash;assert(not C.action(p,'sell',{id=id}));assert(p.cash==cash);assert(not C.action(p,'buy',{id=id})) end;break end end;assert(bought,'free-agent regression must execute a purchase')
""")
test('legacy v1 migration preserves club assets and does not repeat',r"""
local legacy=assert(loadfile("/workspace/TouchlineDynasty/baseline/src/Career.lua"))();local old=legacy.new(21);old.cash=1234567;old.trophies=7;local p=C.migrate(old);assert(p.version==2 and p.cash==1234567 and p.trophies==7 and p.roster[1].id==old.roster[1].id);assert(C.validate(p));assert(C.migrate(p)==p)
""")
test('localization: locale, fallback, numbers and expanded strings',r"""
local L=require('Localization');local ru=L.new({locale='ru'});assert(ru:t('ui.play')=='Играть матч');assert(L.resolve('auto','uk-UA')=='uk');assert(L.resolve('auto','ar-001')=='en');assert(#L.pseudo('Football management')>#'Football management');assert(L.t('ui.play',{},'en')=='Play match')
""")
test('training isolation, fixed challenge, exact-once cosmetics and tutorial steps',r"""
local A=require('Training');local C=require('Career');local M=require('Match');local p=C.new(500);local original=C.copy(p)
local m=A.new('passing',C,M);assert(m.duration==90 and m.training.kind=='passing');assert(not A.new('invalid',C,M))
m.stats[1].completed=5;A.observe(m);assert(not m.training.success);m.stats[1].completed=6;A.observe(m);assert(m.ended and m.training.success)
local result=A.finish(p,m,false,M);assert(result.cosmeticReward==25 and p.cosmetics.tokens==25);assert(A.finish(p,m,false,M).cosmeticReward==0)
assert(p.cash==original.cash and p.date==original.date and p.round==original.round and p.roster[1].xp==original.roster[1].xp)
local f=A.new('finishing',C,M);f.stats[1].onTarget=3;A.observe(f);assert(A.finish(p,f,true,M).cosmeticReward==0);assert(p.cosmetics.tokens==25)
local t=A.new('tutorial',C,M);local q=t.players[t.controlled];q.x=q.x+4;A.observe(t);assert(t.training.step==2);t.stats[1].completed=1;A.observe(t);assert(t.training.step==3);t.stats[1].shots=1;A.observe(t);assert(t.training.success);A.finish(p,t,false,M);assert(not p.tutorial and C.validate(p))
for _,style in ipairs(C.styles)do assert(M.Config.styles[style],style);local fixture=M.new(p,C.next(p),C,77);assert(M.command(fixture,'style',{value=style}))end
local fixture=M.new(p,C.next(p),C,77);assert(M.command(fixture,'teamTalk',{}));assert(M.command(fixture,'teamTalk',{}));assert(not M.command(fixture,'teamTalk',{}))
""")
test('record categories, anomalous values, monotonic writes and throttled reads',r"""
local R=require('Records');local C=require('Career');local p=C.new(17)
R.record(p,{mode='manual',home=2,away=1});assert(p.records.categories.manual_normal.points==3)
R.record(p,{mode='simulate',home=0,away=0});assert(p.records.categories.simulate_normal.points==1)
R.record(p,{mode='mixed',home=5,away=0});assert(not p.records.categories.mixed_normal)
R.record(p,{mode='manual',home=3,away=0,forfeit=true});assert(p.records.categories.manual_normal.points==3)
local now,calls,value=0,0,0;local store={}
function store:UpdateAsync(key,fn)calls=calls+1;value=fn(value);return value end
function store:GetSortedAsync()calls=calls+1;return{GetCurrentPage=function()return{{key='17',value=value}}end}end
local service={GetOrderedDataStore=function(_,name)assert(name:find('TD_TEST_records_v2_',1,true)==1);return store end}
local adapter=R.adapter(service,true,function()return now end)
assert(not adapter.publish(17,nil,10));assert(not adapter.publish(17,'manual_normal',0/0));assert(adapter.publish(17,'manual_normal',3));assert(not adapter.publish(17,'manual_normal',4));now=121;assert(adapter.publish(17,'manual_normal',1));assert(value==3)
local rows=adapter.read('manual','normal');assert(rows[1].points==3);local old=calls;adapter.read('manual','normal');assert(calls==old)
local M=require('Match');local m=M.new(p,C.next(p),C,5);m.t=1;M.setMode(m,'highlights');assert(m.recordMode=='mixed')
""")
test('automatic XI selects strongest eligible goalkeeper and roles',r"""
local C=require('Career');local p=C.new(101);local original=C.strength(p);local keepers={};for _,q in ipairs(p.roster)do if q.pos=='GK'then keepers[#keepers+1]=q end end
assert(#keepers>=2);for key in pairs(keepers[2].attributes)do keepers[2].attributes[key]=95 end;keepers[2].rating=95;keepers[2].potential=99
assert(C.action(p,'autoLineup',{}));assert(p.lineup[1]==keepers[2].id);assert(C.strength(p)>=original);assert(C.validate(p))
""")
test('highlights control is limited to episodes and shootouts stay manual',r"""
local C=require('Career');local M=require('Match');local p=C.new(44);local m=M.new(p,C.next(p),C,44);M.setMode(m,'highlights');m.pause=0;m.owner=10;m.players[10].x=50;assert(not M.interactive(m));assert(not M.command(m,'pass',{}));m.players[10].x=80;assert(M.interactive(m));assert(M.snapshot(m).interactive)
M.startPenalties(m);local before=m.penalties.taken[1];M.step(m,.05);assert(m.penalties.taken[1]==before)
""")
test('full roster suspensions cannot deadlock finalization or farm technical defeats',r"""
local C=require('Career');local p=C.new(133);local serial=1
while #p.roster<30 do local q=C.copy(p.roster[2]);q.id='extra:'..serial;serial=serial+1;p.roster[#p.roster+1]=q end
for _,q in ipairs(p.roster)do q.suspension=2 end
local cash=p.cash;local xp=p.roster[1].xp;assert(not C.repairLineup(p));assert(C.validate(p));assert(not C.isPlayable(p));assert(C.public(p).squadUnavailable)
for i=1,2 do local op=C.next(p);local income,code=C.finish(p,op,0,3,{},{},false,{forfeit=true});assert(income==0,code);assert(C.validate(p))end
assert(C.isPlayable(p));assert(p.cash<=cash and p.roster[1].xp==xp and p.roster[1].goals==0)
""")
test('calendar recovery is free, capped and preparation charges wages once',r"""
local C=require('Career');local E=require('Economy');local p=C.new(14);for _,q in ipairs(p.roster)do q.fitness=40 end;local cash=p.cash;local xp=p.roster[1].xp
E.advance(p,5);assert(p.roster[1].fitness>40 and p.cash==cash and p.roster[1].xp==xp)
local fit=p.roster[1].fitness;E.advance(p,5);assert(p.roster[1].fitness==fit and p.cash==cash)
local fresh=C.new(14);local op=C.next(fresh);fresh.roster[1].fitness=40;local fees=C.prepare(fresh,op);assert(fees~=nil);local before=fresh.cash;local readyFitness=fresh.roster[1].fitness;assert(C.prepare(fresh,op)==0);assert(fresh.cash==before and fresh.roster[1].fitness==readyFitness);assert(C.validate(fresh))
local forged=C.copy(fresh);forged.prepared.costs=0/0;assert(not C.validate(forged))
local stats={fitness={[fresh.lineup[1]]=20},minutes={[fresh.lineup[1]]=90}}
assert(C.finish(fresh,op,1,0,{},{},false,{stats=stats})~=nil);assert(fresh.prepared==nil);assert(fresh.roster[1].fitness>=20 and fresh.roster[1].fitness<40)
local P=require('Players');local friend=C.new(5).roster[1];local morale=friend.morale;local xp=friend.xp;P.develop(friend,2,true,false,true);assert(friend.morale==morale and friend.xp==xp)
local K=require('EconomyConfig');local base=C.new(22);local money=base.cash;local income,parts=E.matchIncome(base,{home=false,kind='league'},0,0,false);assert(parts.tickets==0 and parts.broadcast==K.leagueBroadcast[6]);assert(base.cash==money+income);assert(E.matchIncome(base,{home=true,kind='league'},0,3,true)==0)
""")
test('substitution preserves departed ratings, fitness and substitute experience',r"""
local C=require('Career');local M=require('Match');local p=C.new(12);local op=C.next(p);while op and op.kind=='friendly'do C.finish(p,op,0,0,{},{},false);op=C.next(p)end;assert(C.prepare(p,op)~=nil);local m=M.new(p,op,C,12);m.pause=2
local out=m.players[10];out.personal.goals=2;local incoming
for id,q in pairs(m.bench)do if q.pos~='GK'then incoming=id;break end end
assert(incoming);local before=C.find(p,incoming).xp;assert(M.substitute(m,out.id,incoming));m.minutes[incoming]=15;m.minutes[out.id]=75
local stats=M.statistics(m);assert(stats.ratings[out.id] and stats.fitness[out.id] and stats.ratings[incoming]);assert(C.finish(p,op,2,0,{},{},false,{stats=stats})~=nil);assert(C.find(p,incoming).xp>before)
""")
test('former clubs age their squads and retain bounded detail without losing cash',r"""
local C=require('Career');local W=require('World');local p=C.new(201);local ids={};for id in pairs(p.world.clubs)do ids[#ids+1]=id end;table.sort(ids)
for i=1,7 do local club=p.world.clubs[ids[i]];club.retainedSquad=C.copy(p.roster);club.retainedAt=i;club.cash=10000+i end
C.compactClubs(p);local count=0;for i=1,7 do local club=p.world.clubs[ids[i]];if club.retainedSquad then count=count+1 else assert(club.retainedSummary and #club.retainedSummary.legends<=3)end;assert(club.cash==10000+i)end;assert(count==4)
local club=p.world.clubs[ids[7]];local q=club.retainedSquad[1];local age=q.age;W.advanceSeason(p.world);assert(club.retainedSquad[1].age==age+1);assert(W.validate(p.world))
""")
test('board rewards settle once, active manager contract blocks job cycling, club debts remain',r"""
local C=require('Career');local p=C.new(901)
for season=1,3 do
 local op=C.next(p);while op do assert(C.finish(p,op,2,1,{},{},true)~=nil);op=C.next(p)end
 local before=p.cosmetics.tokens;assert(C.action(p,'season',{}));assert(p.boardLast.completed and p.cosmetics.tokens==before+20);local tokens=p.cosmetics.tokens;assert(not C.action(p,'season',{}));assert(p.cosmetics.tokens==tokens)
 if p.season<=3 then assert(#p.jobOffers==0);local ok,reason=C.action(p,'job',{index=1});assert(not ok and reason=='JOB_CONTRACT_ACTIVE')end
end
assert(p.season==4 and #p.jobOffers>0);local old=p.world.clubs[p.clubId];p.debt=12345;local target=p.world.clubs[p.jobOffers[1].id];target.debt=5432;p.reputation=999
assert(C.action(p,'job',{index=1}));assert(old.debt==12345 and p.debt==5432);assert(p.manager.contractEnd==6)
for _,key in ipairs({'news','goals','marketConsumed','setPieces'})do local bad=C.copy(p);bad[key]='corrupt';assert(not C.validate(bad))end
local bad=C.copy(p);bad.roster[1].form=0/0;assert(not C.validate(bad));local bad=C.copy(p);bad.settings.sfx=0/0;assert(not C.validate(bad));local bad=C.copy(p);bad.upgrades.medical=nil;assert(not C.validate(bad))
""")
test('outgoing loans reserve squad depth, split wages, advance once and block duplicate sales',r"""
local C=require('Career');local E=require('Economy');local P=require('Players');local p=C.new(881);p.cash=1000000
local q;local starters={};for _,id in ipairs(p.lineup)do starters[id]=true end
for _,v in ipairs(p.roster)do if not starters[v.id] and v.pos~='GK'then q=v;break end end
assert(q);local wage=E.wages(p);local cash=p.cash;assert(C.action(p,'loanOut',{id=q.id}));assert(q.loanOut and not P.available(q));assert(p.cash>cash and E.wages(p)<wage)
local cash=p.cash;assert(not C.action(p,'loanOut',{id=q.id}));assert(not C.action(p,'sell',{id=q.id}));assert(p.cash==cash)
E.advance(p,28);local count=q.loanOut.played;assert(count==7);local apps=q.appearances;E.advance(p,28);assert(q.loanOut.played==count and q.appearances==apps);assert(C.validate(p))
local op=C.next(p);while op do assert(C.finish(p,op,0,3,{},{},false,{forfeit=true})~=nil);op=C.next(p)end
assert(C.action(p,'season',{}));local returned=C.find(p,q.id);if returned then assert(not returned.loanOut)end
""")
test('branding filters before mutation and enforces names and premium entitlement',r"""
local B=require('Branding');local C=require('Career');local p=C.new(882);local wallet=p.cash;local service={FilterStringAsync=function(_,raw,id)assert(id==882);return {GetNonChatStringForBroadcastAsync=function()return raw end}end}
assert(not B.filter(service,882,'a'));assert(not B.filter(service,882,'bad\nname'));local name=assert(B.filter(service,882,'  North Stars  '));assert(name=='North Stars');assert(B.rename(p,name,100));assert(not B.rename(p,'Second Name',101));assert(p.club==name and p.world.clubs[p.clubId].name==name)
assert(B.design(p,{palette=1,shape='shield',symbol=1}));assert(not B.design(p,{palette=8,shape='star',symbol=8}));p.cosmetics.passes.identity=true;assert(B.design(p,{palette=8,shape='star',symbol=8}));assert(B.effective(p));p.cosmetics.passes.identity=false;assert(not B.effective(p));assert(p.cash==wallet)
""")
test('own and academy scouting use regional reports with exact-once charges',r"""
local C=require('Career');local p=C.new(883);p.cash=1000000;local q=p.roster[1];assert(C.action(p,'scoutRegion',{value=q.country}));local before=p.cash;assert(C.action(p,'scout',{id=q.id}));assert(before-p.cash==1875 and q.scoutAccuracy==1);local cash=p.cash;assert(not C.action(p,'scout',{id=q.id}));assert(p.cash==cash);assert(not C.action(p,'scoutRegion',{value=q.country}));assert(C.action(p,'academy',{}));assert(C.action(p,'scout',{id=p.academy[1].id}))
""")
test('set-piece selection, four formation lines, shootout order and red-card keeper substitution',r"""
local C=require('Career');local M=require('Match');local p=C.new(884);p.formation='4-2-3-1';local m=M.new(p,C.next(p),C,884);local xs={};for _,q in ipairs(m.players)do if q.team==1 and not q.gk then xs[q.bx]=true end end;local n=0;for _ in pairs(xs)do n=n+1 end;assert(n==4)
local selected=m.players[10];p.setPieces.penalty=selected.id;M.restart(m,'penalty',1,88,32);assert(m.owner==10)
M.sendOff(m,22);M.startPenalties(m);assert(#m.penalties.orders[1]==10 and #m.penalties.orders[2]==10);assert(m.players[m.penalties.orders[1][1]].id==selected.id)
local seen={};for i=1,20 do m.penalties.execution=0;assert(M.penalty(m,{aim=.9,power=.8,dive=-1}));local row=m.penalties.history[#m.penalties.history];if row.team==1 then assert(not seen[row.shooter]);seen[row.shooter]=true end end;assert(not m.ended)
local m=M.new(p,C.next(p),C,885);M.sendOff(m,1);m.pause=20;local reserve;for id,q in pairs(m.bench)do if q.pos=='GK'then reserve=id;break end end;assert(reserve);assert(M.substitute(m,m.players[2].id,reserve));local keepers=0;for _,q in ipairs(m.players)do if q.team==1 and q.active and q.gk then keepers=keepers+1 end end;assert(keepers==1)
""")

# Execute the adapter test bodies in original statement order with native Lua.
st=ast.parse((ROOT/'tests/test_storage.py').read_text())
runtime_fn=next(n for n in st.body if isinstance(n,ast.FunctionDef) and n.name=='runtime')
setup=next(n.value.args[0].value for n in runtime_fn.body if isinstance(n,ast.Expr) and isinstance(n.value,ast.Call) and isinstance(n.value.func,ast.Attribute) and n.value.func.attr=='execute')
for filename in ['test_storage.py','test_monetization.py']:
 tree=ast.parse((ROOT/'tests'/filename).read_text());main=next(n for n in tree.body if isinstance(n,ast.FunctionDef) and n.name=='main');parts=[]
 for n in main.body:
  if isinstance(n,ast.Assign) and isinstance(n.value,ast.Call) and isinstance(n.value.func,ast.Name) and n.value.func.id=='runtime':parts.append('cooperative=false;pauseWrite=false;'+setup)
  elif isinstance(n,ast.Assign) and isinstance(n.value,ast.Call) and isinstance(n.value.func,ast.Attribute) and n.value.func.attr=='execute':
   name=n.targets[0].attr if isinstance(n.targets[0],ast.Attribute) else None
   if name: parts.append(name+'=assert(loadfile('+json.dumps(str(ROOT/'src'/('MonetizationConfig.lua' if name=='Config' else 'Monetization.lua')))+'))()')
  elif isinstance(n,ast.Expr) and isinstance(n.value,ast.Call):
   call=n.value
   if isinstance(call.func,ast.Name) and call.func.id=='load_storage':
    name=ast.literal_eval(call.args[1]) if len(call.args)>1 else 'S';parts.append(name+'=assert(loadfile('+json.dumps(str(ROOT/'src'/'Storage.lua'))+'))()')
   elif isinstance(call.func,ast.Attribute) and call.func.attr=='execute' and isinstance(call.args[0],ast.Constant):parts.append(call.args[0].value)
 if filename=='test_storage.py':parts.append("local u={UserId=909};local p=S.load(u,function()return {version=2,cash=8}end);records.u909.lock='another';local ok=S.close(u,p,copy);assert(not ok and S.sessions[u]==nil and records.u909.profile.cash==8)")
 test(filename+' adapter scenarios','\n'.join(parts))
test('modular UI construction and grouped pages (mock, not Studio)',r'''
assert(loadfile('/workspace/TouchlineDynasty/tests/mock_roblox.lua'))()
require=NATIVE_REQUIRE
Input.WindowFocusReleased=Instance.new('BindableEvent').Activated;Input.TextBoxFocused=Instance.new('BindableEvent').Activated;Input.GetFocusedTextBox=function()return nil end
script={Parent=setmetatable({},{__index=function(_,k)return k end})}
local L=require('Localization');local UI=require('UI');local Screens=require('CareerScreens');local V=require('MatchView');local I=require('Input')
local player=game:GetService('Players').LocalPlayer;local tr=L.new({locale='en'});local screens=Screens.new(tr,function()end);local ui=UI.new(player,tr,{items=function(...)return screens:items(...)end});screens.ui=ui
local A=NATIVE_REQUIRE('Audio');local audioConfig=NATIVE_REQUIRE('AudioConfig');audioConfig.kick.id=101;audioConfig.crowd.id=102;local audio=A.new(Instance.new('Folder'));local played=0;audio.sounds.kick.Play=function()played=played+1 end;audio:settingsChanged({sfx=.5,crowd=.2});assert(audio.sounds.kick.Volume==.325);audio:snapshot({seq=1,owner=10,phase='play'});audio:snapshot({seq=2,phase='play'});audio:snapshot({seq=2,phase='play'});assert(played==1);audio:destroy();audioConfig.kick.id=0;audioConfig.crowd.id=0
local C=NATIVE_REQUIRE('Career');local p=C.public(C.new(13));p.shop={catalog={}};ui:update(p)
for _,g in ipairs(UI.groups)do for _,page in ipairs(g.pages)do ui:open(page)end end
local missingKeys={};for _,obj in ipairs(Objects)do if type(obj.Text)=='string'then local missing=obj.Text:match('%[([%w_.]+)%]');if missing then missingKeys[missing]=true end end end;local missing={};for key in pairs(missingKeys)do missing[#missing+1]=key end;table.sort(missing);assert(#missing==0,'untranslated UI keys '..table.concat(missing,', '))
tr:setLocale('ru');ui:update(p);assert(ui.nav[1].button.Text=='Клуб');tr:setLocale('en');ui:update(p)
local v=V.new(ui.gui,tr,function()end);local input=I.new(ui.gui,v,tr,function()end);assert(input and v);ui:modal('Result','1:0',{{label='Continue',callback=function()end}})
local rs=game:GetService('ReplicatedStorage');local folder=Instance.new('Folder');folder.Name='TouchlineShared';folder.Parent=rs
for _,name in ipairs({'Audio','AudioConfig','Results','UI','CareerScreens','MatchView','Input','Localization','Locales','MonetizationConfig'})do local m=Instance.new('ModuleScript');m.Name=name;m.Parent=folder end
require=function(target)return NATIVE_REQUIRE(type(target)=='table' and target.Name or target)end
assert(loadfile('/workspace/TouchlineDynasty/src/Client.client.lua'))()
assert(Command.lastAction=='ready');RemoteEvent.OnClientEvent:Fire('profile',p)
workspace.CurrentCamera.ViewportSize=Vector2.new(390,844);ui:resize();v:resize();input:resize();assert(ui.mobile);workspace.CurrentCamera.ViewportSize=Vector2.new(1280,800);ui:resize();assert(not ui.mobile)
local career=C.new(13);local op=C.next(career);local match=NATIVE_REQUIRE('Match').new(career,op,C,13)
RemoteEvent.OnClientEvent:Fire('matchStart',NATIVE_REQUIRE('Match').snapshot(match));Run.RenderStepped:Fire(.016)
RemoteEvent.OnClientEvent:Fire('result',{home=1,away=0,op='Test',income=1,stats=NATIVE_REQUIRE('Match').statistics(match)});assert(click('Player ratings'));assert(click('Back to report'));assert(click('Match factors'));assert(click('Back to report'));assert(click('Continue'))
for _,item in ipairs(NATIVE_REQUIRE('MonetizationConfig').items)do p.cosmetics.equipped[item.slot]=item.id;v:show(p,NATIVE_REQUIRE('Match').snapshot(match));if item.id=='hoops'then assert(v.figures[1].patterns[1].Visible)end;if item.id=='crest_star'then assert(v.crest.Text:find('★',1,true))end end

''')
(ROOT/'NATIVE_TEST_RESULTS.json').write_text(json.dumps(results,ensure_ascii=False,indent=2))
raise SystemExit(any(x['status']=='FAIL' for x in results))
