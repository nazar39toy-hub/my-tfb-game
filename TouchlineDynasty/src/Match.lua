-- Deterministic server-authoritative evolution of the original 11v11 engine.
-- Scores home/away retain USER/OPPONENT orientation; userHome describes venue.
-- Simplified offside: evaluated at a targeted pass, at least 2 opponents nearer
-- their own goal, opponent half, recipient ahead of the ball; no offside on restarts.
local Config=require(script.Parent.MatchConfig)
local M={Config=Config}
local atan2=math.atan2 or function(y,x) return math.atan(y,x) end
local function clamp(v,a,b) return math.max(a,math.min(b,v)) end
local function finite(v) return type(v)=='number' and v==v and math.abs(v)<1e9 end
local function distance(a,b) local x,y=a.x-b.x,a.y-b.y; return math.sqrt(x*x+y*y) end
local function norm(x,y) local d=math.sqrt(x*x+y*y); if d<.001 then return 0,0 end; return x/d,y/d end
local function copy(v) if type(v)~='table' then return v end; local t={}; for k,x in pairs(v) do t[k]=copy(x) end; return t end
local function dir(m,team) return team==1 and m.direction or -m.direction end
local function stat() return {shots=0,onTarget=0,passes=0,completed=0,possession=0,fouls=0,yellow=0,red=0,corners=0,offsides=0,saves=0} end
local function event(m,key,args)
 m.notice=key; m.events[#m.events+1]={key=key,params=args or {},time=m.t}
 if #m.events>Config.eventLimit then table.remove(m.events,1) end
end
local function style(m,team) return Config.styles[m.styles[team]] or Config.styles.possession end
local function coords(formation)
 local groups={};for n in tostring(formation):gmatch('%d+')do groups[#groups+1]=tonumber(n)end
 if #groups<3 or #groups>4 then groups={4,3,3}end
 local out={{x=5,y=32,role='GK'}};local x=#groups==4 and {22,35,50,65}or{24,43,62}
 for g,n in ipairs(groups)do for i=1,n do out[#out+1]={x=x[g],y=64*i/(n+1),role=g==1 and 'DEF'or g==#groups and 'FWD'or'MID'}end end
 return out
end
local function attributes(q,rating)
 local a=q and q.attributes or {}; local out={}
 for _,key in ipairs({'pace','shooting','passing','dribbling','defending','physical','goalkeeping'}) do out[key]=clamp(tonumber(a[key]) or rating,1,99) end
 return out
end
local function footballer(m,q,n,team,base,role)
 local rating=q and q.rating or base
 if q and m.C.effective then rating=m.C.effective(m.profile,q,role) end
 local venue=not m.op.neutral and(m.op.home and team==1 or not m.op.home and team==2)and 1.018 or 1
 local difficulty=team==2 and (Config.difficulty[m.difficulty] or 1) or 1
 local a=attributes(q,rating)
 local keeping={}
 -- A role/fitness/form adjustment is applied to every skill in both all-AI and manual play.
 local factor=rating/math.max(1,q and q.rating or base)*venue*difficulty
 for k,v in pairs(a) do a[k]=clamp(v*factor,1,105) end
 for _,key in ipairs({'handling','reflexes','positioning'})do keeping[key]=clamp(((q and q.keeping and q.keeping[key])or(q and q.attributes.goalkeeping)or base)*factor,1,105)end
 return {x=0,y=0,bx=0,by=0,team=team,number=n,rating=clamp(rating*venue*difficulty,1,105),fitness=q and q.fitness or 100,
  id=q and q.id or ('cpu'..n),name=q and q.name or m.op.name,gk=n==1,role=role,attributes=a,keeping=keeping,
  active=true,sentOff=false,injured=false,card=0,angle=0,vx=0,vy=0,personal={goals=0,assists=0,saves=0,tackles=0,minutes=0}}
end
function M.new(profile,op,C,seed)
 local mode=profile.matchMode or 'manual'
 if mode~='manual' and mode~='highlights' and mode~='simulate' then mode='manual' end
 local m={t=0,tick=0,duration=Config.duration,regulation=Config.duration,extraEnd=Config.duration+Config.extraTime,
  home=0,away=0,players={},ball={x=50,y=32,vx=0,vy=0},owner=10,controlled=10,cooldown=1,pause=1.2,
  phase='kickoff',ended=false,op=copy(op),scorers={},assists={},ownGoals={},input={x=0,y=0},rng=C.rng(seed),seed=seed,
  formation=profile.formation,mentality=profile.mentality,notice='match.kickoff',lastPass=nil,
  profile=profile,C=C,mode=mode,difficulty=profile.difficulty or 'normal',userHome=op.home==true,
  direction=op.home==false and -1 or 1,half=1,halftimeDone=false,extra=false,extraHalfDone=false,
  styles={profile.style or profile.tacticStyle or 'possession',op.style or 'counter'},stats={stat(),stat()},
  injuries={},redCards={},yellowCards={},minutes={},events={},replay={},replayId=0,replayClock=0,
  aiClock=0,targets={},saveAttempts={},substitutions=0,usedSubs={},bench={},sprint=false,seq=0,penWin=nil}
 local a,b=coords(profile.formation),coords(op.formation or '4-3-3')
 for i=1,22 do
  local team=i<=11 and 1 or 2; local n=team==1 and i or i-11; local pos=(team==1 and a or b)[n]
  local q=team==1 and C.find(profile,profile.lineup[n]) or nil
  local p=footballer(m,q,n,team,op.rating or 50,pos.role); p.bx=dir(m,team)>0 and pos.x or 100-pos.x; p.by=pos.y; p.x=p.bx; p.y=p.by
  m.players[i]=p
 end
 local selected={}; for _,id in ipairs(profile.lineup) do selected[id]=true end
 for _,q in ipairs(profile.roster) do if not selected[q.id] and (q.injuredDays or q.injury or 0)==0 and (q.suspension or 0)==0 then m.bench[q.id]=q end end
 m.players[10].x=50; m.players[10].y=32
 event(m,'match.kickoff'); return m
end
local function move(p,x,y,s,dt)
 local ox,oy=p.x,p.y; local dx,dy=x-p.x,y-p.y; local d=math.sqrt(dx*dx+dy*dy)
 if d>.05 then local step=math.min(d,s*dt); p.x=clamp(p.x+dx/d*step,.7,99.3); p.y=clamp(p.y+dy/d*step,.7,63.3); p.angle=atan2(dy,dx) end
 p.vx=(p.x-ox)/dt; p.vy=(p.y-oy)/dt
end
local function nearest(m,team,target,exclude,keeper)
 local best,d=nil,1e9
 for i,p in ipairs(m.players) do if p.active and p.team==team and i~=exclude and (keeper or not p.gk) then
  local n=distance(p,target); if n<d then best,d=i,n end
 end end
 return best,d
end
function M.kickoff(m,team)
 for _,p in ipairs(m.players) do if p.active then p.x=p.bx; p.y=p.by; p.vx=0; p.vy=0 end end
 local idx=nearest(m,team,{x=50,y=32},nil,false)
 if not idx then idx=nearest(m,team,{x=50,y=32},nil,true) end
 m.owner=idx; if idx then m.players[idx].x=50; m.players[idx].y=32 end
 m.ball={x=50,y=32,vx=0,vy=0}; m.cooldown=1; m.lastPass=nil; m.passTarget=nil; m.shot=false; m.lastTouch=idx
 if team==1 then m.controlled=idx end
end
local function flip(m)
 m.direction=-m.direction
 for _,p in ipairs(m.players) do p.bx=100-p.bx end
end
local function keeperIndex(m,team)
 for i,p in ipairs(m.players) do if p.active and p.team==team and p.gk then return i end end
 return nearest(m,team,{x=dir(m,team)>0 and 2 or 98,y=32},nil,true)
end
function M.restart(m,kind,team,x,y)
 local idx
 if kind=='goalKick' then idx=keeperIndex(m,team) else idx=nearest(m,team,{x=x,y=y},nil,false) end
 if team==1 and m.profile.setPieces then local key=kind=='freeKick'and'freeKick'or kind=='corner'and'corner'or kind=='penalty'and'penalty';local id=key and m.profile.setPieces[key];if id then for i,q in ipairs(m.players)do if q.id==id and q.active and q.team==1 then idx=i;break end end end end
 if not idx then idx=keeperIndex(m,team) end
 if not idx then m.ended=true; m.phase='ended'; return end
 local p=m.players[idx]; p.x=clamp(x,1,99); p.y=clamp(y,1,63)
 m.owner=idx; m.lastTouch=idx; m.ball={x=p.x,y=p.y,vx=0,vy=0}; m.cooldown=.8; m.pause=Config.restartPause
 m.phase='restart'; m.restartKind=kind; m.lastPass=nil; m.passTarget=nil; m.shot=false; m.noOffside=true
 event(m,'match.'..kind,{team=team}); if team==1 then m.controlled=idx end
end
function M.switch(m)
 if m.owner and m.players[m.owner].active and m.players[m.owner].team==1 then m.controlled=m.owner; return end
 local best=nearest(m,1,m.owner and m.players[m.owner] or m.ball,nil,false)
 if best then m.controlled=best end
end
local function isOffside(m,idx,receiver)
 if m.noOffside then return false end
 local p,q=m.players[idx],m.players[receiver]; local d=dir(m,p.team)
 if (q.x-50)*d<=0 or (q.x-p.x)*d<=.2 then return false end
 local defenders={}
 for _,e in ipairs(m.players) do if e.active and e.team~=p.team then defenders[#defenders+1]=e.x*d end end
 table.sort(defenders,function(a,b)return a>b end)
 return #defenders>=2 and q.x*d>defenders[2]+.2
end
function M.kick(m,idx,tx,ty,shot,power,receiver)
 if m.owner~=idx or m.pause>0 or not m.players[idx] or not m.players[idx].active then return false end
 local p=m.players[idx]; local dx,dy=norm(tx-p.x,ty-p.y)
 if dx==0 and dy==0 then return false end
 if receiver and isOffside(m,idx,receiver) then
  m.stats[p.team].offsides=m.stats[p.team].offsides+1; local q=m.players[receiver]
  M.restart(m,'offside',3-p.team,q.x,q.y); return false
 end
 power=clamp(finite(power) and power or .78,.25,1)
 local skill=shot and p.attributes.shooting or p.attributes.passing*style(m,p.team).passing
 local spread=(110-skill)*.0018
 dy=dy+(m.rng()-.5)*spread*(shot and 1.3 or .45); dx,dy=norm(dx,dy)
 m.ball.x=p.x+dx*1.2; m.ball.y=p.y+dy*1.2
 local speed=shot and (29+power*24) or (24+power*14)
 m.ball.vx=dx*speed; m.ball.vy=dy*speed; m.owner=nil; m.lastTouch=idx; m.shot=shot; m.flight=0; m.cooldown=.16
 m.saveAttempts={}; m.noOffside=false; m.passTarget=receiver
 if shot then
  m.passInFlight=false; m.lastShooter=idx; m.shotSkill=skill; m.shotPower=power; m.stats[p.team].shots=m.stats[p.team].shots+1
  local gx=dir(m,p.team)>0 and 100 or 0
  local projected=p.y+(gx-p.x)*dy/(math.abs(dx)>.001 and dx or .001)
  if projected>23 and projected<41 then m.stats[p.team].onTarget=m.stats[p.team].onTarget+1 end
 else m.lastPass=idx; m.passInFlight=true; m.stats[p.team].passes=m.stats[p.team].passes+1 end
 return true
end
function M.pass(m,idx,through)
 local p=m.players[idx]; if not p or not p.active then return end
 local d=dir(m,p.team); local best,score=nil,-1e9
 for i,q in ipairs(m.players) do if q.active and q.team==p.team and i~=idx and not q.gk then
  local dist=distance(p,q); local _,enemy=nearest(m,3-p.team,q,nil,true)
  local s=(q.x-p.x)*d*.35+math.min(enemy,15)*1.4-math.abs(dist-18)*.65
  if isOffside(m,idx,i) then s=s-50 end
  if through then s=s+(q.x-p.x)*d*.65 end
  if s>score then score=s; best=i end
 end end
 if best then local q=m.players[best]; return M.kick(m,idx,clamp(q.x+d*(through and 7 or 1),1,99),q.y,false,through and .85 or .65,best) end
end
local function removal(m,idx,kind)
 local p=m.players[idx]; if not p or not p.active then return end
 p.active=false; p.sentOff=kind=='redCard'; p.injured=kind=='injury'
 if m.owner==idx then m.owner=nil end
 if m.controlled==idx then M.switch(m) end
 if kind=='redCard' then m.stats[p.team].red=m.stats[p.team].red+1; if p.team==1 then m.redCards[p.id]=1 end
 elseif p.team==1 then m.injuries[p.id]=1+m.rng(0,2) end
 event(m,'match.'..kind,{id=p.id,team=p.team})
 local reds=0;for _,q in ipairs(m.players)do if q.team==p.team and q.sentOff then reds=reds+1 end end
 if reds>=5 then m.technicalLoser=p.team;m.home=p.team==1 and 0 or 3;m.away=p.team==1 and 3 or 0;m.ended=true;m.phase='ended';event(m,'match.technicalDefeat')end
end
function M.sendOff(m,idx) removal(m,idx,'redCard') end
local function tackle(m,idx)
 local p=m.players[idx]; local enemy=m.owner and m.players[m.owner]
 if not p or not p.active or not enemy or enemy.team==p.team or m.cooldown>0 or distance(p,enemy)>4.2 then return false end
 m.cooldown=.6
 local clean=clamp(.55+(p.attributes.defending-enemy.attributes.dribbling)*.006,.18,.85)
 local roll=m.rng()
 if roll<clean then m.owner=idx; m.lastPass=nil; p.personal.tackles=p.personal.tackles+1; return true end
 if roll>clean+.18 then
  local team=enemy.team; m.stats[p.team].fouls=m.stats[p.team].fouls+1
  if m.rng()<.48 then
   p.card=p.card+1; m.stats[p.team].yellow=m.stats[p.team].yellow+1
   if p.team==1 then m.yellowCards[p.id]=(m.yellowCards[p.id] or 0)+1 end
   event(m,'match.yellowCard',{id=p.id,team=p.team}); if p.card>=2 or m.rng()<.035 then removal(m,idx,'redCard') end
  end
  if m.ended then return true end
  if m.rng()<.035 then removal(m,m.owner,'injury') end
  local inBox=dir(m,team)>0 and enemy.x>84 or dir(m,team)<0 and enemy.x<16
  local kind=inBox and enemy.y>14 and enemy.y<50 and 'penalty' or 'freeKick'
  M.restart(m,kind,team,kind=='penalty' and (dir(m,team)>0 and 88 or 12) or enemy.x,kind=='penalty' and 32 or enemy.y)
  return true
 end
 return false
end
function M.substitute(m,outId,inId)
 if m.substitutions>=Config.maxSubstitutions or type(outId)~='string' or type(inId)~='string' or m.pause<=0 then return false,'match.substitutionUnavailable' end
 local q=m.bench[inId]; if not q or m.usedSubs[inId] then return false,'match.substitutionUnavailable' end
 for i,p in ipairs(m.players) do if p.team==1 and p.id==outId and not p.sentOff then
  if p.gk and q.pos~='GK' then return false,'match.goalkeeperRequired' end
  local replacement=footballer(m,q,p.number,1,m.C.effective(m.profile,q,p.role),p.role); replacement.x=p.x; replacement.y=p.y; replacement.bx=p.bx; replacement.by=p.by
  m.departed=m.departed or {};m.departed[#m.departed+1]=p;if q.pos=='GK'then local goalkeeper=false;for _,other in ipairs(m.players)do if other.team==1 and other.active and other.gk then goalkeeper=true end end;if not goalkeeper then replacement.gk=true;replacement.role='GK';replacement=footballer(m,q,p.number,1,q.rating,'GK');replacement.gk=true;replacement.x=p.x;replacement.y=p.y;replacement.bx=p.bx;replacement.by=p.by end end
  m.players[i]=replacement; m.substitutions=m.substitutions+1; m.usedSubs[outId]=true; m.usedSubs[inId]=true; m.bench[inId]=nil
  event(m,'match.substitution',{out=outId,player=inId}); return true
 end end
 return false,'match.playerUnavailable'
end
local function shootoutDone(m)
 local p=m.penalties; local a,b=p.scores[1],p.scores[2]; local na,nb=p.taken[1],p.taken[2]
 local done=(na<=5 and nb<=5 and (a>b+5-nb or b>a+5-na)) or (na>=5 and nb>=5 and na==nb and a~=b)
 if done then m.penWin=a>b; m.ended=true; m.phase='ended'; event(m,'match.ended'); return true end
 return false
end
local function preparePenalty(m)
 local p=m.penalties; p.wait=0; p.aiAim=(m.rng()-.5)*1.8; p.aiDive=m.rng(-1,1); p.execution=m.rng(); p.power=.72+m.rng()*.25
end
function M.startPenalties(m)
 m.phase='penalties'; m.pause=0; m.owner=nil; m.input={x=0,y=0}; m.penalties={scores={0,0},taken={0,0},turn=1,history={},orders={{},{}}}
 local teams={{},{}};for i,p in ipairs(m.players)do if p.active then teams[p.team][#teams[p.team]+1]=i end end
 local count=math.min(#teams[1],#teams[2]);for team=1,2 do
  while #teams[team]>count do local remove=#teams[team];for n=#teams[team],1,-1 do if not m.players[teams[team][n]].gk then remove=n;break end end;table.remove(teams[team],remove)end
  local preferred=team==1 and m.profile.setPieces and m.profile.setPieces.penalty
  table.sort(teams[team],function(a,b)if a==b then return false end;local x,y=m.players[a],m.players[b];if x.id==preferred then return true end;if y.id==preferred then return false end;if x.gk~=y.gk then return not x.gk end;return x.number<y.number end);m.penalties.orders[team]=teams[team]
 end
 preparePenalty(m); event(m,'match.penalties')
end
function M.penalty(m,arg)
 if m.phase~='penalties' or m.ended then return false end
 arg=arg or {}; local p=m.penalties; local team=p.turn
 local aim=team==1 and (finite(arg.aim) and clamp(arg.aim,-1,1) or 0) or p.aiAim
 local power=team==1 and (finite(arg.power) and clamp(arg.power,.25,1) or .8) or p.power
 local dive=team==1 and p.aiDive or (finite(arg.dive) and clamp(arg.dive,-1,1) or 0)
 local order=p.orders[team];local shooter=m.players[order[(p.taken[team]%#order)+1]]; local keeper=keeperIndex(m,3-team)
 local shooting=shooter and shooter.attributes.shooting or 50; local keeping=keeper and (m.players[keeper].keeping.reflexes*.6+m.players[keeper].keeping.positioning*.4)or 30
 local probability=clamp(.77+(shooting-keeping)*.002+math.abs(aim)*.09-math.max(0,.48-math.abs(aim-dive))*.42-(power>.96 and .08 or 0),.25,.96)
 local scored=p.execution<probability
 p.taken[team]=p.taken[team]+1; if scored then p.scores[team]=p.scores[team]+1 end
 p.history[#p.history+1]={team=team,shooter=shooter.id,goal=scored,aim=aim,dive=dive}
 event(m,scored and 'match.penaltyGoal' or 'match.penaltySave',{team=team})
 if not shootoutDone(m) then p.turn=3-team; preparePenalty(m) end
 return true
end
function M.setMode(m,mode)
 if mode~='manual' and mode~='highlights' and mode~='simulate' then return false end
 if m.t>0 and m.mode~=mode then m.recordMode='mixed' end
 m.mode=mode; m.input={x=0,y=0}; m.target=nil; m.sprint=false; return true
end
local function manualActive(m)
 if m.mode=='simulate' then return false end
 if m.mode=='manual' then return true end
 -- Highlights only grants control in either penalty-area approach, never rerolls.
 local owner=m.owner and m.players[m.owner]
 return (owner and owner.team==1 and (owner.x-50)*dir(m,1)>14) or (owner and owner.team==2 and (owner.x-50)*dir(m,2)>27) or false
end
M.interactive=manualActive
function M.command(m,action,arg)
 if m.ended or type(action)~='string' then return false end
 arg=arg or {}
 if action=='teamTalk' then if (m.teamTalks or 0)>=2 then return false,'match.pauseLimit' end;m.teamTalks=(m.teamTalks or 0)+1;m.pause=30;return true end
 if action=='mode' then return M.setMode(m,arg.value) end
 if action=='penalty' then return M.penalty(m,arg) end
 if action=='substitute' then return M.substitute(m,arg.out,arg.inId) end
 if action=='continue' then m.pause=0; return true end
 if action=='style' and Config.styles[arg.value] then m.styles[1]=arg.value; return true end
 if action=='sprint' then m.sprint=arg.enabled==true; return true end
 if m.pause>0 or m.phase=='penalties' or not manualActive(m) then return false end
 local idx=m.controlled; local p=idx and m.players[idx]; if not p or not p.active then M.switch(m); return false end
 if action=='switch' then M.switch(m); return true
 elseif action=='pass' and m.owner==idx then return M.pass(m,idx,false)
 elseif action=='through' and m.owner==idx then return M.pass(m,idx,true)
 elseif action=='shoot' and m.owner==idx then
  return M.kick(m,idx,dir(m,1)>0 and 103 or -3,finite(arg.y) and clamp(arg.y,0,64) or 32,true,arg.power)
 elseif action=='tackle' then return tackle(m,idx)
 elseif action=='target' and finite(arg.x) and finite(arg.y) then m.target={x=clamp(arg.x,1,99),y=clamp(arg.y,1,63)}; return true end
 return false
end
local function saveReplay(m)
 m.replayClock=m.replayClock+Config.step
 if m.replayClock<.1 then return end; m.replayClock=0
 local f={time=m.t,ball={x=m.ball.x,y=m.ball.y},players={}}
 for i,p in ipairs(m.players) do f.players[i]={x=p.x,y=p.y,team=p.team,number=p.number,active=p.active,angle=p.angle} end
 m.replay[#m.replay+1]=f; if #m.replay>Config.replayFrames then table.remove(m.replay,1) end
end
local function goal(m,team)
 if team==1 then m.home=m.home+1 else m.away=m.away+1 end
 local q=m.lastTouch and m.players[m.lastTouch]
 if q and q.team==team then
  q.personal.goals=q.personal.goals+1
  if team==1 then m.scorers[q.id]=(m.scorers[q.id] or 0)+1 end
  local a=m.lastPass and m.players[m.lastPass]
  if a and a.team==team and a.id~=q.id then a.personal.assists=a.personal.assists+1; if team==1 then m.assists[a.id]=(m.assists[a.id] or 0)+1 end end
 elseif q then m.ownGoals[q.id]=(m.ownGoals[q.id] or 0)+1 end
 m.lastReplay=copy(m.replay); m.replayId=m.replayId+1
 m.pause=2; m.phase='goal'; event(m,team==1 and 'match.goal' or 'match.opponentGoal',{scorer=q and q.name or '',ownGoal=q and q.team~=team or false})
 M.kickoff(m,3-team)
end
local function aiDecide(m)
 local owner=m.owner and m.players[m.owner]; local ball=owner or m.ball
 local near={nearest(m,1,ball,m.owner,false),nearest(m,2,ball,m.owner,false)}
 for i,p in ipairs(m.players) do if p.active then
  local d=dir(m,p.team); local s=style(m,p.team); local attacking=owner and owner.team==p.team
  if i==m.owner then
   local gx=d>0 and 100 or 0; local distanceGoal=math.abs(gx-p.x)
   local _,enemy=nearest(m,3-p.team,p,nil,false)
   if p.gk then m.targets[i]={x=p.bx,y=p.by}; if m.cooldown<=0 then M.pass(m,i) end
   else
    local ty=32+(p.by-32)*(m.styles[p.team]=='wings' and .65 or .22)
    m.targets[i]={x=d>0 and 94 or 6,y=ty}
    if not (p.team==1 and manualActive(m)) and m.cooldown<=0 then
     if m.restartKind=='penalty' or (distanceGoal<27 and math.abs(p.y-32)<18 and m.rng()<.48) then M.kick(m,i,gx+d*3,25+m.rng()*14,true,.6+m.rng()*.4)
     elseif (enemy<4.8 or m.styles[p.team]=='possession' and m.rng()<.23) then M.pass(m,i,m.styles[p.team]=='counter') end
    end
   end
  elseif p.gk then
   local advance=clamp((50-math.abs(ball.x-50))*.13,0,6)
   m.targets[i]={x=d>0 and 4+advance or 96-advance,y=clamp(32+(ball.y-32)*(.4+p.keeping.positioning*.002),23,41)}
  elseif near[p.team]==i and (not owner or owner.team~=p.team) then
   m.targets[i]={x=ball.x,y=ball.y}
  else
   local shift=attacking and 11*s.depth or -9*(2-s.depth)
   local mentality=p.team==1 and m.mentality or(m.op.mentality or'balanced');shift=shift+(mentality=='attack'and 5 or mentality=='defend'and-5 or 0)
   local x=p.bx+d*shift+(ball.x-50)*.19
   local y=32+(p.by-32)*s.width+(ball.y-32)*.16
   if not attacking and owner and s.press>1.2 and distance(p,owner)<17 then x=owner.x-d*2; y=owner.y+(p.by<32 and -4 or 4)
   elseif not attacking and owner then x=x*.8+(owner.x-d*7)*.2; y=y*.8+owner.y*.2 end
   m.targets[i]={x=clamp(x,6,94),y=clamp(y,3,61)}
  end
 end end
end
local function collect(m,idx)
 local p=m.players[idx]
 if m.passInFlight and m.lastPass and m.players[m.lastPass].team==p.team and m.lastPass~=idx then m.stats[p.team].completed=m.stats[p.team].completed+1
 elseif m.lastTouch and m.players[m.lastTouch].team~=p.team then m.lastPass=nil end
 m.owner=idx; m.cooldown=.32; m.shot=false; m.passInFlight=false; m.passTarget=nil; m.restartKind=nil
end
local function ballStep(m,dt)
 local owner=m.owner and m.players[m.owner]
 if owner and owner.active then
  m.ball.x=owner.x+dir(m,owner.team)*.85; m.ball.y=owner.y; m.ball.vx=0; m.ball.vy=0
  m.stats[owner.team].possession=m.stats[owner.team].possession+dt
  if m.cooldown<=0 then
   local idx,d=nearest(m,3-owner.team,owner,nil,false)
   if idx and d<2.5 and not (m.players[idx].team==1 and manualActive(m)) then tackle(m,idx) end
  end
  return
 end
 m.owner=nil; m.flight=(m.flight or 0)+dt
 m.ball.x=m.ball.x+m.ball.vx*dt; m.ball.y=m.ball.y+m.ball.vy*dt
 local drag=math.max(0,1-dt*.34); m.ball.vx=m.ball.vx*drag; m.ball.vy=m.ball.vy*drag
 if m.ball.x>100 or m.ball.x<0 then
  local scoring=m.ball.x>100 and (m.direction>0 and 1 or 2) or (m.direction>0 and 2 or 1)
  if m.ball.y>23 and m.ball.y<41 then goal(m,scoring); return end
  local defending=3-scoring; local touch=m.lastTouch and m.players[m.lastTouch].team
  if touch==defending then
   m.stats[scoring].corners=m.stats[scoring].corners+1
   M.restart(m,'corner',scoring,m.ball.x>100 and 99 or 1,m.ball.y<32 and 1 or 63)
  else M.restart(m,'goalKick',defending,m.ball.x>100 and 94 or 6,32) end
 elseif m.ball.y<0 or m.ball.y>64 then
  local team=m.lastTouch and 3-m.players[m.lastTouch].team or 1
  M.restart(m,'throwIn',team,clamp(m.ball.x,2,98),m.ball.y<0 and 1 or 63)
 elseif m.cooldown<=0 then
  for i,p in ipairs(m.players) do if p.active and not (i==m.lastTouch and m.flight<.45) then
   local reach=p.gk and 2.4+p.keeping.reflexes*.009 or 1.45
   if distance(p,m.ball)<reach then
    if p.gk and m.shot and (not m.lastTouch or m.players[m.lastTouch].team~=p.team) then
     if not m.saveAttempts[i] then
      m.saveAttempts[i]=true
      local probability=clamp(.66+(p.keeping.reflexes-(m.shotSkill or 50))*.004-(m.shotPower or .8)*.09,.25,.9)
      if m.rng()<probability then
       p.personal.saves=p.personal.saves+1; m.stats[p.team].saves=m.stats[p.team].saves+1
       if m.rng()<clamp(.35-p.keeping.handling*.0025,.08,.32)then
        m.ball.vx=-m.ball.vx*.3; m.ball.vy=(m.rng()-.5)*18; m.cooldown=.3; m.shot=false; m.lastTouch=i; m.lastPass=nil
       else collect(m,i) end
       break
      end
     end
    else collect(m,i); break end
   end
  end end
 end
end
local function terminal(m)
 m.ended=true; m.phase='ended'; m.input={x=0,y=0}; event(m,'match.ended')
end
function M.step(m,dt)
 if m.ended or not finite(dt) or dt<=0 then return end
 dt=math.min(dt,.1); m.tick=m.tick+1
 if m.phase=='penalties' then
  local p=m.penalties; p.wait=p.wait+dt
  if m.mode=='simulate' or p.wait>=Config.penaltyTimeout then M.penalty(m,{aim=p.aiAim,power=p.power,dive=p.aiDive}) end
  return
 end
 if m.pause>0 then m.pause=math.max(0,m.pause-dt); return end
 if not m.halftimeDone and m.t>=m.regulation/2 then
  m.halftimeDone=true; m.half=2; flip(m); M.kickoff(m,2); m.phase='halftime'; m.pause=Config.halftimePause; event(m,'match.halftime'); return
 end
 if m.t>=m.regulation and not m.extra then
  if m.op.kind~='league' and m.op.kind~='friendly' and m.home==m.away then
   m.extra=true; m.half=3; m.phase='extraTime'; m.pause=1.5; M.kickoff(m,1); event(m,'match.extraTime'); return
  else terminal(m); return end
 end
 if m.extra and not m.extraHalfDone and m.t>=m.regulation+Config.extraTime/2 then
  m.extraHalfDone=true; m.half=4; flip(m); M.kickoff(m,2); m.phase='halftime'; m.pause=1.5; event(m,'match.halftime'); return
 end
 if m.extra and m.t>=m.extraEnd then if m.home==m.away then M.startPenalties(m) else terminal(m) end; return end
 m.phase='play'; m.t=m.t+dt; m.cooldown=math.max(0,m.cooldown-dt)
 local owner=m.owner and m.players[m.owner]; if owner and owner.team==1 and owner.active then m.controlled=m.owner end
 if not m.controlled or not m.players[m.controlled].active then M.switch(m) end
 m.aiClock=m.aiClock+dt; if m.aiClock>=Config.aiInterval then m.aiClock=m.aiClock-Config.aiInterval; aiDecide(m) end
 local manual=manualActive(m)
 local ix=finite(m.input.x) and clamp(m.input.x,-1,1) or 0; local iy=finite(m.input.y) and clamp(m.input.y,-1,1) or 0
 for i,p in ipairs(m.players) do if p.active then
  p.personal.minutes=p.personal.minutes+dt/m.regulation*90; if p.team==1 then m.minutes[p.id]=(m.minutes[p.id] or 0)+dt/m.regulation*90 end
  local s=style(m,p.team); local sprint=i==m.controlled and manual and m.sprint and p.fitness>5
  local speed=(7.8+p.attributes.pace*.055)*(.65+.35*p.fitness/100)*s.speed*(sprint and 1.32 or 1)
  p.fitness=clamp(p.fitness-dt*(sprint and .52 or .035)*s.stamina,0,100)
  if i==m.controlled and manual then
   if math.abs(ix)+math.abs(iy)>.05 then m.target=nil; local dx,dy=norm(ix,iy); move(p,p.x+dx*10,p.y+dy*10,speed,dt)
   elseif m.target then move(p,m.target.x,m.target.y,speed,dt) else p.vx=0; p.vy=0 end
  else local target=m.targets[i]; if target then move(p,target.x,target.y,speed*(p.gk and .85 or .9),dt) end end
 end end
 ballStep(m,dt); saveReplay(m)
end
function M.simulate(profile,op,C,seed)
 local m=M.new(profile,op,C,seed); M.setMode(m,'simulate')
 for _=1,15000 do M.step(m,Config.step); if m.ended then return m end end
 error('Match exceeded deterministic simulation step budget')
end
function M.replay(m) return copy(m.lastReplay or {}) end
function M.statistics(m)
 local shootout=m.penalties and {scores=copy(m.penalties.scores),taken=copy(m.penalties.taken),history=copy(m.penalties.history)}or nil
 local stats={shootout=shootout,fitness={},teams=copy(m.stats),ratings={},playerOfMatch=nil,injuries=copy(m.injuries),redCards=copy(m.redCards),yellowCards=copy(m.yellowCards),minutes=copy(m.minutes),ownGoals=copy(m.ownGoals)}
 local best=-1
 local participants={};for _,p in ipairs(m.players)do participants[#participants+1]=p end;for _,p in ipairs(m.departed or {})do participants[#participants+1]=p end
 for _,p in ipairs(participants) do
  if p.team==1 then stats.fitness[p.id]=p.fitness end
  local r=clamp(6+p.personal.goals*.8+p.personal.assists*.45+p.personal.saves*.12+p.personal.tackles*.08-p.card*.35-(p.sentOff and 1 or 0),1,10)
  stats.ratings[p.id]=math.floor(r*10)/10
  if r>best then best=r; stats.playerOfMatch={id=p.id,name=p.name,team=p.team,rating=stats.ratings[p.id]} end
 end
 local total=m.stats[1].possession+m.stats[2].possession
 for i=1,2 do local s=stats.teams[i]; s.possessionPercent=total>0 and math.floor(s.possession/total*100+.5) or 50; s.passAccuracy=s.passes>0 and math.floor(s.completed/s.passes*100+.5) or 0 end
 return stats
end
function M.snapshot(m)
 m.seq=m.seq+1
 local players={}; for i,p in ipairs(m.players) do players[i]={x=math.floor(p.x*100)/100,y=math.floor(p.y*100)/100,team=p.team,number=p.number,gk=p.gk,active=p.active,angle=p.angle,fitness=math.floor(p.fitness),card=p.card,id=p.id} end
 local captain;for i,p in ipairs(m.players)do if p.team==1 and p.active then if not captain then captain=i end;if p.id==m.profile.captain then captain=i;break end end end
 local penalties
 if m.penalties then penalties={scores=copy(m.penalties.scores),taken=copy(m.penalties.taken),turn=m.penalties.turn,history=copy(m.penalties.history),wait=m.penalties.wait} end
 return {players=players,ball={x=m.ball.x,y=m.ball.y},home=m.home,away=m.away,minute=math.min(m.extra and 120 or 90,math.floor(m.t/m.regulation*90)),
  controlled=m.controlled,owner=m.owner,notice=(m.pause>0 or m.phase=='penalties') and m.notice or '',ended=m.ended,op=m.op.name,
  captain=captain,interactive=manualActive(m),userHome=m.userHome,attackDirection=m.direction,phase=m.phase,half=m.half,seq=m.seq,time=m.tick*Config.step,mode=m.mode,
  bench=(function()local rows={};for id,q in pairs(m.bench)do if not m.usedSubs[id] then rows[#rows+1]={id=id}end end;table.sort(rows,function(a,b)return a.id<b.id end);return rows end)(),stats={copy(m.stats[1]),copy(m.stats[2])},penalties=penalties,penWin=m.penWin,replayId=m.replayId,substitutions=m.substitutions}
end
return M
