-- Owner-operated server diagnostics. Never runs automatically or in a live server.
local Q={}
function Q.run(options)
 local Run=game:GetService('RunService');assert(Run:IsStudio(),'StudioQA is disabled outside Studio')
 options=options or {};local C=require(script.Parent.Career);local M=require(script.Parent.Match);local S=require(script.Parent.Storage)
 local report={environment=Run:IsServer() and 'Roblox Studio server' or 'Roblox Studio Edit mode',checks={}}
 local function check(name,fn)
  local start=os.clock();local ok,detail=pcall(fn)
  report.checks[#report.checks+1]={name=name,status=ok and 'PASS' or 'FAIL',result=ok and(detail or 'assertions passed')or tostring(detail),seconds=os.clock()-start}
 end
 check('Luau career and authoritative match lifecycle',function()
  local p=C.new(900001);assert(C.validate(p));local op=C.next(p);assert(C.prepare(p,op)~=nil)
  local m=M.simulate(p,op,C,op.seed or 900001);local income,_,result=C.finish(p,op,m.home,m.away,m.scorers,m.assists,m.penWin,{mode='simulate',stats=M.statistics(m)})
  assert(income~=nil and result.matchId==op.matchId and C.validate(p));local cash=p.cash;assert(C.finish(p,op,50,0,{},{},true)==0 and p.cash==cash)
 end)
 if options.storage then
  assert(Run:IsRunning() and Run:IsServer(),'Run the storage probe in the SERVER Command Bar during Play')
  local probeUser={UserId=-900000001}
  check('Real Studio test-store durable write and reload',function()
   assert(S.namespace=='TouchlineDynasty_TEST_v2','Refusing non-test namespace')
   local user=probeUser;local p,code=S.load(user,function()return C.new(900001)end,C.migrate,C.validate)
   assert(p,code)
   if S.sessions[user].temporary then S.close(user,p,C.copy);return 'NOT RUN: Studio API is unavailable; only temporary memory was used' end
   local before=p.studioProbeCount or 0
   local ok,_,reason=S.transaction(user,p,function(candidate)candidate.studioProbeCount=before+1;return true end,C.copy);assert(ok,reason)
   assert(S.close(user,p,C.copy));local loaded,reason=S.load(user,function()error('Durable profile was not found')end,C.migrate,C.validate);assert(loaded,reason)
   assert(not S.sessions[user].temporary and loaded.studioProbeCount==before+1);assert(S.close(user,loaded,C.copy))
   return 'Durable test key u-900000001 reloaded; production namespace was not accessed'
  end)
  if S.sessions[probeUser]then S.close(probeUser,S.sessions[probeUser].profile,C.copy)end
  local last=report.checks[#report.checks];if type(last.result)=='string'and last.result:sub(1,7)=='NOT RUN'then last.status='NOT RUN'end
 end
 local Http=game:GetService('HttpService');print('TOUCHLINE_STUDIO_QA '..Http:JSONEncode(report));return report
end
return Q
