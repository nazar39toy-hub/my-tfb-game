-- Pure footballer model. OVR is a role summary; matches also consume individual attributes.
local P={}
local first={'Alex','Dani','Luka','Nico','Mark','Ilya','Tom','Lev','Erik','Oscar','Roman','Theo','Mateo','Jan','Kai','Arin'}
local last={'Vale','Moro','Silva','Novak','Costa','Bondar','Reyes','Muller','Bruno','Clark','Ross','Vega','Sol','Kova','Neri','Lind'}
local keys={'pace','shooting','passing','dribbling','defending','physical','goalkeeping'}
local weights={GK={.03,.02,.10,.04,.12,.15,.54},DEF={.13,.03,.12,.07,.38,.24,.03},MID={.12,.12,.30,.23,.12,.09,.02},FWD={.19,.36,.13,.22,.03,.06,.01}}
local function clamp(v,a,b)return math.max(a,math.min(b,v))end
function P.rating(q,role)
 local w=weights[role or q.pos] or weights.MID;local n=0
 for i,key in ipairs(keys)do n=n+(q.attributes[key] or q.rating or 50)*w[i]end
 return math.floor(n+.5)
end
function P.new(rng,id,rating,pos,country,season)
 local q={id=id,name=first[rng(1,#first)]..' '..last[rng(1,#last)],age=rng(18,30),pos=pos,country=country or 'asteria',secondary={},foot=rng()<.22 and 'left' or 'right',attributes={},fitness=100,form=65,morale=70,xp=0,goals=0,assists=0,appearances=0,careerGoals=0,careerAssists=0,traits={},injury=0,suspension=0,contractEnd=(season or 1)+rng(2,4),history={},grown=0}
 for i,key in ipairs(keys)do
  local bonus=(pos=='GK' and key=='goalkeeping') and 6 or (pos=='FWD' and key=='shooting')and 5 or (pos=='DEF' and key=='defending')and 5 or(pos=='MID'and key=='passing')and 5 or 0
  q.attributes[key]=clamp(rating+rng(-6,6)+bonus,20,96)
 end
 if pos~='GK'then q.attributes.goalkeeping=rng(12,26)end
 q.keeping={handling=q.attributes.goalkeeping,reflexes=clamp(q.attributes.goalkeeping+rng(-4,4),10,99),positioning=clamp(q.attributes.goalkeeping+rng(-3,3),10,99)}
 q.rating=P.rating(q);q.potential=clamp(q.rating+rng(5,19),q.rating,96)
 q.wage=math.max(120,math.floor(q.rating*7));q.traits[1]=({'calm','runner','leader','technician'})[rng(1,4)]
 if pos=='MID'then q.secondary={'FWD'}elseif pos=='DEF'then q.secondary={'MID'}elseif pos=='FWD'then q.secondary={'MID'}end
 return q
end
function P.normalize(q,season)
 q.pos=weights[q.pos]and q.pos or'MID';q.secondary=q.secondary or{};q.country=q.country or'asteria';q.foot=q.foot or'right'
 q.attributes=q.attributes or{};for _,k in ipairs(keys)do q.attributes[k]=clamp(tonumber(q.attributes[k])or q.rating or 50,1,99)end
 if q.pos~='GK'and q.attributes.goalkeeping==(q.rating or 50)then q.attributes.goalkeeping=20 end
 q.rating=P.rating(q);q.potential=clamp(tonumber(q.potential)or q.rating+8,q.rating,99)
 q.fitness=clamp(tonumber(q.fitness)or 100,0,100);q.form=clamp(tonumber(q.form)or 65,0,100);q.morale=clamp(tonumber(q.morale)or 70,0,100)
 q.age=math.floor(clamp(tonumber(q.age)or 23,14,70));q.wage=math.max(120,tonumber(q.wage)or q.rating*7)
 q.contractEnd=q.contractEnd or(season+2);q.goals=q.goals or 0;q.assists=q.assists or 0;q.xp=q.xp or 0
 q.careerGoals=q.careerGoals or q.goals;q.careerAssists=q.careerAssists or q.assists;q.appearances=q.appearances or 0
 q.injury=q.injury or 0;q.suspension=q.suspension or 0;q.history=q.history or{};q.traits=q.traits or{};q.grown=q.grown or 0
 q.keeping=q.keeping or{handling=q.attributes.goalkeeping,reflexes=q.attributes.goalkeeping,positioning=q.attributes.goalkeeping}
 return q
end
function P.available(q)return not q.loanOut and(q.injury or 0)<=0 and(q.suspension or 0)<=0 end
function P.effective(p,q,role)
 if not q or not P.available(q)then return 0 end
 local fit=.72+.28*q.fitness/100;local form=.94+.06*q.form/100;local morale=.96+.04*q.morale/100
 local pos=role==q.pos and 1 or .82
 for _,v in ipairs(q.secondary or{})do if v==role then pos=.94 end end
 local chemistry=1+math.min(.025,(p.chemistry or 0)*.00025)
 return P.rating(q,role)*fit*form*morale*pos*chemistry
end
function P.develop(q,training,active,forfeit,noGrowth)
 q.injury=math.max(0,(q.injury or 0)-1);q.suspension=math.max(0,(q.suspension or 0)-1)
 q.fitness=clamp(q.fitness+(active and-5 or 13),0,100)
 if forfeit then q.morale=clamp(q.morale-5,0,100);return end
 if noGrowth or not active then return end
 q.appearances=q.appearances+1;q.xp=q.xp+4+math.min(14,training)
 local plateau=q.pos=='GK'and 31 or q.pos=='DEF'and 28 or 26
 local cap=q.age<22 and 2 or q.age<=plateau and 1 or 0
 if q.xp>=100 and q.grown<cap and q.rating<q.potential then
  q.xp=q.xp-100;q.grown=q.grown+1
  local focus=q.focus
  if focus and q.attributes[focus]then q.attributes[focus]=clamp(q.attributes[focus]+3,1,99)end
  for _,key in ipairs(keys)do if key~='goalkeeping'or q.pos=='GK'then q.attributes[key]=clamp(q.attributes[key]+1,1,99)end end
  if q.pos=='GK' and q.keeping then for _,key in ipairs({'handling','reflexes','positioning'})do q.keeping[key]=clamp(q.keeping[key]+1+(q.focus=='goalkeeping'and 3 or 0),1,99)end end
  q.rating=P.rating(q);q.potential=math.max(q.potential,q.rating)
 end
 q.form=clamp(q.form+1,0,100)
end
function P.endSeason(q,season,rng)
 q.age=q.age+1;q.grown=0;q.xp=math.min(q.xp,99);q.fitness=100;q.injury=0;q.suspension=0
 q.history[#q.history+1]={season=season,age=q.age-1,rating=q.rating,club=q.loanOut and q.loanOut.clubId or nil,goals=q.goals,assists=q.assists,appearances=q.appearances};if#q.history>8 then table.remove(q.history,1)end
 q.goals=0;q.assists=0;q.appearances=0
 local decline=q.pos=='GK'and 35 or q.pos=='DEF'and 32 or 30
 if q.age>decline then
  q.attributes.pace=clamp(q.attributes.pace-2,15,99);q.attributes.physical=clamp(q.attributes.physical-1,15,99)
  if q.pos=='GK' and q.keeping then q.keeping.reflexes=clamp(q.keeping.reflexes-1,10,99);if q.age>decline+4 then q.keeping.handling=clamp(q.keeping.handling-1,10,99);q.keeping.positioning=clamp(q.keeping.positioning-1,10,99)end end
  if q.age>decline+4 then for _,key in ipairs(keys)do q.attributes[key]=clamp(q.attributes[key]-1,10,99)end end
 end
 q.rating=P.rating(q)
 local retirement=q.pos=='GK'and 42 or 38
 q.retirementNotice=q.age>=retirement-1
 return q.age>=retirement+3 or(q.age>=retirement and rng()<.45)
end
function P.range(q,scout)
 if q.scouted then local error=q.scoutAccuracy or 2;return{low=math.max(q.rating,q.potential-error),high=math.min(99,q.potential+error)}end
 local uncertainty=math.max(5,13-(scout or 1))
 -- The public centre uses age/OVR, never the exact hidden potential.
 local centre=math.min(96,q.rating+(q.age<=21 and 12 or 5))
 return{low=math.max(q.rating,centre-uncertainty),high=math.min(99,centre+uncertainty)}
end
return P
