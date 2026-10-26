-- Authoritative profile store. Saves, finalization and receipts share one queue.
-- UpdateAsync transforms return precomputed envelopes, without outside effects.
local DataStoreService=game:GetService('DataStoreService')
local RunService=game:GetService('RunService')
local HttpService=game:GetService('HttpService')
local S={sessions={},LEASE=180,RENEW_EVERY=45,RETRIES=3,QUEUE_TIMEOUT=12,MAX_PROFILE_BYTES=3500000}
local studio=RunService:IsStudio()
S.namespace=studio and 'TouchlineDynasty_TEST_v2' or 'TouchlineDynasty_v1'
local dbOK,db=pcall(function() return DataStoreService:GetDataStore(S.namespace) end)
if not dbOK then db=nil end
local counter=0
local function nonce()
 counter=counter+1
 return tostring(game.JobId or '')..':'..HttpService:GenerateGUID(false)..':'..counter
end
local function clone(value,seen)
 if type(value)~='table' then return value end
 seen=seen or {}; if seen[value] then error('CYCLIC_PROFILE') end
 seen[value]=true; local out={}
 for k,v in pairs(value) do out[k]=clone(v,seen) end
 seen[value]=nil; return out
end
local function overwrite(target,source)
 for k in pairs(target) do target[k]=nil end
 for k,v in pairs(source) do target[k]=v end
end
local function finite(n) return type(n)=='number' and n==n and math.abs(n)<math.huge end
local function basicValidate(p)
 if type(p)~='table' or not finite(p.version) or p.version<1 then return false,'PROFILE_INVALID' end
 if p.cash~=nil and not finite(p.cash) then return false,'PROFILE_INVALID' end
 return true
end
local function validate(session,p)
 local ok,valid,reason=pcall(session.validate or basicValidate,p)
 if not ok or not valid then return false,reason or 'PROFILE_INVALID' end
 return true
end
local function budget()
 if not DataStoreService.GetRequestBudgetForRequestType then return true end
 local request=Enum.DataStoreRequestType.UpdateAsync
 for _=1,10 do
  local ok,n=pcall(function() return DataStoreService:GetRequestBudgetForRequestType(request) end)
  if ok and n>=1 then return true end
  task.wait(.2)
 end
 return false
end
local function retry(fn)
 local last='STORE_UNAVAILABLE'
 for attempt=1,S.RETRIES do
  if budget() then
   local ok,value=pcall(fn)
   if ok then return true,value end
   last='STORE_UNAVAILABLE'
  else last='STORE_THROTTLED' end
  if attempt<S.RETRIES then task.wait(.25*2^(attempt-1)) end
 end
 return false,last
end
local function acquire(session)
 for _=1,math.floor(S.QUEUE_TIMEOUT/.05) do
  if session.closed or session.lost then return false,'LOCK_LOST' end
  if not session.busy then session.busy=true; return true end
  task.wait(.05)
 end
 return false,'STORE_BUSY'
end
local function owns(session,old,now)
 return type(old)=='table' and old.lock==session.token and finite(old.expires) and old.expires>now
end
local function envelope(session,snapshot,writeId,release)
 return {profile=snapshot,lock=not release and session.token or nil,
  expires=not release and os.time()+S.LEASE or 0,
  revision=session.revision+1,lastWrite=writeId}
end
local function writeLocked(session,snapshot,release)
 if HttpService.JSONEncode then
  local encodedOk,encoded=pcall(function() return HttpService:JSONEncode(snapshot) end)
  if not encodedOk then return false,'PROFILE_INVALID' end
  session.encodedBytes=#encoded
  -- Reserve headroom below the DataStore per-key limit for the envelope.
  if #encoded>S.MAX_PROFILE_BYTES then return false,'PROFILE_TOO_LARGE' end
 end
 if session.temporary then
  session.revision=session.revision+1; session.dirty=false
  if release then session.closed=true end
  return true,'TEST_SESSION'
 end
 local writeId=nonce()
 local expected=session.revision
 local candidate=envelope(session,snapshot,writeId,release)
 local ok,result=retry(function()
  return db:UpdateAsync(session.key,function(old)
   -- Recover a commit whose response was lost, without applying it twice.
   if type(old)=='table' and old.lastWrite==writeId then return old end
   if not owns(session,old,os.time()) or (old.revision or 0)~=expected then return nil end
   return candidate
  end)
 end)
 if not ok then return false,result end
 if not result or result.lastWrite~=writeId then session.lost=true; return false,'LOCK_LOST' end
 session.revision=result.revision; session.expires=result.expires
 session.lastSaved=os.clock(); session.dirty=false
 if release then session.closed=true end
 return true,'SAVED'
end
local function unlockUnchanged(session)
 if not db or session.temporary then return end
 retry(function()
  return db:UpdateAsync(session.key,function(old)
   if type(old)~='table' or old.lock~=session.token then return nil end
   local released=clone(old); released.lock=nil; released.expires=0; return released
  end)
 end)
end
function S.load(player,make,migrate,check)
 if S.sessions[player] and not S.sessions[player].closed then return nil,'SESSION_EXISTS' end
 local session={key='u'..player.UserId,token=nonce(),busy=false,dirty=false,
  temporary=false,lost=false,revision=0,validate=check}
 if not db then
  if not studio then return nil,'STORE_UNAVAILABLE' end
  local ok,p=pcall(make); if not ok then return nil,'PROFILE_INVALID' end
  local valid,reason=validate(session,p); if not valid then return nil,reason end
  session.temporary=true; session.profile=p; S.sessions[player]=session
  return p,'TEST_SESSION'
 end
 local ok,record=retry(function()
  return db:UpdateAsync(session.key,function(old)
   if old~=nil and type(old)~='table' then return nil end
   if old and old.revision~=nil and (not finite(old.revision) or old.revision<0 or old.revision%1~=0) then return nil end
   if old and old.expires~=nil and not finite(old.expires) then return nil end
   if old and old.lock and (old.expires or 0)>os.time() and old.lock~=session.token then return nil end
   if old and not old.bootstrap and type(old.profile)~='table' then return nil end
   return {profile=old and old.profile or {},bootstrap=old==nil or old.bootstrap,
    lock=session.token,expires=os.time()+S.LEASE,revision=old and old.revision or 0,
    lastWrite=old and old.lastWrite}
  end)
 end)
 if not ok then
  -- Studio is isolated from production; offline fallback is non-durable.
  if studio then
   local made,p=pcall(make); if not made then return nil,'PROFILE_INVALID' end
   local valid,reason=validate(session,p); if not valid then return nil,reason end
   session.temporary=true; session.profile=p; S.sessions[player]=session
   return p,'TEST_SESSION'
  end
  return nil,record
 end
 if not record then return nil,'PROFILE_LOCKED_OR_INVALID' end
 session.revision=record.revision or 0; session.expires=record.expires
 local prepared,p
 if record.bootstrap then prepared,p=pcall(make)
 elseif migrate then prepared,p=pcall(migrate,clone(record.profile))
 else prepared,p=true,clone(record.profile) end
 if not prepared or type(p)~='table' then unlockUnchanged(session); return nil,'MIGRATION_FAILED' end
 local valid,reason=validate(session,p)
 if not valid then unlockUnchanged(session); return nil,reason end
 session.profile=p; S.sessions[player]=session
 -- Do not expose an unsaved new profile or migration to game code.
 if record.bootstrap or record.profile.version~=p.version then
  session.busy=true; local saved,code=writeLocked(session,clone(p),false); session.busy=false
  if not saved then unlockUnchanged(session); S.sessions[player]=nil; return nil,code end
 end
 return p,'SAVED'
end
function S.markDirty(player)
 local s=S.sessions[player]; if s and not s.closed then s.dirty=true; s.mutations=(s.mutations or 0)+1 end
end
function S.save(player,profile,copy,release)
 local session=S.sessions[player]; if not session then return false,'NO_SESSION' end
 local locked,code=acquire(session); if not locked then return false,code end
 if profile~=session.profile then session.busy=false; return false,'PROFILE_STALE' end
 local valid,reason=validate(session,profile)
 if not valid then session.busy=false; return false,reason end
 local generation=session.mutations or 0
 local copied,snapshot=pcall(copy or clone,profile)
 if not copied then session.busy=false; return false,'PROFILE_INVALID' end
 local ok,result=writeLocked(session,snapshot,release)
 if (session.mutations or 0)~=generation then session.dirty=true end
 session.busy=false
 if ok and release then S.sessions[player]=nil end
 return ok,result
end
function S.transaction(player,profile,mutate,copy)
 local session=S.sessions[player]; if not session then return false,nil,'NO_SESSION' end
 local locked,code=acquire(session); if not locked then return false,nil,code end
 if profile~=session.profile then session.busy=false; return false,nil,'PROFILE_STALE' end
 local copied,candidate=pcall(copy or clone,profile)
 if not copied then session.busy=false; return false,nil,'PROFILE_INVALID' end
 local executed,accepted,result=pcall(mutate,candidate)
 if not executed then session.busy=false; return false,nil,'OPERATION_FAILED' end
 if accepted~=true then session.busy=false; return false,result,'OPERATION_REJECTED' end
 local valid,reason=validate(session,candidate)
 if not valid then session.busy=false; return false,result,reason end
 local saved,message=writeLocked(session,candidate,false)
 if saved then overwrite(profile,candidate); session.mutations=(session.mutations or 0)+1 end
 session.busy=false
 return saved,result,message
end
function S.renew(player)
 local session=S.sessions[player]; if not session then return false,'NO_SESSION' end
 if session.temporary then return true,'TEST_SESSION' end
 if session.dirty then return S.save(player,session.profile,clone,false) end
 local locked,code=acquire(session); if not locked then return false,code end
 local token=session.token
 local ok,res=retry(function()
  return db:UpdateAsync(session.key,function(old)
   if not owns(session,old,os.time()) then return nil end
   local renewed=clone(old); renewed.lock=token; renewed.expires=os.time()+S.LEASE; return renewed
  end)
 end)
 session.busy=false
 if not ok then return false,res end
 if not res then session.lost=true; return false,'LOCK_LOST' end
 session.expires=res.expires; session.lastRenewed=os.clock(); return true,'SAVED'
end
function S.close(player,profile,copy)
 local session=S.sessions[player];if not session then return false,'NO_SESSION'end
 local ok,reason=S.save(player,profile,copy,true)
 -- On a lost lock or outage, earlier durable pending state remains recoverable.
 -- Stop renewing and release in-memory references; the remote lease expires normally.
 session.closed=true;S.sessions[player]=nil;return ok,reason
end
return S
