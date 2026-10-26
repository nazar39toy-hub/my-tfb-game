"""Pure adapter regression; intentionally not a claim of real DataStore QA."""
from pathlib import Path
from lupa import LuaRuntime
ROOT=Path(__file__).resolve().parents[1]

def runtime():
 lua=LuaRuntime(unpack_returned_tuples=True)
 lua.execute(r'''
 function copy(v)
  if type(v)~='table' then return v end
  local out={}; for k,x in pairs(v) do out[k]=copy(x) end; return out
 end
 now=1000; waits=0; calls=0; fail=false; responseLoss=0; budgetCount=10
 studio=false; unavailable=false; records={}; storeNames={}; repeatCallback=true
 os.time=function() return now end
 task={wait=function(seconds)
  waits=waits+1
  if cooperative then coroutine.yield('wait') end
 end}
 Enum={DataStoreRequestType={UpdateAsync='update'},ProductPurchaseDecision={PurchaseGranted='GRANTED',NotProcessedYet='RETRY'}}
 local guid=0
 local db={}
 function db:UpdateAsync(key,callback)
  calls=calls+1
  if fail then error('simulated unavailable store') end
  if pauseWrite then pauseWrite=false; coroutine.yield('write') end
  local previous=copy(records[key])
  local value=callback(copy(previous))
  if repeatCallback then value=callback(copy(previous)) end
  if value~=nil then records[key]=copy(value) end
  if responseLoss>0 then responseLoss=responseLoss-1; error('committed, response lost') end
  return copy(value)
 end
 local datastore={GetDataStore=function(_,name)
  storeNames[#storeNames+1]=name
  if unavailable then error('API disabled') end
  return db
 end,GetRequestBudgetForRequestType=function() return budgetCount end}
 local services={DataStoreService=datastore,RunService={IsStudio=function() return studio end},HttpService={GenerateGUID=function()
  guid=guid+1; return 'guid-'..guid
 end}}
 game={JobId='server-A',GetService=function(_,name) return services[name] end}
 function addService(name,value) services[name]=value end
 ''')
 return lua

def load_storage(lua,name='S'):
 lua.globals()[name]=lua.execute((ROOT/'src/Storage.lua').read_text())


def main():
 lua=runtime(); load_storage(lua)
 lua.execute(r'''
 makeCount=0
 function make() makeCount=makeCount+1; return {version=2,cash=123,roster={},cosmetics={tokens=0}} end
 player={UserId=101}
 p,msg=S.load(player,make)
 assert(p.cash==123 and msg=='SAVED' and makeCount==1)
 assert(records.u101.profile.cash==123 and records.u101.lock==S.sessions[player].token)
 assert(storeNames[1]=='TouchlineDynasty_v1')
 local before=calls
 local mutated=0
 local ok,result,code=S.transaction(player,p,function(candidate)
  mutated=mutated+1; candidate.cash=candidate.cash+10; return true,'applied'
 end,copy)
 assert(ok and result=='applied' and code=='SAVED' and mutated==1)
 assert(p.cash==133 and records.u101.profile.cash==133)
 local unchanged=p.cash
 assert(not S.transaction(player,p,function(candidate) candidate.cash=900; return false,'denied' end,copy))
 assert(p.cash==unchanged and records.u101.profile.cash==unchanged)
 assert(not S.transaction(player,p,function() error('bad mutation') end,copy))
 assert(not S.save(player,{version=2,cash=133},copy,false))
 responseLoss=1
 assert(S.transaction(player,p,function(candidate) candidate.cash=candidate.cash+7; return true end,copy))
 assert(p.cash==140 and records.u101.profile.cash==140)
 -- Renew without rewriting a stale copy; expired leases cannot be resurrected.
 now=1100; assert(S.renew(player)); assert(records.u101.expires==1280)
 now=1281
 local ok,code=S.save(player,p,copy,false)
 assert(not ok and code=='LOCK_LOST' and S.sessions[player].lost)
 assert(records.u101.profile.cash==140)
 ''')
 print('PASS storage: create, repeated UpdateAsync, serialized mutation, rejection, response-loss recovery, renew/expiry')
 lua=runtime(); load_storage(lua,'A'); lua.execute('game.JobId="server-B"'); load_storage(lua,'B')
 lua.execute(r'''
 local a={UserId=77}; local b={UserId=77}
 local p=A.load(a,function() return {version=2,cash=55} end)
 assert(p and B.load(b,function() error('must not replace locked profile') end)==nil)
 now=now+181
 local q=B.load(b,function() error('must reuse saved profile') end)
 assert(q.cash==55)
 local ok,code=A.save(a,p,copy,false); assert(not ok and code=='LOCK_LOST')
 assert(B.save(b,q,copy,true)); assert(records.u77.lock==nil and B.sessions[b]==nil)
 -- Legacy data migration persists once; corrupted input is never reset.
 records.u88={profile={version=1,cash=777},revision=4}
 local migrations=0; local user={UserId=88}
 local p=B.load(user,function() error('must preserve') end,function(old)
  migrations=migrations+1; assert(old.cash==777); old.version=2; old.legacy=true; return old
 end)
 assert(p.cash==777 and p.legacy and migrations==1 and records.u88.profile.version==2)
 assert(B.save(user,p,copy,true))
 local again=B.load(user,function() error('must preserve') end,function(old)
  if old.version==1 then migrations=migrations+1 end; return old
 end)
 assert(again.cash==777 and migrations==1)
 records.u99={profile='corrupt'}
 assert(B.load({UserId=99},function() error('no reset') end)==nil)
 assert(records.u99.profile=='corrupt')
 records.u100={profile={version=999,cash=300}}
 assert(B.load({UserId=100},function() error('no reset') end,nil,function(v) return v.version==2 end)==nil)
 assert(records.u100.profile.cash==300 and records.u100.lock==nil)
 ''')
 print('PASS storage: two owners, stale writer rejection, release, migration once, corruption quarantine')
 lua=runtime(); load_storage(lua)
 lua.execute(r'''
 budgetCount=0
 assert(S.load({UserId=1},function() return {version=2} end)==nil)
 assert(calls==0 and waits>0)
 budgetCount=10; fail=true
 assert(S.load({UserId=2},function() return {version=2} end)==nil)
 ''')
 lua.execute('studio=true'); load_storage(lua,'T')
 lua.execute(r'''
 local user={UserId=3}; local p,code=T.load(user,function() return {version=2,cash=10} end)
 assert(p and code=='TEST_SESSION' and T.sessions[user].temporary)
 assert(storeNames[#storeNames]=='TouchlineDynasty_TEST_v2')
 assert(T.save(user,p,copy,true))
 ''')
 print('PASS storage: bounded throttling/outage handling, isolated Studio namespace and non-durable fallback')
 lua=runtime(); load_storage(lua)
 lua.execute(r'''
 player={UserId=1}; p=S.load(player,function() return {version=2,cash=100,cosmetics={tokens=0}} end)
 cooperative=true; pauseWrite=true
 local results={}
 local a=coroutine.create(function()
  results.a=S.transaction(player,p,function(c) c.cosmetics.tokens=c.cosmetics.tokens+100; return true end,copy)
 end)
 local b=coroutine.create(function()
  results.b=S.transaction(player,p,function(c) c.cash=c.cash-10; return true end,copy)
 end)
 assert(coroutine.resume(a)); assert(coroutine.status(a)=='suspended')
 assert(coroutine.resume(b)); assert(coroutine.status(b)=='suspended')
 assert(coroutine.resume(a)); assert(results.a)
 assert(coroutine.resume(b)); assert(results.b)
 assert(p.cash==90 and p.cosmetics.tokens==100)
 assert(records.u1.profile.cash==90 and records.u1.profile.cosmetics.tokens==100)
 ''')
 print('PASS storage: cooperative concurrent transactions retain receipt wallet and football changes')
 print('PASS storage: all adapter regression groups (Lua/lupa, no Studio)')

if __name__=='__main__': main()
