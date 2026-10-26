local W=require(script.Parent.World)
local Config=require(script.Parent.WorldConfig)
local T={}
local function copy(v) if type(v)~='table' then return v end local o={} for k,x in pairs(v) do o[k]=copy(x) end return o end
local function contains(list,id) for _,v in ipairs(list) do if v==id then return true end end return false end
local function previousPower(n) local p=1; while p*2<=n do p=p*2 end return p end
-- Seeds are ordered strongest first. A 96-team cup has 32 seeded byes and 32 preliminary ties.
function T.newCup(ids,seed,kind,id)
 assert(#ids>=2,'A cup needs at least two real clubs')
 local seen={}; for _,club in ipairs(ids) do assert(not seen[club],'Duplicate cup participant'); seen[club]=true end
 return {id=id or 'cup',kind=kind or 'cup',seed=seed or 1,participants=copy(ids),field=copy(ids),round=1,rounds={},winner=nil}
end
local function buildRound(cup)
 if cup.rounds[cup.round] then return cup.rounds[cup.round] end
 local field=cup.field; local n=#field; local power=previousPower(n); local byes=n==power and 0 or 2*power-n
 local round={number=cup.round,byes={},games={}}
 for i=1,byes do round.byes[#round.byes+1]=field[i] end
 local playing=n-byes
 for i=1,playing/2 do
  local a,b=field[byes+i],field[n-i+1]
  if (i+cup.round)%2==0 then a,b=b,a end
  round.games[#round.games+1]={homeId=a,awayId=b,id=cup.id..':'..cup.round..':'..i}
 end
 cup.rounds[cup.round]=round; return round
end
-- Five kicks then sudden death. A kick is a football event, never a winner coin toss.
function T.penalties(rng,a,b)
 local scores={0,0}; local kicks={}; local attempts={0,0}
 local function kick(team)
  local skill=team==1 and a or b; local other=team==1 and b or a
  local p=math.max(.55,math.min(.88,.75+(skill-other)*.0025))
  local goal=rng()<p; attempts[team]=attempts[team]+1; if goal then scores[team]=scores[team]+1 end
  kicks[#kicks+1]={team=team,scored=goal}; return goal
 end
 for r=1,5 do
  kick(1); if scores[1]>scores[2]+(6-r) or scores[2]>scores[1]+(5-r) then return scores[1]>scores[2],{home=scores[1],away=scores[2],kicks=kicks} end
  kick(2); if scores[1]>scores[2]+(5-r) or scores[2]>scores[1]+(5-r) then return scores[1]>scores[2],{home=scores[1],away=scores[2],kicks=kicks} end
 end
 -- Paired sudden-death kicks continue until one team leads after equal attempts.
 -- An upper bound also protects tests from a constant RNG double.
 local pair=0
 while scores[1]==scores[2] and pair<200 do pair=pair+1; kick(1); kick(2) end
 if scores[1]==scores[2] then
  -- RNG test doubles can return a constant forever. Recorded accuracy decides one kick.
  local winner=a>=b and 1 or 2; scores[winner]=scores[winner]+1; kicks[#kicks+1]={team=winner,scored=true,accuracyTiebreak=true}
 end
 return scores[1]>scores[2],{home=scores[1],away=scores[2],kicks=kicks}
end
local function simulate(cup,game,world)
 local a,b=world.clubs[game.homeId],world.clubs[game.awayId]
 assert(a and b,'Cup contains unknown club')
 local rng=W.rng(cup.seed+W.hash(game.id))
 local neutral=#cup.field==2 or cup.kind=='supercup'
 local x,y=W.simScore(rng,a.rating,b.rating,neutral)
 -- Extra time: one third of a regulation match, with the same public score model.
 if x==y then local ex,ey=W.simScore(rng,a.rating,b.rating,neutral,1/3);x=x+ex;y=y+ey; game.extraTime=true end
 local penHome=false
 if x==y then penHome,game.penalties=T.penalties(rng,a.rating,b.rating) end
 game.homeScore=x; game.awayScore=y; game.winner=x>y and game.homeId or x<y and game.awayId or penHome and game.homeId or game.awayId
end
local function closeRound(cup,world)
 local round=buildRound(cup); local nextField=copy(round.byes)
 for _,game in ipairs(round.games) do assert(game.winner,'Unfinished cup tie'); nextField[#nextField+1]=game.winner end
 cup.field=nextField
 if #nextField==1 then
  cup.winner=nextField[1]
  local club=world.clubs[cup.winner]; club.records.cups=club.records.cups+1
  if cup.country then world.cupWinners[cup.country]=cup.winner
  elseif cup.kind=='international' then world.internationalWinners=world.internationalWinners or {}; world.internationalWinners[cup.id]=cup.winner end
 else cup.round=cup.round+1 end
end
function T.nextRound(cup) if cup.winner then return nil end return buildRound(cup) end
function T.advance(cup,world,overrides)
 if cup.winner then return false end
 for _,game in ipairs(buildRound(cup).games) do
  local override=overrides and overrides[game.id]
  if override then
   local x,y=override.home,override.away; assert(type(x)=='number' and type(y)=='number' and x>=0 and y>=0 and x%1==0 and y%1==0,'Invalid score')
   game.homeScore=x; game.awayScore=y
   local ph=override.penWin
   if x==y and type(ph)~='boolean' then ph,game.penalties=T.penalties(W.rng(cup.seed+W.hash(game.id)),world.clubs[game.homeId].rating,world.clubs[game.awayId].rating) end
   game.winner=x>y and game.homeId or x<y and game.awayId or ph and game.homeId or game.awayId
  elseif not game.winner then simulate(cup,game,world) end
 end
 closeRound(cup,world); return true
end
local function seeded(world,ids)
 local out=copy(ids)
 table.sort(out,function(a,b) local ac,bc=world.clubs[a],world.clubs[b]; if ac.reputation~=bc.reputation then return ac.reputation>bc.reputation end return a<b end)
 return out
end
local function descriptor(state,event,a,b,world,clubId)
 local home=a==clubId; local opponent=home and b or a; local c=world.clubs[opponent]
 local index
 for i,id in ipairs(state.leagueIds) do if id==opponent then index=i end end
 return {id=opponent,opponentId=opponent,name=c.name,rating=c.rating,style=c.style,formation=c.formation,derby=(world.clubs[clubId].rival==opponent or c.rival==clubId),home=home,kind=event.kind,round=event.round,date=event.date,
  index=index,tournamentId=event.tournament,knockout=event.kind~='league' and event.kind~='friendly',neutral=event.neutral or false,
  matchId=tostring(state.season)..':'..clubId..':'..event.date..':'..event.kind,seed=state.seed+event.date*104729+W.hash(clubId),colors=copy(c.colors)}
end
local prepare
prepare=function(state,world,clubId)
 state.next=nil
 while state.cursor<=#state.calendar do
  local event=state.calendar[state.cursor]
  if event.kind=='league' then
   for _,game in ipairs(state.leagueSchedule[event.round]) do if game[1]==clubId or game[2]==clubId then state.next=descriptor(state,event,game[1],game[2],world,clubId); return end end
   error('User missing from league calendar')
  elseif event.kind=='friendly' then
   state.next=descriptor(state,event,clubId,state.friendlyOpponent,world,clubId); return
  else
   local cup=state.cups[event.tournament]
   if cup and not cup.winner then
    assert(cup.round==event.round,'Cup calendar out of sync')
    local round=buildRound(cup); local userGame
    for _,game in ipairs(round.games) do
     if game.homeId==clubId or game.awayId==clubId then userGame=game else simulate(cup,game,world) end
    end
    if userGame then
     state.next=descriptor(state,event,userGame.homeId,userGame.awayId,world,clubId); state.next.gameId=userGame.id; return
    end
    closeRound(cup,world)
   end
  end
  state.date=event.date; state.cursor=state.cursor+1
 end
 state.done=true
end
function T.new(world,clubId,season,seed)
 local club=assert(world.clubs[clubId],'Unknown career club')
 local state={season=season or world.season,seed=seed or world.seed,date=0,cursor=1,calendar={},cups={},completed={},leagueIds={},done=false}
 for _,c in ipairs(W.league(world,club.country,club.division)) do state.leagueIds[#state.leagueIds+1]=c.id end
 state.leagueSchedule=W.schedule(state.leagueIds)
 local function event(date,kind,round,cup,neutral) state.calendar[#state.calendar+1]={date=date,kind=kind,round=round,tournament=cup,neutral=neutral} end
 local index=1; for i,id in ipairs(state.leagueIds) do if id==clubId then index=i end end
 state.friendlyOpponent=state.leagueIds[index%#state.leagueIds+1]; event(Config.DATES.friendly,'friendly',1)
 for round=1,30 do event(round*4,'league',round) end
 for ci,country in ipairs(Config.COUNTRIES) do
  local ids={}; for div=1,country.divisions do for _,c in ipairs(W.league(world,country.id,div)) do ids[#ids+1]=c.id end end
  local cupId='national_'..country.id; local cup=T.newCup(seeded(world,ids),state.seed+ci*997+state.season*101,'cup',cupId); cup.country=country.id; state.cups[cupId]=cup
  local dates=#ids==96 and Config.DATES.national96 or Config.DATES.national32
  for round,date in ipairs(dates) do event(date,'cup',round,cupId,round==#dates) end
  local super=world.supercups and world.supercups[country.id]
  if super and #super==2 and super[1]~=super[2] then local sid='super_'..country.id; state.cups[sid]=T.newCup(super,state.seed+ci*313+state.season*17,'supercup',sid); event(Config.DATES.supercup,'supercup',1,sid,true) end
 end
 for tier,ids in pairs(world.qualifications or {}) do
  if #ids>=2 then
   local cup=T.newCup(seeded(world,ids),state.seed+W.hash(tier)+state.season*37,'international',tier); state.cups[tier]=cup
   local rounds=0; local n=#ids; while n>1 do local power=previousPower(n); n=n==power and n/2 or power; rounds=rounds+1 end
   assert(rounds<=#Config.DATES.international,'International field exceeds calendar')
   for round=1,rounds do event(Config.DATES.international[round],'international',round,tier,round==rounds) end
  end
 end
 table.sort(state.calendar,function(a,b) if a.date~=b.date then return a.date<b.date end return (a.tournament or a.kind)<(b.tournament or b.kind) end)
 prepare(state,world,clubId); return state
end
function T.next(state,world,clubId)
 -- Cached next fixture is materialised only when a sporting date advances, never on viewing.
 if state.done then return nil,'SEASON_COMPLETE' end
 return copy(state.next)
end
function T.finish(state,world,clubId,op,x,y,penWin)
 if not state.next or not op or op.matchId~=state.next.matchId then return nil,'STALE_MATCH' end
 assert(type(x)=='number' and type(y)=='number' and x==x and y==y and x>=0 and y>=0 and x%1==0 and y%1==0,'Invalid fixture score')
 local event=state.calendar[state.cursor]; local result={title=false,date=event.date,matchId=op.matchId}
 if op.knockout then
  local cup=state.cups[event.tournament]; local round=buildRound(cup); local target
  for _,game in ipairs(round.games) do if game.id==op.gameId then target=game; break end end
  assert(target,'Missing knockout fixture')
  target.homeScore=op.home and x or y; target.awayScore=op.home and y or x
  if x==y and type(penWin)~='boolean' then
   penWin,result.penalties=T.penalties(W.rng(op.seed+83),world.clubs[clubId].rating,world.clubs[op.opponentId].rating)
  end
  target.winner=x>y and clubId or x<y and op.opponentId or penWin and clubId or op.opponentId
  result.won=target.winner==clubId; result.penWin=penWin
  closeRound(cup,world)
  if cup.winner==clubId then result.title=true; result.titleId=cup.id end
 end
 state.completed[#state.completed+1]={matchId=op.matchId,date=event.date,opponentId=op.opponentId,home=op.home,x=x,y=y,kind=op.kind}
 if #state.completed>64 then table.remove(state.completed,1) end
 state.date=event.date; state.cursor=state.cursor+1
 prepare(state,world,clubId); result.done=state.done; return result
end
function T.public(state,clubId)
 local result={date=state.date,done=state.done,calendar={},cups={}}
 local relevant={}
 for id,cup in pairs(state.cups) do
  if contains(cup.participants,clubId) then relevant[id]=true; result.cups[id]={id=id,kind=cup.kind,round=cup.round,winner=cup.winner,rounds=copy(cup.rounds),participants=copy(cup.participants)} end
 end
 for _,event in ipairs(state.calendar) do
  if not event.tournament or relevant[event.tournament] then
   local visible=copy(event); visible.completed=event.date<=state.date; result.calendar[#result.calendar+1]=visible
  end
 end
 return result
end
return T
