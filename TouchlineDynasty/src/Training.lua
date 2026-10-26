-- Isolated practice: no league calendar, wages, XP or club money mutations.
local A={challenges={passing={seed=5011,metric='completed',target=6},finishing={seed=5012,metric='onTarget',target=3}}}
function A.new(kind,C,M)
 if kind~='practice' and kind~='tutorial' and not A.challenges[kind] then return nil,'INVALID_TRAINING' end
 local rule=A.challenges[kind];local seed=rule and rule.seed or 5010
 local p=C.new(seed);p.difficulty='normal';p.style='possession'
 for _,q in ipairs(p.roster)do q.rating=70;q.fitness=100;for k in pairs(q.attributes)do q.attributes[k]=70 end end
 local m=M.new(p,{name='Touchline Academy',rating=50,home=true,kind='friendly',matchId='training:'..kind},C,seed)
 m.training={kind=kind,step=1,target=rule and rule.target or 0,metric=rule and rule.metric,startX=m.players[m.controlled].x,startY=m.players[m.controlled].y}
 m.duration=90;m.regulation=90;m.extraEnd=90;m.op.knockout=false
 return m
end
function A.observe(m)
 local t=m.training;if not t then return end
 if t.kind=='tutorial' then
  local q=m.players[m.controlled];local s=m.stats[1]
  if t.step==1 and ((q.x-t.startX)^2+(q.y-t.startY)^2)>9 then t.step=2 end
  if t.step==2 and s.completed>0 then t.step=3 end
  if t.step==3 and s.shots>0 then t.step=4;t.success=true;m.ended=true;m.phase='ended' end
 elseif t.metric and m.stats[1][t.metric]>=t.target then t.success=true;m.ended=true;m.phase='ended' end
end
function A.snapshot(m)
 local t=m.training;if not t then return nil end
 return {kind=t.kind,step=t.step,progress=t.metric and m.stats[1][t.metric] or t.step-1,target=t.target,remaining=math.max(0,math.ceil(m.duration-m.t)),success=t.success==true}
end
function A.finish(p,m,forfeit,M)
 local t=m.training;if not t then return nil end
 local reward=0
 if not forfeit and t.success then
  if t.kind=='tutorial' then p.tutorial=false
  elseif A.challenges[t.kind] then
   p.challengeRewards=p.challengeRewards or {};if not p.challengeRewards[t.kind] then p.challengeRewards[t.kind]=true;p.cosmetics.tokens=p.cosmetics.tokens+25;reward=25 end
  end
 end
 return {home=m.home,away=m.away,op=m.op.name,income=0,costs=0,net=0,stats=M.statistics(m),training=A.snapshot(m),cosmeticReward=reward,forfeit=forfeit}
end
return A
