local Players=game:GetService('Players')
local ReplicatedStorage=game:GetService('ReplicatedStorage')
local RunService=game:GetService('RunService')
local C=require(script.Parent.Career)
local M=require(script.Parent.Match)
local S=require(script.Parent.Storage)
local net=Instance.new('Folder'); net.Name='TouchlineNet'; net.Parent=ReplicatedStorage
local event=Instance.new('RemoteEvent'); event.Name='Event'; event.Parent=net
local command=Instance.new('RemoteEvent'); command.Name='Command'; command.Parent=net
local profiles,matches,rates,busy,status={}, {}, {}, {}, {}
local function emit(p,kind,data) if p.Parent==Players then event:FireClient(p,kind,data) end end
local function update(p)
 local profile=profiles[p]; if not profile then return end
 local packet=C.copy(profile); packet.strength=math.floor(C.strength(profile)); packet.table=C.sorted(profile); packet.next=C.next(profile,'league'); packet.saveStatus=status[p]
 emit(p,'profile',packet)
 local stats=p:FindFirstChild('leaderstats')
 if stats then stats.Trophies.Value=profile.trophies; stats.Wins.Value=profile.wins; stats.Season.Value=profile.season end
end
local function save(p,release)
 if not profiles[p] then return end
 local ok,msg=S.save(p,profiles[p],C.copy,release)
 status[p]=msg
 if msg=='LOCK_LOST' then p:Kick('Карьера открыта в другой сессии. Перезайди.') end
 return ok,msg
end
local function finish(p,m,forfeit)
 local profile=profiles[p]; if not profile then return end
 local x,y=m.home,m.away
 if forfeit then x=0; y=3 end
 local pen=m.op.kind=='cup' and x==y and m.rng()<.5
 local income=C.finish(profile,m.op,x,y,m.scorers,m.assists,pen)
 profile.pending=nil; matches[p]=nil
 emit(p,'result',{home=x,away=y,op=m.op.name,income=income,penalties=m.op.kind=='cup' and x==y,penWin=pen})
 update(p); task.spawn(function() save(p,false) end)
end
local function join(p)
 local profile,msg=S.load(p,function() return C.new(math.max(1,math.abs(p.UserId)+913)) end)
 if not profile then if p.Parent==Players then p:Kick(msg) end; return end
 profiles[p]=profile; status[p]=msg
 if profile.pending then C.finish(profile,profile.pending,0,3,{},{}); profile.pending=nil; profile.lastResult=profile.lastResult..' • выход из матча' end
 if p.Parent~=Players then save(p,true); profiles[p]=nil; return end
 local stats=Instance.new('Folder'); stats.Name='leaderstats'; stats.Parent=p
 for _,name in ipairs({'Trophies','Wins','Season'}) do local n=Instance.new('IntValue'); n.Name=name; n.Parent=stats end
 update(p)
end
Players.PlayerAdded:Connect(join)
for _,p in ipairs(Players:GetPlayers()) do task.spawn(join,p) end
command.OnServerEvent:Connect(function(p,action,arg)
 if type(action)~='string' or #action>24 or (arg~=nil and type(arg)~='table') then return end
 arg=arg or {}
 local now=os.clock(); local rate=rates[p] or {time=now,n=0}; rates[p]=rate
 if now-rate.time>1 then rate.time=now; rate.n=0 end
 rate.n=rate.n+1; if rate.n>32 then return end
 local profile=profiles[p]
 if action=='ready' then if profile then update(p) end; return end
 if not profile or busy[p] then return end
 local m=matches[p]
 if action=='input' then
  if m then
   local x,y=tonumber(arg.x),tonumber(arg.y)
   if x and y and x==x and y==y and math.abs(x)<=1 and math.abs(y)<=1 then m.input={x=x,y=y}; m.inputAt=now end
  end
  return
 end
 if action=='control' then
  if m and type(arg.action)=='string' then M.command(m,arg.action,arg) end; return
 end
 if action=='forfeit' and m then finish(p,m,true); return end
 if m then emit(p,'toast','Сначала закончи матч'); return end
 if action=='play' or action=='simulate' then
  local kind=arg.kind=='cup' and 'cup' or 'league'; local op,err=C.next(profile,kind)
  if not op then emit(p,'toast',err); return end
  busy[p]=true
  if action=='simulate' then
   local rng=C.rng(profile.seed+profile.season*500+profile.round*71+profile.cupStage*11)
   local x,y=C.sim(rng,C.strength(profile),op.rating)
   local goals={}; for _=1,x do local id=profile.lineup[rng(9,11)]; goals[id]=(goals[id] or 0)+1 end
   finish(p,{home=x,away=y,op=op,scorers=goals,assists={},rng=rng},false)
  else
   profile.pending=op
   local ok,msg=save(p,false)
   if ok then
    local match=M.new(profile,op,C,profile.seed+os.time()); matches[p]=match
    emit(p,'matchStart',M.snapshot(match))
   else profile.pending=nil; emit(p,'toast',msg) end
  end
  busy[p]=nil; return
 elseif action=='save' then
  busy[p]=true; local _,msg=save(p,false); busy[p]=nil; emit(p,'toast',msg); update(p); return
 end
 local ok,msg=C.action(profile,action,arg)
 emit(p,'toast',msg); if ok then update(p) end
end)
local accum,netAccum=0,0
RunService.Heartbeat:Connect(function(dt)
 accum=math.min(accum+dt,.25); netAccum=netAccum+dt
 while accum>=.05 do
  accum=accum-.05
  for p,m in pairs(matches) do
   if os.clock()-(m.inputAt or 0)>.45 then m.input={x=0,y=0} end
   M.step(m,.05); if m.ended then finish(p,m,false) end
  end
 end
 if netAccum>=.1 then netAccum=0; for p,m in pairs(matches) do emit(p,'snapshot',M.snapshot(m)) end end
end)
local function leave(p)
 while busy[p] do task.wait(.1) end
 if matches[p] and profiles[p] then
  local m=matches[p]; C.finish(profiles[p],m.op,0,3,{},{}); profiles[p].pending=nil; matches[p]=nil
 end
 save(p,true); profiles[p]=nil; rates[p]=nil; status[p]=nil; busy[p]=nil
end
Players.PlayerRemoving:Connect(leave)
task.spawn(function()
 while true do
  task.wait(60)
  for p in pairs(profiles) do task.spawn(function() save(p,false); if not matches[p] then update(p) end end) end
 end
end)
game:BindToClose(function()
 local remaining=0
 for p in pairs(profiles) do remaining=remaining+1; task.spawn(function() leave(p); remaining=remaining-1 end) end
 local start=os.clock(); while remaining>0 and os.clock()-start<25 do task.wait(.1) end
end)
-- Original, asset-free stadium. All visuals are primitives and generated at runtime.
local preview=workspace:FindFirstChild('TouchlinePreview'); if preview then preview:Destroy() end
local world=Instance.new('Folder'); world.Name='TouchlineStadium'; world.Parent=workspace
local function part(name,size,pos,color)
 local p=Instance.new('Part'); p.Name=name; p.Anchored=true; p.Size=size; p.Position=pos; p.Color=color; p.Material=Enum.Material.SmoothPlastic; p.Parent=world; return p
end
part('Pitch',Vector3.new(150,1,96),Vector3.new(0,-1,0),Color3.fromRGB(28,102,64))
for i=0,9 do part('Stripe',Vector3.new(15,.1,96),Vector3.new(-67.5+i*15,-.44,0),i%2==0 and Color3.fromRGB(33,117,72) or Color3.fromRGB(28,106,65)) end
for _,z in ipairs({-48,48}) do part('Touchline',Vector3.new(150,.12,.35),Vector3.new(0,-.3,z),Color3.new(1,1,1)) end
for _,x in ipairs({-75,0,75}) do part('Line',Vector3.new(.35,.12,96),Vector3.new(x,-.3,0),Color3.new(1,1,1)) end
for side=-1,1,2 do
 for row=1,6 do
  part('Stand',Vector3.new(180,2,5),Vector3.new(0,row*2,side*(54+row*5)),Color3.fromRGB(25+row*3,34+row*3,48+row*3))
  for seat=1,35 do part('Seat',Vector3.new(2,1.2,2),Vector3.new(-86+seat*4.8,row*2+1.7,side*(54+row*5)),seat%4==0 and Color3.fromRGB(187,242,93) or Color3.fromRGB(48,79,105)) end
 end
 for _,z in ipairs({-14,14}) do part('GoalPost',Vector3.new(.6,9,.6),Vector3.new(side*76,4,z),Color3.new(1,1,1)) end
 part('Crossbar',Vector3.new(.6,.6,28),Vector3.new(side*76,8.5,0),Color3.new(1,1,1))
end
local spawn=Instance.new('SpawnLocation'); spawn.Anchored=true; spawn.Size=Vector3.new(10,1,10); spawn.Position=Vector3.new(0,3,100); spawn.Transparency=1; spawn.Neutral=true; spawn.Parent=world
workspace.Gravity=196.2
game:GetService('Lighting').ClockTime=16
game:GetService('Lighting').Ambient=Color3.fromRGB(140,150,170)
