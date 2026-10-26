local Players=game:GetService('Players')
-- The visible match is a 2.5D GUI scene; no hidden avatar simulation is needed.
Players.CharacterAutoLoads=false
local RS=game:GetService('ReplicatedStorage')
local Run=game:GetService('RunService')
local Messages=require(RS:WaitForChild('TouchlineShared'):WaitForChild('Locales'))
local L=require(RS.TouchlineShared.Localization)
local Branding=require(script.Parent.Branding)
local C=require(script.Parent.Career)
local M=require(script.Parent.Match)
local S=require(script.Parent.Storage)
local N=require(script.Parent.Monetization)
local A=require(script.Parent.Training)
local R=require(script.Parent.Records)
local records=R.adapter(game:GetService('DataStoreService'),Run:IsStudio())
local net=Instance.new('Folder'); net.Name='TouchlineNet'; net.Parent=RS
local event=Instance.new('RemoteEvent'); event.Name='Event'; event.Parent=net
local command=Instance.new('RemoteEvent'); command.Name='Command'; command.Parent=net
local profiles,matches,busy,rates,leaving={},{},{},{},{}
local function emit(p,k,v) if p.Parent==Players then event:FireClient(p,k,v) end end
local function toast(p,key,params)
 local aliases={SAVED='status.saved',TEST_SESSION='status.studio',LOCK_LOST='error.lockLost',INSUFFICIENT_FUNDS='error.money',MATCH_ACTIVE='error.matchActive',STORE_UNAVAILABLE='error.save',PRODUCT_NOT_CONFIGURED='error.productDisabled',OPERATION_FAILED='error.server'}
 local textKey=(Messages.en['code.'..tostring(key)] and 'code.'..key) or (Messages.en[tostring(key)] and tostring(key)) or aliases[key] or (type(key)=='string' and string.find(key,'.',1,true) and key) or 'error.unavailable'
 emit(p,'toast',{key=textKey,params=params or {}})
end
local views,netRevision={},{}
local function equal(a,b)
 if type(a)~=type(b) then return false end
 if type(a)~='table' then return a==b end
 for k,v in pairs(a) do if not equal(v,b[k]) then return false end end
 for k in pairs(b) do if a[k]==nil then return false end end
 return true
end
local function update(p,force)
 local profile=profiles[p]; if not profile then return end
 local v=C.public(profile); v.shop=N.public(p,profile); v.saveStatus=S.sessions[p] and (S.sessions[p].temporary and 'TEST_SESSION' or 'SAVED')
 local old=views[p];local base=netRevision[p] or 0;v.revision=base+1;netRevision[p]=v.revision
 if force or not old then emit(p,'profile',v)
 else
  local fields,removed={},{}
  for k,value in pairs(v) do if k~='revision' and not equal(value,old[k]) then fields[k]=value end end
  for k in pairs(old) do if v[k]==nil then removed[#removed+1]=k end end
  emit(p,'patch',{base=base,revision=v.revision,fields=fields,removed=removed})
 end
 views[p]=v
end
local function transaction(p,fn)
 return S.transaction(p,profiles[p],fn,C.copy)
end
local function finish(p,m,forfeit)
 if m.finalizing or not profiles[p] then return end
 m.finalizing=true;forfeit=forfeit or m.technicalLoser==1
 local ok,result,code=transaction(p,function(candidate)
  if m.training then return true,A.finish(candidate,m,forfeit,M) end
  local income,key,r=C.finish(candidate,m.op,m.home,m.away,m.technicalLoser and {}or m.scorers,m.technicalLoser and {}or m.assists,m.penWin,{technical=m.technicalLoser~=nil,forfeit=forfeit,mode=m.recordMode or m.mode,stats=M.statistics(m)})
  if income==nil then return false,key end
  candidate.pending=nil;R.record(candidate,r); return true,r
 end)
 if ok then if not m.training then local key=R.category(m.recordMode or m.mode,profiles[p].difficulty);local row=key and profiles[p].records.categories and profiles[p].records.categories[key];if row then task.spawn(function()records.publish(p.UserId,key,row.points)end)end end;matches[p]=nil; emit(p,'result',result); update(p)
 else m.finalizing=false; m.ended=true; m.retryAt=os.clock()+5; toast(p,code) end
end
N.bind({profiles=profiles,storage=S,copy=C.copy,onChanged=update})
local function join(p)
 local profile,code=S.load(p,function() return C.new(math.abs(p.UserId)+913) end,C.migrate,C.validate)
 if not profile then p:Kick(code); return end
 profiles[p]=profile
 if profile.pending then
  local pending=profile.pending
  local op=pending.op or pending
  if not profile.prepared then local ok,_,reason=transaction(p,function(candidate)local costs,code=C.prepare(candidate,op);return costs~=nil,code end);if not ok then S.close(p,profile,C.copy);profiles[p]=nil;p:Kick(tostring(reason));return end end
  local m=M.simulate(profile,op,C,pending.seed or op.seed or profile.seed)
  finish(p,m,false)
 end
 if p.Parent~=Players then S.close(p,profile,C.copy); profiles[p]=nil; return end
 N.refreshPasses(p,profile,true);update(p)
end
Players.PlayerAdded:Connect(join)
for _,p in ipairs(Players:GetPlayers()) do task.spawn(join,p) end
local function valid(v,depth)
 depth=depth or 0
 if depth>3 then return false end
 local t=type(v)
 if t=='number' then return v==v and math.abs(v)<1e12 end
 if t=='string' then return #v<=160 end
 if t=='boolean' or t=='nil' then return true end
 if t~='table' then return false end
 local count=0; for k,x in pairs(v) do count=count+1; if count>24 or type(k)~='string' or #k>32 or not valid(x,depth+1) then return false end end
 return true
end
command.OnServerEvent:Connect(function(p,action,arg)
 if type(action)~='string' or #action>32 or not valid(arg) or (arg~=nil and type(arg)~='table') then return end
 arg=arg or {}; local now=os.clock(); local bucket=(action=='input' or action=='control') and 'input' or 'economy'
 rates[p]=rates[p] or {}; local r=rates[p][bucket] or {t=now,n=0}; rates[p][bucket]=r
 if now-r.t>=1 then r.t=now;r.n=0 end
 r.n=r.n+1; if r.n>(bucket=='input' and 40 or 6) then return end
 if action=='ready' then update(p,true); return end
 if busy[p] or leaving[p] or not profiles[p] then return end
 if S.sessions[p] and S.sessions[p].lost then toast(p,'LOCK_LOST');return end
 local m=matches[p]
 if action=='input' then if m and type(arg.x)=='number' and type(arg.y)=='number' and math.abs(arg.x)<=1 and math.abs(arg.y)<=1 then m.input={x=arg.x,y=arg.y};m.inputAt=now end;return end
 if action=='control' then if m and not (m.training and arg.action=='mode') then local ok,key=M.command(m,arg.action,arg);if ok==false and key then toast(p,key) end end;return end
 if action=='forfeit' then if m then finish(p,m,true) end;return end
 if m then toast(p,'MATCH_ACTIVE');return end
 busy[p]=true
 local safe,err=pcall(function()
  if action=='rename' then
   local filtered,reason=Branding.filter(game:GetService('TextService'),p.UserId,arg.name);if not filtered then toast(p,reason);return end
   local ok,result,code=transaction(p,function(candidate)local accepted,reason=Branding.rename(candidate,filtered,os.time());return accepted,reason end);toast(p,ok and'status.success'or type(result)=='string'and result or code);if ok then update(p)end
  elseif action=='identityDesign'then
   local checked,reason=N.refreshPasses(p,profiles[p],false);if not checked then toast(p,reason);return end
   local ok,result,code=transaction(p,function(candidate)local accepted,reason=Branding.design(candidate,arg);return accepted,reason end);toast(p,ok and'status.success'or type(result)=='string'and result or code);if ok then update(p)end
  elseif action=='practice' then
   local match,reason=A.new(arg.kind or 'practice',C,M);if not match then toast(p,reason);return end
   matches[p]=match;local snapshot=M.snapshot(match);snapshot.training=A.snapshot(match);emit(p,'matchStart',snapshot)
  elseif action=='technicalForfeit' then
   local op,reason=C.next(profiles[p]);if not op then toast(p,reason);return end
   local ok,result,code=transaction(p,function(candidate)local income,key,r=C.finish(candidate,op,0,3,{},{},false,{forfeit=true,mode='simulate'});if income==nil then return false,key end;return true,r end)
   if ok then emit(p,'result',result);update(p)else toast(p,code)end
  elseif action=='play' or action=='simulate' or action=='highlights' then
   if not C.isPlayable(profiles[p])then toast(p,'SQUAD_UNAVAILABLE');return end
   local op,reason=C.next(profiles[p]); if not op then toast(p,reason);return end
   local seed=op.seed or profiles[p].seed+profiles[p].season*100003+profiles[p].round*91
   local ok,_,code=transaction(p,function(candidate) local costs,reason=C.prepare(candidate,op);if costs==nil then return false,reason end;candidate.pending={op=C.copy(op),seed=seed}; return true,'MATCH_PREPARED' end)
   if not ok then toast(p,code);return end
   if action=='simulate' then local sim=M.simulate(profiles[p],op,C,seed);matches[p]=sim;finish(p,sim,false)
   else local match=M.new(profiles[p],op,C,seed); if action=='highlights' then M.setMode(match,'highlights') end;matches[p]=match;emit(p,'matchStart',M.snapshot(match)) end
  elseif action=='playerHistory'then local q=C.find(profiles[p],arg.id);if not q then for _,a in ipairs(profiles[p].academy)do if a.id==arg.id then q=a;break end end end;if not q then toast(p,'PLAYER_NOT_FOUND');return end;emit(p,'playerHistory',{name=q.name,rows=C.copy(q.history or {})})
  elseif action=='records' then local rows,reason=records.read(arg.mode or 'manual',arg.difficulty or profiles[p].difficulty);if rows then emit(p,'records',{rows=rows,mode=arg.mode or 'manual',difficulty=arg.difficulty or profiles[p].difficulty})else toast(p,reason)end
  elseif action=='save' then local _,code=S.save(p,profiles[p],C.copy,false);toast(p,code)
  elseif action=='purchase' or action=='refreshPasses' or action=='cosmeticBuy' or action=='cosmeticEquip' then local ok,code,params=N.action(p,profiles[p],action,arg);toast(p,ok and(code=='PURCHASE_PROMPT'and'shop.prompt'or'status.success')or code,params);update(p)
  else
   local ok,result,code=transaction(p,function(candidate) local accepted,key,params=C.action(candidate,action,arg);return accepted,{key=key,params=params} end)
   toast(p,ok and 'status.success' or (type(result)=='table' and result.key or code),type(result)=='table' and result.params);if ok then update(p) end
  end
 end)
 busy[p]=nil;if not safe then warn('Touchline command failed: '..tostring(err));toast(p,'OPERATION_FAILED') end
end)
local accum,network=0,0
Run.Heartbeat:Connect(function(dt)
 accum=math.min(accum+dt,.25);network=network+dt
 while accum>=.05 do
  accum=accum-.05
  for p,m in pairs(matches) do
   if not busy[p] and not leaving[p] and not m.finalizing then
    if os.clock()-(m.inputAt or 0)>.45 then m.input={x=0,y=0} end
    if not m.ended then
     local steps=m.mode=='highlights' and m.phase=='play' and m.pause<=0 and not M.interactive(m) and 4 or 1
     for _=1,steps do M.step(m,.05);A.observe(m);if m.ended or M.interactive(m) then break end end
    end
    if m.ended and os.clock()>=(m.retryAt or 0) then m.finalizing=true;task.spawn(function() m.finalizing=false;finish(p,m,false) end) end
   end
  end
 end
 if network>=.1 then network=0;for p,m in pairs(matches) do local snapshot=M.snapshot(m);snapshot.training=A.snapshot(m);emit(p,'snapshot',snapshot) end end
end)
local function leave(p)
 if leaving[p] then return end; leaving[p]=true
 local start=os.clock();while busy[p] and os.clock()-start<12 do task.wait(.1) end
 -- Pending deterministic seed survives interruption; reconnect resolves it once.
 if profiles[p] then S.close(p,profiles[p],C.copy) end
 records.clear(p.UserId);profiles[p]=nil;matches[p]=nil;rates[p]=nil;busy[p]=nil;leaving[p]=nil;views[p]=nil;netRevision[p]=nil
end
Players.PlayerRemoving:Connect(leave)
task.spawn(function() while true do task.wait(45);for p in pairs(profiles) do task.spawn(function() if not leaving[p] then local ok,reason=S.renew(p);if not ok and reason=='LOCK_LOST'and p.Parent==Players then local locale='en';pcall(function()locale=L.resolve(profiles[p].settings.locale,p.LocaleId)end);matches[p]=nil;p:Kick(L.t('error.lockLost',{},locale))end end end) end end end)
game:BindToClose(function() local n=0;for p in pairs(profiles) do n=n+1;task.spawn(function() leave(p);n=n-1 end) end;local t=os.clock();while n>0 and os.clock()-t<25 do task.wait(.1) end end)
