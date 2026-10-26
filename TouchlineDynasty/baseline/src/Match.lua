-- Deterministic 11v11 ground-ball simulation; authoritative on the server.
local M={}
local function clamp(v,a,b) return math.max(a,math.min(b,v)) end
local function distance(a,b) local x,y=a.x-b.x,a.y-b.y; return math.sqrt(x*x+y*y) end
local function norm(x,y) local d=math.sqrt(x*x+y*y); if d<.001 then return 0,0 end; return x/d,y/d end
local function move(p,x,y,s,dt)
 local dx,dy=x-p.x,y-p.y; local d=math.sqrt(dx*dx+dy*dy)
 if d>.05 then local step=math.min(d,s*dt); p.x=clamp(p.x+dx/d*step,1,99); p.y=clamp(p.y+dy/d*step,1,63) end
end
local function coords(formation)
 local out={{x=5,y=32}}; local groups=formation=='4-4-2' and {4,4,2} or formation=='3-5-2' and {3,5,2} or {4,3,3}
 for g,n in ipairs(groups) do for i=1,n do out[#out+1]={x=({24,43,62})[g],y=64*i/(n+1)} end end
 return out
end
function M.new(profile,op,C,seed)
 local m={t=0,duration=120,home=0,away=0,players={},ball={x=50,y=32,vx=0,vy=0},owner=10,controlled=10,cooldown=1,pause=1.2,phase='kickoff',ended=false,op=op,scorers={},assists={},input={x=0,y=0},rng=C.rng(seed),formation=profile.formation,mentality=profile.mentality,notice='НАЧАЛО МАТЧА',lastPass=nil}
 local a,b=coords(profile.formation),coords('4-3-3')
 for i=1,22 do
  local home=i<=11; local n=home and i or i-11; local pos=(home and a or b)[n]
  local q=home and C.find(profile,profile.lineup[n]) or nil
  m.players[i]={x=home and pos.x or 100-pos.x,y=pos.y,bx=home and pos.x or 100-pos.x,by=pos.y,team=home and 1 or 2,number=n,rating=q and q.rating or op.rating,fitness=q and q.fitness or 100,id=q and q.id or ('cpu'..n),name=q and q.name or 'Соперник',gk=n==1}
 end
 m.players[10].x=50; m.players[10].y=32
 return m
end
function M.kickoff(m,team)
 for _,p in ipairs(m.players) do p.x=p.bx; p.y=p.by end
 m.owner=team==1 and 10 or 21; local p=m.players[m.owner]; p.x=50; p.y=32
 m.ball={x=50,y=32,vx=0,vy=0}; m.cooldown=1; m.lastPass=nil; m.shot=false
 if team==1 then m.controlled=m.owner end
end
function M.switch(m)
 if m.owner and m.players[m.owner].team==1 then m.controlled=m.owner; return end
 local target=m.owner and m.players[m.owner] or m.ball; local best,d=2,1e9
 for i=2,11 do local v=distance(m.players[i],target); if v<d then d=v; best=i end end
 m.controlled=best
end
function M.kick(m,idx,tx,ty,shot)
 if m.owner~=idx or m.pause>0 then return end
 local p=m.players[idx]; local dx,dy=norm(tx-p.x,ty-p.y)
 if dx==0 and dy==0 then return end
 local spread=(100-p.rating)*.0016
 if shot then dy=dy+(m.rng()-.5)*spread; dx,dy=norm(dx,dy) end
 m.ball.x=p.x+dx*1.3; m.ball.y=p.y+dy*1.3
 m.ball.vx=dx*(shot and 49 or 36); m.ball.vy=dy*(shot and 49 or 36)
 m.owner=nil; m.lastTouch=idx; m.shot=shot; m.flight=0; m.cooldown=.18
 if not shot then m.lastPass=idx end
end
function M.pass(m,idx)
 local p=m.players[idx]; local dir=p.team==1 and 1 or -1; local best,score=nil,-1e9
 for i,q in ipairs(m.players) do if q.team==p.team and i~=idx and not q.gk then
  local d=distance(p,q); local nearest=20
  for _,enemy in ipairs(m.players) do if enemy.team~=p.team then nearest=math.min(nearest,distance(q,enemy)) end end
  local s=(q.x-p.x)*dir*.5+nearest*1.3-math.abs(d-17)*.55
  if s>score then score=s; best=i end
 end end
 if best then local q=m.players[best]; M.kick(m,idx,q.x+dir*1.5,q.y,false) end
end
function M.command(m,action,arg)
 if m.ended or m.pause>0 then return end
 local idx=m.controlled; local p=m.players[idx]
 if action=='switch' then M.switch(m)
 elseif action=='pass' and m.owner==idx then M.pass(m,idx)
 elseif action=='shoot' and m.owner==idx then
  local y=arg and tonumber(arg.y); if not y or y~=y then y=32 end
  M.kick(m,idx,103,clamp(y,24,40),true)
 elseif action=='tackle' and m.owner and m.players[m.owner].team==2 and m.cooldown<=0 then
  if distance(p,m.players[m.owner])<4.8 and m.rng()<.64 then m.owner=idx; m.lastPass=nil; m.cooldown=.65 end
 elseif action=='target' and arg then
  local x,y=tonumber(arg.x),tonumber(arg.y)
  if x and y and x==x and y==y then m.target={x=clamp(x,1,99),y=clamp(y,1,63)} end
 end
end
local function goal(m,team)
 if team==1 then
  m.home=m.home+1
  local q=m.lastTouch and m.players[m.lastTouch]
  if q and q.team==1 then m.scorers[q.id]=(m.scorers[q.id] or 0)+1 end
  local assist=m.lastPass and m.players[m.lastPass]
  if assist and q and assist.team==1 and assist.id~=q.id then m.assists[assist.id]=(m.assists[assist.id] or 0)+1 end
 else m.away=m.away+1 end
 m.pause=2; m.notice=team==1 and 'ГОООЛ! ТВОЯ КОМАНДА ЗАБИВАЕТ' or 'ГОЛ СОПЕРНИКА'; m.phase='goal'
 M.kickoff(m,team==1 and 2 or 1)
end
function M.step(m,dt)
 if m.ended then return end
 if m.pause>0 then m.pause=math.max(0,m.pause-dt); return end
 m.phase='play'; m.t=m.t+dt; m.cooldown=math.max(0,m.cooldown-dt)
 if m.t>=m.duration then m.ended=true; m.phase='ended'; m.notice='ФИНАЛЬНЫЙ СВИСТОК'; return end
 local owner=m.owner and m.players[m.owner]
 if owner and owner.team==1 then m.controlled=m.owner end
 local ball=owner or m.ball
 local nearest={nil,nil}; local nd={1e9,1e9}
 for i,p in ipairs(m.players) do if not p.gk and i~=m.owner then local d=distance(p,ball); if d<nd[p.team] then nearest[p.team]=i; nd[p.team]=d end end end
 for i,p in ipairs(m.players) do
  local speed=(8+p.rating*.055)*(.7+.3*p.fitness/100)
  local dir=p.team==1 and 1 or -1
  if i==m.controlled then
   if math.abs(m.input.x)+math.abs(m.input.y)>.05 then
    m.target=nil; local dx,dy=norm(m.input.x,m.input.y); move(p,p.x+dx*10,p.y+dy*10,speed,dt)
   elseif m.target then move(p,m.target.x,m.target.y,speed,dt) end
  elseif i==m.owner then
   if p.gk then M.pass(m,i)
   else
    move(p,p.team==1 and 94 or 6,32+(p.by-32)*.35,speed*.87,dt)
    local goalDist=p.team==1 and 100-p.x or p.x
    if m.cooldown<=0 then
     if goalDist<29 and m.rng()<dt*2 then M.kick(m,i,p.team==1 and 103 or -3,25+m.rng()*14,true)
     elseif nd[3-p.team]<4 and m.rng()<dt*2 then M.pass(m,i) end
    end
   end
  elseif p.gk then
   move(p,p.team==1 and 4 or 96,clamp(ball.y,24,40),speed*.8,dt)
  elseif nearest[p.team]==i and (not owner or owner.team~=p.team) then
   move(p,ball.x,ball.y,speed*.97,dt)
  else
   local attacking=owner and owner.team==p.team
   local shift=attacking and 12 or -7
   if p.team==1 then shift=shift+(m.mentality=='attack' and 7 or m.mentality=='defend' and -7 or 0) end
   move(p,clamp(p.bx+dir*shift+(ball.x-50)*.22,8,92),clamp(p.by+(ball.y-32)*.2,4,60),speed*.72,dt)
  end
 end
 owner=m.owner and m.players[m.owner]
 if owner then
  m.ball.x=owner.x+(owner.team==1 and .9 or -.9); m.ball.y=owner.y; m.ball.vx=0; m.ball.vy=0
  if m.cooldown<=0 then
   local challenger=nearest[3-owner.team]
   if challenger and distance(m.players[challenger],owner)<2.1 and m.rng()<dt*1.9 then
    m.owner=challenger; m.cooldown=.7; m.lastPass=nil; m.notice='ПЕРЕХВАТ'
   end
  end
 else
  m.flight=(m.flight or 0)+dt
  m.ball.x=m.ball.x+m.ball.vx*dt; m.ball.y=m.ball.y+m.ball.vy*dt
  local drag=math.max(0,1-dt*.34); m.ball.vx=m.ball.vx*drag; m.ball.vy=m.ball.vy*drag
  if m.ball.x>100 or m.ball.x<0 then
   if m.ball.y>23 and m.ball.y<41 then goal(m,m.ball.x>100 and 1 or 2); return end
   m.pause=.75; m.notice='УДАР ОТ ВОРОТ'; m.owner=m.ball.x>100 and 12 or 1; m.cooldown=.7; m.lastPass=nil
  elseif m.ball.y<0 or m.ball.y>64 then
   local team=m.lastTouch and 3-m.players[m.lastTouch].team or 1
   local idx=nearest[team] or (team==1 and 5 or 16)
   m.owner=idx; m.players[idx].x=clamp(m.ball.x,3,97); m.players[idx].y=clamp(m.ball.y,2,62)
   m.pause=.5; m.cooldown=.7; m.notice='ВВОД МЯЧА'; m.lastPass=nil
  elseif m.cooldown<=0 then
   for i,p in ipairs(m.players) do
    if not (i==m.lastTouch and m.flight<.45) then
     local reach=p.gk and 2.5+p.rating*.008 or 1.55
     if distance(p,m.ball)<reach then
      if p.gk and m.shot and m.rng()>.78 then
       -- A fast shot may beat the keeper; one roll per passage.
       m.cooldown=.12
      else
       m.owner=i; m.cooldown=.45; if m.lastTouch and m.players[m.lastTouch].team~=p.team then m.lastPass=nil end
       m.shot=false; break
      end
     end
    end
   end
  end
 end
end
function M.snapshot(m)
 local players={}; for i,p in ipairs(m.players) do players[i]={x=p.x,y=p.y,team=p.team,number=p.number,gk=p.gk} end
 return {players=players,ball={x=m.ball.x,y=m.ball.y},home=m.home,away=m.away,minute=math.min(90,math.floor(m.t/m.duration*90)),controlled=m.controlled,owner=m.owner,notice=m.pause>0 and m.notice or '',ended=m.ended,op=m.op.name}
end
return M
