from pathlib import Path
from lupa import LuaRuntime
ROOT=Path(__file__).resolve().parents[1]
lua=LuaRuntime(unpack_returned_tuples=True)
lua.execute('''
record=nil; fail=false; studio=false; unavailable=false; now=100
local db={}
function db:UpdateAsync(key,callback)
 if fail then error('simulated outage') end
 local value=callback(record)
 if value~=nil then record=value end
 return value
end
local services={DataStoreService={GetDataStore=function() if unavailable then error('unpublished') end; return db end},RunService={IsStudio=function() return studio end},HttpService={GenerateGUID=function() return 'test-guid' end}}
game={JobId='server-A',GetService=function(_,name) return services[name] end}
task={wait=function() end}
''')
code=(ROOT/'src/Storage.lua').read_text()
lua.globals().S=lua.execute(code)
lua.execute('''
local player={UserId=101}
local p,msg=S.load(player,function() return {version=1,cash=123} end)
assert(p.cash==123 and record.lock=='server-A')
p.cash=555
assert(S.save(player,p,function(q) return {version=q.version,cash=q.cash} end,false))
assert(record.profile.cash==555 and record.lock=='server-A')
assert(S.save(player,p,function(q) return q end,true)); assert(record.lock==nil)
record={profile={version=1,cash=777},lock='server-B',expires=os.time()+100}
assert(S.load(player,function() error('must not reset profile') end)==nil)
assert(record.profile.cash==777)
record.expires=os.time()-1
local loaded=S.load(player,function() error('must reuse profile') end)
assert(loaded.cash==777 and record.lock=='server-A')
record.lock='server-B'
local ok,reason=S.save(player,loaded,function(q) return q end,false)
assert(not ok and reason=='LOCK_LOST')
fail=true; studio=false
assert(S.load({UserId=555},function() return {version=1} end)==nil)
studio=true
local temporaryPlayer={UserId=999}
local temporary=S.load(temporaryPlayer,function() return {version=1,cash=10} end)
assert(temporary.cash==10 and S.sessions[temporaryPlayer].temporary)
assert(S.save(temporaryPlayer,temporary,function(q) return q end,true))
''')
lua.execute('unavailable=true; fail=false')
lua.globals().S2=lua.execute(code)
lua.execute('''
local p={UserId=77}
local value=S2.load(p,function() return {version=1,cash=21} end)
assert(value.cash==21 and S2.sessions[p].temporary)
''')
print('PASS storage: acquisition, persistence, release, live lock, expired lock, lost lock, outage, Studio temporary, unpublished Studio')
