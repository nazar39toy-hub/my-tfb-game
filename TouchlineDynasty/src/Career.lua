-- Touchline Dynasty career domain. All mutations run on the server's serialized queue.
-- Pure Lua modules are shared by the game and deterministic regression tests.
local W=require(script.Parent.World)
local T=require(script.Parent.Tournaments)
local P=require(script.Parent.Players)
local E=require(script.Parent.Economy)
local B=require(script.Parent.Market)
local K=require(script.Parent.EconomyConfig)
local Branding=require(script.Parent.Branding)
local Loans=require(script.Parent.Loans)
local C={VERSION=2}
C.formations={'4-3-3','4-4-2','3-5-2','4-2-3-1','5-3-2','4-1-4-1','3-4-3'}
C.styles={'possession','counter','press','lowblock','wings'}
local formations={['4-3-3']={4,3,3},['4-4-2']={4,4,2},['3-5-2']={3,5,2},['4-2-3-1']={4,5,1},['5-3-2']={5,3,2},['4-1-4-1']={4,5,1},['3-4-3']={3,4,3}}
local function finite(v)return type(v)=='number'and v==v and math.abs(v)<1e15 end
local function contains(t,v)for _,q in ipairs(t)do if q==v then return true end end;return false end
local function bounded(t,v,n)t[#t+1]=v;if#t>n then table.remove(t,1)end end
local function event(p,key,params)
 local e={key=key,params=params or{},date=p.date,season=p.season};bounded(p.news,e,K.newsLimit);return e
end
function C.copy(v)if type(v)~='table'then return v end;local o={};for k,x in pairs(v)do o[k]=C.copy(x)end;return o end
C.rng=W.rng
function C.roles(formation)
 local roles={'GK'};for g,n in ipairs(formations[formation]or formations['4-3-3'])do for _=1,n do roles[#roles+1]=({'DEF','MID','FWD'})[g]end end;return roles
end
C.player=P.new
C.value=E.value
C.effective=P.effective
function C.find(p,id)for i,q in ipairs(p.roster)do if q.id==id then return q,i end end end
function C.strength(p)
 local sum=0;local roles=C.roles(p.formation);for i,id in ipairs(p.lineup)do sum=sum+P.effective(p,C.find(p,id),roles[i])end;return sum/11
end
function C.transferImpact(p,q)
 local best=0
 for slot,role in ipairs(C.roles(p.formation))do local current=C.find(p,p.lineup[slot]);local gain=P.effective(p,q,role)-P.effective(p,current,role);best=math.max(best,gain/11)end
 return best
end
function C.sorted(p)return W.sorted(p.league)end
function C.schedule(ids)return W.schedule(ids or{1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16})end
function C.sim(rng,a,b,home,neutral)
 if home==false then local y,x=W.simScore(rng,b,a,neutral);return x,y end
 return W.simScore(rng,a,b,neutral)
end
function C.poisson(rng,lambda)
 local k,n=0,1;repeat k=k+1;n=n*rng()until n<=math.exp(-lambda)or k>10;return k-1
end
local function freshRows(p)
 p.league={};for _,club in ipairs(W.league(p.world,p.country,p.division))do
  p.league[#p.league+1]={id=club.id,name=club.name,rating=club.rating,pts=0,gf=0,ga=0,w=0,d=0,l=0,played=0}
 end
 p.schedule=W.schedule(W.league(p.world,p.country,p.division));p.round=1
end
function C.buildLeague(p)
 freshRows(p);p.tournament=T.new(p.world,p.clubId,p.season,p.seed+p.season*1009)
 p.date=p.tournament.date or 0;p.cupAlive=true;p.cupDone=false;p.cupStage=1
end
function C.market(p)return B.refresh(p,C)end
local function createSquad(p,rng,prefix,rating)
 p.roster={};p.lineup={};local roles=C.roles(p.formation)
 for i=1,20 do
  local pos=roles[i]or({'GK','DEF','MID','FWD'})[(i-12)%4+1]
  local q=P.new(rng,prefix..':'..i,rating+rng(-4,4),pos,p.country,p.season)
  q.acquiredAbs=-1000;q.currentSeason=p.season;p.roster[#p.roster+1]=q;if i<=11 then p.lineup[i]=q.id end
 end
 p.captain=p.lineup[6];p.setPieces={freeKick=p.lineup[9],penalty=p.lineup[10],corner=p.lineup[8]}
end
function C.new(seed)
 seed=math.max(1,math.floor(tonumber(seed)or 1))
 local world=W.new(seed);local club=W.club(world,W.START_CLUB)
 local p={version=2,featuresVersion=1,revision=1,seed=seed,world=world,clubId=club.id,club=club.name,country=club.country,division=club.division,season=1,date=0,
  scoutRegion=club.country,cash=K.initialCash,debt=0,reputation=0,formation='4-3-3',mentality='balanced',style='counter',difficulty='normal',chemistry=40,
  upgrades={training=1,academy=1,stadium=1,medical=1},staff={coach=1,scout=1,doctor=1},sponsor='stable',history={},news={},seasonHistory={},hallOfFame={},records={bestDivision=6,goals=0},
  trophies=0,wins=0,tutorial=true,academyYear=0,academy={},marketVersion=0,marketConsumed={},favorites={},completedMatches={},achievements={},goals={priority='league',claimed=false,startCash=K.initialCash,startYouth=0,startForfeits=0},
  manager={name='Manager',reputation=0,trophies=0,contractEnd=3,clubHistory={}},financeLedger=E.newLedger(),settings={locale='auto',textScale=1,reducedMotion=false,shake=false,colorblind=false,haptics=true,music=.4,sfx=.7,crowd=.4,bindings={pass='E',shoot='Space',through='Q',switch='R',tackle='F',sprint='LeftShift'}},
  cosmetics={tokens=0,owned={classic=true,clean=true},equipped={kit='classic',broadcast='clean'},passes={},receipts={},support=0},youthPromotions=0}
 createSquad(p,C.rng(seed+913),p.clubId..':original',club.rating+1)
 C.buildLeague(p);C.market(p);event(p,'event.welcome',{club=p.club,division=p.division});return p
end
local function ensureCosmetics(p)
 p.cosmetics=p.cosmetics or{};local c=p.cosmetics;c.tokens=c.tokens or 0;c.owned=c.owned or{classic=true,clean=true};c.equipped=c.equipped or{kit='classic',broadcast='clean'};c.passes=c.passes or{};c.receipts=c.receipts or{};c.support=c.support or 0
end
local function emergency(p,pos)
 local serial=(p.emergencySerial or 0)+1;p.emergencySerial=serial
 local q=P.new(C.rng(p.seed+p.season*331+serial),p.clubId..':emergency:'..p.season..':'..serial,math.max(34,40+(6-p.division)*4),pos,p.country,p.season)
 q.age=18;q.emergency=true;q.wage=K.emergencyWage;q.contractEnd=p.season;q.loan={ends=p.season,emergency=true,buyout=E.value(q)};q.acquiredAbs=(p.season-1)*K.seasonDays+p.date
 p.roster[#p.roster+1]=q;event(p,'event.emergency_registration',{name=q.name});return q
end
function C.repairLineup(p,optimize)
 local previous=C.copy(p.lineup)
 local available={};local keepers=0
 for _,q in ipairs(p.roster)do if P.available(q)then available[#available+1]=q;if q.pos=='GK'then keepers=keepers+1 end end end
 if keepers==0 and#p.roster<K.maxRoster then available[#available+1]=emergency(p,'GK')end
 while#available<11 and#p.roster<K.maxRoster do available[#available+1]=emergency(p,({'DEF','MID','FWD'})[#available%3+1])end
 local used={};local roles=C.roles(p.formation);local lineup={}
 local keeper=C.find(p,p.lineup[1]);if not keeper or keeper.pos~='GK' or not P.available(keeper) then keeper=nil;for _,q in ipairs(available)do if q.pos=='GK'then keeper=q;break end end end
 if optimize then keeper=nil;local score=-1;for _,q in ipairs(available)do if q.pos=='GK' and P.effective(p,q,'GK')>score then keeper=q;score=P.effective(p,q,'GK')end end end
 if keeper then lineup[1]=keeper.id;used[keeper.id]=true end
 for slot=2,11 do
  local old=not optimize and C.find(p,p.lineup[slot]);if old and P.available(old)and not used[old.id]and(slot~=1 or old.pos=='GK')then lineup[slot]=old.id;used[old.id]=true end
 end
 for slot=1,11 do
  if not lineup[slot]then
   local best,score
   for _,q in ipairs(available)do if not used[q.id]and(slot~=1 or q.pos=='GK')then local s=P.effective(p,q,roles[slot]);if not score or s>score then best=q;score=s end end end
   if best then lineup[slot]=best.id;used[best.id]=true end
  end
 end
 local complete=true;for slot=1,11 do if not lineup[slot]then complete=false end end
 if not complete then local valid=#previous==11;local seen={};for slot=1,11 do local q=C.find(p,previous[slot]);if not q or seen[previous[slot]]or(slot==1 and q.pos~='GK')then valid=false else seen[q.id]=true end end;if valid then p.lineup=previous;return false end end
 p.lineup=lineup
 return complete
end
function C.isPlayable(p)
 for i=1,11 do local q=C.find(p,p.lineup[i]);if not q or not P.available(q)or(i==1 and q.pos~='GK')then return false end end;return true
end
local function legacyNext(p)
 local l=p.legacy
 if p.round<=14 then
  for _,g in ipairs(l.schedule[p.round]or{})do
   if g[1]==1 or g[2]==1 then local idx=g[1]==1 and g[2]or g[1];local row=p.league[idx]
    return{name=row.name,rating=row.rating,index=idx,home=g[1]==1,kind='league',round=p.round,date=math.min(112,p.round*7),matchId='legacy:'..p.season..':league:'..p.round,seed=p.seed+p.round*717}
   end
  end
 elseif p.cupAlive and not p.cupDone then
  local peers=W.league(p.world,p.country,math.max(1,p.division-1));local other=peers[(p.cupStage*3)%#peers+1]
  return{name=other.name,id=other.id,opponentId=other.id,rating=other.rating,home=p.cupStage%2==1,kind='cup',knockout=true,round=p.cupStage,date=114+p.cupStage*2,matchId='legacy:'..p.season..':cup:'..p.cupStage,seed=p.seed+p.cupStage*917}
 end
 return nil,'SEASON_COMPLETE'
end
function C.next(p,kind)
 local op,err
 if p.legacy then op,err=legacyNext(p)else op,err=T.next(p.tournament,p.world,p.clubId)end
 -- A requested competition is only a check; it never bypasses the sporting calendar.
 if op and kind and kind~='next'and kind~='training'and kind~=op.kind then return nil,'NEXT_FIXTURE_REQUIRED' end
 return op,err
end
local function leagueFinish(p,op,x,y)
 local rows={};for _,row in ipairs(p.league)do rows[row.id or row.name]=row end
 local rng=C.rng(p.seed+p.season*100003+op.round*733)
 for _,g in ipairs(p.schedule[op.round])do
  local a,b=p.legacy and p.league[g[1]]or rows[g[1]],p.legacy and p.league[g[2]]or rows[g[2]]
  local userA=p.legacy and g[1]==1 or(not p.legacy and g[1]==p.clubId)
  local userB=p.legacy and g[2]==1 or(not p.legacy and g[2]==p.clubId)
  local gx,gy
  if userA then gx,gy=x,y elseif userB then gx,gy=y,x else gx,gy=W.simScore(rng,a.rating,b.rating)end
  W.record(a,b,gx,gy)
 end
 p.round=op.round+1
end
local function achievement(p,id,condition)
 if condition and not p.achievements[id]then p.achievements[id]={done=true,claimed=false};event(p,'event.achievement',{name=id})end
end
function C.recoveryNeeded(p)
 local op=C.next(p);if not op or p.restDate==p.date then return false end
 local recovery=math.max(0,op.date-p.date)*E.recoveryPerDay(p)
 for _,q in ipairs(p.roster)do if (q.injury or 0)>0 or q.fitness+recovery<95 then return true end end;return false
end
function C.prepare(p,op)
 local expected=C.next(p)
 if not expected or not op or expected.matchId~=op.matchId then return nil,'STALE_MATCH'end
 if p.prepared then if p.prepared.matchId==op.matchId then return 0,'ALREADY_PREPARED'end;return nil,'MATCH_ACTIVE'end
 if (p.manager.contractEnd or 0)<p.season then p.manager.contractEnd=p.season+2;event(p,'event.manager_renewed',{season=p.manager.contractEnd})end
 p.goals.startCash=p.goals.startCash or p.cash;p.goals.startYouth=p.goals.startYouth or p.youthPromotions;p.goals.startForfeits=p.goals.startForfeits or(p.forfeits or 0)
 local from=p.date;local costs=E.advance(p,expected.date)
 p.prepared={matchId=op.matchId,costs=costs,fromDate=from};return costs,'MATCH_PREPARED'
end
function C.finish(p,op,x,y,scorers,assists,penWin,options)
 options=options or{};local id=op and op.matchId
 if type(id)~='string'then return nil,'INVALID_MATCH'end
 if p.completedMatches[id]then return 0,'ALREADY_FINALIZED',C.copy(p.completedMatches[id])end
 local expected=C.next(p)
 if not expected or expected.matchId~=id then return nil,'STALE_MATCH'end
 if not finite(x)or not finite(y)or x<0 or y<0 or x%1~=0 or y%1~=0 or x>50 or y>50 then return nil,'INVALID_SCORE'end
 -- Canonical server-owned descriptor prevents mutated price/venue/opponent data.
 op=expected;local forfeit=options.forfeit==true
 if forfeit then x=0;y=3;scorers={};assists={};penWin=false end
 local prepared=p.prepared and p.prepared.matchId==id and p.prepared or nil
 local startDate=prepared and prepared.fromDate or p.date;local costs=(prepared and prepared.costs or 0)+E.advance(p,op.date)
 local cupResult
 if p.legacy then
  if op.kind=='league'then leagueFinish(p,op,x,y)else
   local won=x>y or(x==y and penWin==true)
   if x==y and type(penWin)~='boolean'then penWin=T.penalties(C.rng(op.seed+33),C.strength(p),op.rating);won=penWin end
   if won and p.cupStage>=3 then p.cupDone=true;cupResult={title=true,titleId='legacy_cup'}elseif won then p.cupStage=p.cupStage+1 else p.cupAlive=false end
  end
 else
  if op.kind=='league'then leagueFinish(p,op,x,y)end
  cupResult=T.finish(p.tournament,p.world,p.clubId,op,x,y,penWin)
  local nextDate=p.tournament.date or op.date;if nextDate>p.date then costs=costs+E.advance(p,nextDate)end
  local cup=p.tournament.cups['national_'..p.country];p.cupDone=cup and cup.winner~=nil or false;p.cupStage=cup and cup.round or 1
  if cup then p.cupAlive=contains(cup.field,p.clubId)end
 end
 if cupResult and type(cupResult.penWin)=='boolean'then penWin=cupResult.penWin end
 local won=x>y or(x==y and(cupResult and cupResult.penWin==true or penWin==true))
 local income,breakdown=E.matchIncome(p,op,x,y,forfeit)
 if not forfeit and won and op.kind~='friendly'then p.wins=p.wins+1;p.reputation=math.min(999,p.reputation+2);p.manager.reputation=p.reputation end
 if forfeit then p.reputation=math.max(0,p.reputation-2);p.forfeits=(p.forfeits or 0)+1 end
 local active={};for _,pid in ipairs(p.lineup)do active[pid]=true end
 if options.stats and options.stats.minutes then for _,q in ipairs(p.roster)do active[q.id]=(options.stats.minutes[q.id]or 0)>0 end end
 for _,q in ipairs(p.roster)do
  if not q.loanOut then P.develop(q,p.upgrades.training+p.staff.coach-1,active[q.id],forfeit,op.kind=='friendly')end
  if not forfeit then
   local fitness=options.stats and options.stats.fitness and options.stats.fitness[q.id];if finite(fitness)and fitness>=0 and fitness<=100 then local recovery=math.max(0,p.date-op.date)*E.recoveryPerDay(p);q.fitness=math.min(100,fitness+recovery) end
   local goals=math.max(0,math.floor((scorers or{})[q.id]or 0));local assistsN=math.max(0,math.floor((assists or{})[q.id]or 0))
   q.goals=q.goals+goals;q.assists=q.assists+assistsN;q.careerGoals=q.careerGoals+goals;q.careerAssists=q.careerAssists+assistsN
   if active[q.id]then q.morale=math.max(0,math.min(100,q.morale+(won and 2 or-1)))end
  end
  local stats=options.stats or{};q.injury=math.max(q.injury,(stats.injuries or{})[q.id]or 0);q.suspension=math.max(q.suspension,((stats.redCards or{})[q.id]or 0)>0 and 2 or 0)
 end
 for _,q in ipairs(p.academy)do if not q.loanOut then P.develop(q,p.upgrades.academy,true,forfeit,op.kind=='friendly')end end
 if cupResult and cupResult.title and not forfeit then
  p.trophies=p.trophies+1;p.manager.trophies=p.trophies;p.reputation=math.min(999,p.reputation+15)
  local prize=K.cupPrize*(op.kind=='international'and 4 or 1);E.credit(p,prize);income=income+prize;breakdown.prize=prize
  bounded(p.hallOfFame,{season=p.season,title=cupResult.titleId,club=p.clubId},80)
 end
 p.chemistry=math.min(100,p.chemistry+(forfeit and-3 or 1));p.records.goals=(p.records.goals or 0)+x
 local result={matchId=id,home=x,away=y,op=op.name,venueHome=op.home,neutral=op.neutral,income=income,costs=costs,net=income-costs,breakdown=breakdown,technical=options.technical==true,forfeit=forfeit,mode=options.mode or'simulation',penWin=penWin,penalties=x==y and op.knockout or false,stats=C.copy(options.stats or{}),date=p.date,elapsedDays=p.date-startDate}
 p.lastResult={key=op.knockout and x==y and(penWin and'event.match_pen_win'or'event.match_pen_loss')or'event.match_result',params={club=p.club,opponent=op.name,home=x,away=y},season=p.season,date=p.date}
 if op.derby then event(p,'event.derby',p.lastResult.params)end
 bounded(p.history,p.lastResult,K.historyLimit);event(p,p.lastResult.key,p.lastResult.params)
 p.prepared=nil;p.completedMatches[id]=C.copy(result);p.revision=p.revision+1
 achievement(p,'firstWin',p.wins>=1);achievement(p,'academy',p.youthPromotions>=2);achievement(p,'tenWins',p.wins>=10)
 C.repairLineup(p)
 return income,'MATCH_FINALIZED',result
end
local function moveClub(world,id,destination)
 local club=world.clubs[id];if club.division==destination then return end
 local origin=world.leagues[club.country][club.division];local target=world.leagues[club.country][destination]
 local ix;for i,v in ipairs(origin)do if v==id then ix=i end end
 local other=target[1];target[1]=id;origin[ix]=other;world.clubs[other].division=club.division;club.division=destination
 table.sort(origin);table.sort(target)
end
local function season(p)
 if C.next(p)then return false,'SEASON_NOT_COMPLETE'end
 local tableRows=C.sorted(p);local place=#tableRows
 for i,row in ipairs(tableRows)do if row.id==p.clubId or(p.legacy and i and row.name==p.club)then place=i end end
 local oldDivision=p.division;local prize=E.endSeason(p,place);E.advance(p,K.seasonDays)
 local technical=(p.forfeits or 0)-(p.goals.startForfeits or 0)
 local goal=p.goals.priority;local completed=technical<=2 and ((goal=='league' and place<=8)or(goal=='youth' and p.youthPromotions-(p.goals.startYouth or 0)>=2)or(goal=='finance' and technical==0 and p.debt==0 and p.cash>=(p.goals.startCash or p.cash)))
 p.boardLast={season=p.season,priority=goal,completed=completed,reward=completed and 20 or 0}
 if completed then p.cosmetics.tokens=p.cosmetics.tokens+20;event(p,'event.goal_complete',{season=p.season})end
 local rng=C.rng(p.seed+p.season*11939);local oldSeason=p.season
 if place==1 then p.trophies=p.trophies+1;p.manager.trophies=p.trophies;p.reputation=math.min(999,p.reputation+15)end
 bounded(p.seasonHistory,{season=p.season,club=p.clubId,division=p.division,place=place,prize=prize,cash=p.cash,debt=p.debt},K.seasonHistoryLimit)
 if p.legacy then
  local legacyDivision=p.legacy.division;if place<=2 then legacyDivision=math.max(1,legacyDivision-1)elseif place>=7 then legacyDivision=math.min(3,legacyDivision+1)end
  bounded(p.history,{key='event.legacy_completed',params={season=p.season,place=place},legacyTable=C.copy(p.league)},K.historyLimit)
  W.advanceSeason(p.world,nil,p.clubId);moveClub(p.world,p.clubId,math.max(2,math.min(6,legacyDivision*2)));p.legacy=nil
 else
  W.advanceSeason(p.world,{country=p.country,division=p.division,table=p.league},p.clubId)
 end
 p.season=p.season+1;p.world.season=p.season;p.division=W.club(p.world,p.clubId).division;p.date=0
 local kept={}
 for _,q in ipairs(p.roster)do
  local retired=P.endSeason(q,oldSeason,rng);if q.loanOut and q.loanOut.ends<=oldSeason then q.loanOut=nil;event(p,'event.loan_returned',{name=q.name})end
  if retired then
   event(p,'event.retired',{name=q.name});if q.careerGoals>=30 or q.careerAssists>=30 then bounded(p.hallOfFame,{name=q.name,id=q.id,goals=q.careerGoals,assists=q.careerAssists,retired=p.season},80)end
  elseif q.loan and(q.loan.ends or 0)<p.season then event(p,'event.loan_returned',{name=q.name})
  elseif q.contractEnd<p.season then event(p,'event.contract_expired',{name=q.name})
  else q.currentSeason=p.season;kept[#kept+1]=q;if q.retirementNotice then event(p,'event.retirement_warning',{name=q.name})end end
 end
 p.roster=kept
 local academy={};for _,q in ipairs(p.academy)do P.endSeason(q,oldSeason,rng);if q.loanOut and q.loanOut.ends<=oldSeason then q.loanOut=nil;event(p,'event.loan_returned',{name=q.name})end;if q.age<=21 then q.currentSeason=p.season;academy[#academy+1]=q else event(p,'event.academy_released',{name=q.name})end end;p.academy=academy
 p.completedMatches={};p.marketConsumed={};p.sold={};p.goals={priority=p.goals.priority,claimed=false,startCash=p.cash,startYouth=p.youthPromotions,startForfeits=p.forfeits or 0};p.restDate=nil;p.restructured=false
 C.repairLineup(p)
 local club=W.club(p.world,p.clubId);club.rating=math.floor(C.strength(p));club.cash=p.cash
 -- Manager appointments are decided before renewing an expired three-year contract.
 C.buildLeague(p);C.market(p)
 p.records.bestDivision=math.min(p.records.bestDivision,p.division)
 if p.division<oldDivision then achievement(p,'promotion',true);event(p,'event.promotion',{division=p.division})end
 p.jobOffers={}
 local clubList={};for _,c in pairs(p.world.clubs)do if p.season>(p.manager.contractEnd or 0)and c.id~=p.clubId and c.division>=math.max(1,p.division-1)and c.reputation<=40+p.reputation*.6 then clubList[#clubList+1]=c end end
 table.sort(clubList,function(a,b)return a.id<b.id end)
 for i=1,math.min(3,#clubList)do local c=clubList[((p.seed+p.season*13+i*17)%#clubList)+1];p.jobOffers[#p.jobOffers+1]={id=c.id,name=c.name,division=c.division,country=c.country,budget=c.cash,years=3,contractEnd=p.season+2,requiredReputation=math.max(0,math.floor((c.reputation-40)/.6))}end
 event(p,'event.season',{season=p.season,place=place,prize=prize});p.financeLedger=E.newLedger()
 return true,'SEASON_STARTED',{season=p.season,place=place,prize=prize}
end
local function settings(p,arg)
 local key,value=arg.key,arg.value
 if key=='locale'then if not contains({'auto','en','ru','uk','es','pt-br','pl','de','fr','tr','ja','ko','qps-ploc'},value)then return false,'INVALID_SETTINGS'end
 elseif key=='textScale'then if not finite(value)or value<.8 or value>1.5 then return false,'INVALID_SETTINGS'end
 elseif key=='music'or key=='sfx'or key=='crowd'then if not finite(value)or value<0 or value>1 then return false,'INVALID_SETTINGS'end
 elseif key=='reducedMotion'or key=='shake'or key=='colorblind'or key=='haptics'then if type(value)~='boolean'then return false,'INVALID_SETTINGS'end
 elseif key=='bindings'then
  if type(value)~='table'then return false,'INVALID_SETTINGS'end
  local clean=C.copy(p.settings.bindings)
  local allowed={Space=true,LeftShift=true,RightShift=true,LeftControl=true,RightControl=true}
  for ch=65,90 do allowed[string.char(ch)]=true end
  for action,k in pairs(value)do if clean[action]==nil or type(k)~='string'or not allowed[k]then return false,'INVALID_SETTINGS'end;clean[action]=k end
  value=clean
 else return false,'INVALID_SETTINGS'end
 p.settings[key]=value;return true,'SETTINGS_SAVED'
end
function C.compactClubs(p)
 local clubs={};for _,club in pairs(p.world.clubs)do if club.retainedSquad then clubs[#clubs+1]=club end end
 table.sort(clubs,function(a,b)if (a.retainedAt or 0)==(b.retainedAt or 0)then return a.id<b.id end;return(a.retainedAt or 0)>(b.retainedAt or 0)end)
 for index=K.retainedClubLimit+1,#clubs do
  local club=clubs[index];local total=0;local legends={}
  for _,q in ipairs(club.retainedSquad)do total=total+q.rating;legends[#legends+1]={id=q.id,name=q.name,goals=q.careerGoals or 0,assists=q.careerAssists or 0}end
  table.sort(legends,function(a,b)if a.goals==b.goals then return a.id<b.id end;return a.goals>b.goals end)
  while #legends>3 do table.remove(legends)end
  club.retainedSummary={season=club.retainedAt or 0,count=#club.retainedSquad,rating=math.floor(total/math.max(1,#club.retainedSquad)),legends=legends};club.retainedSquad=nil
 end
end
function C.action(p,action,arg)
 arg=arg or{};if type(arg)~='table'then return false,'INVALID_ARGUMENT'end
 if action=='loanOut'then local ok,code,params=Loans.out(p,C,arg.id,E);if ok then p.revision=p.revision+1 end;return ok,code,params end
 if action=='autoLineup'then if C.repairLineup(p,true) then p.revision=p.revision+1;return true,'LINEUP_UPDATED' end;return false,'INVALID_LINEUP'end
 local ok,code,params
 if action=='buy'then ok,code,params=B.buy(p,C,arg.id,false)
 elseif action=='loan'then ok,code,params=B.buy(p,C,arg.id,true)
 elseif action=='sell'then ok,code,params=B.sell(p,C,arg.id,arg.offerId)
 elseif action=='buyout'then ok,code,params=B.buyout(p,C,arg.id)
 elseif action=='scout'then ok,code,params=B.scout(p,arg.id)
 elseif action=='negotiate'then ok,code,params=B.negotiate(p,arg.id)
 elseif action=='favorite'then
  if not B.find(p,arg.id)then return false,'OFFER_UNAVAILABLE'end
  p.favorites[arg.id]=not p.favorites[arg.id];ok,code=true,'FAVORITE_UPDATED'
 elseif action=='swap'then
  local q=C.find(p,arg.id);local slot=arg.slot
  if not q or not finite(slot)or slot%1~=0 or slot<1 or slot>11 then return false,'INVALID_LINEUP'end
  if not P.available(q)then return false,'PLAYER_UNAVAILABLE'end
  if slot==1 and q.pos~='GK'then return false,'KEEPER_REQUIRED'end
  local old=p.lineup[slot]
  for i,id in ipairs(p.lineup)do if id==q.id then if i==1 and C.find(p,old).pos~='GK'then return false,'KEEPER_REQUIRED'end;p.lineup[i]=old;break end end
  p.lineup[slot]=q.id;p.chemistry=math.max(0,p.chemistry-1);ok,code=true,'LINEUP_UPDATED'
 elseif action=='formation'then
  if not formations[arg.value]then return false,'INVALID_TACTIC'end
  p.formation=arg.value;p.chemistry=math.max(0,p.chemistry-2);ok,code=true,'TACTIC_UPDATED'
 elseif action=='mentality'then
  if not contains({'attack','balanced','defend'},arg.value)then return false,'INVALID_TACTIC'end;p.mentality=arg.value;ok,code=true,'TACTIC_UPDATED'
 elseif action=='style'then
  if not contains(C.styles,arg.value)then return false,'INVALID_TACTIC'end;p.style=arg.value;ok,code=true,'TACTIC_UPDATED'
 elseif action=='tactic'then
  local presets={{formation='4-3-3',style='possession',mentality='balanced'},{formation='4-4-2',style='counter',mentality='balanced'},{formation='5-3-2',style='lowblock',mentality='defend'}}
  local n=arg.index;if not finite(n)or n%1~=0 or not presets[n]then return false,'INVALID_TACTIC'end
  for k,v in pairs(presets[n])do p[k]=v end;ok,code=true,'TACTIC_UPDATED'
 elseif action=='captain'or action=='setPiece'then
  if not C.find(p,arg.id)then return false,'PLAYER_NOT_FOUND'end
  if action=='captain'then p.captain=arg.id else if not contains({'freeKick','penalty','corner'},arg.key)then return false,'INVALID_ARGUMENT'end;p.setPieces[arg.key]=arg.id end
  ok,code=true,'TACTIC_UPDATED'
 elseif action=='difficulty'then
  if not K.difficulty[arg.value]then return false,'INVALID_SETTINGS'end;p.difficulty=arg.value;ok,code=true,'SETTINGS_SAVED'
 elseif action=='upgrade'then
  local n=p.upgrades[arg.key];if not n or n>=K.maxFacility then return false,'MAX_LEVEL'end
  ok,code=E.spend(p,E.upgradeCost(n));if ok then p.upgrades[arg.key]=n+1;code='FACILITY_UPGRADED'end
 elseif action=='staff'then
  local n=p.staff[arg.key];if not n or n>=K.maxStaff then return false,'MAX_LEVEL'end
  ok,code=E.spend(p,E.staffCost(n));if ok then p.staff[arg.key]=n+1;code='STAFF_HIRED'end
 elseif action=='sponsor'then
  if not contains({'stable','performance'},arg.value)then return false,'INVALID_ARGUMENT'end
  if p.sponsorChangedSeason==p.season then return false,'SPONSOR_LOCKED'end;p.sponsor=arg.value;p.sponsorChangedSeason=p.season;ok,code=true,'SPONSOR_CHANGED'
 elseif action=='rest'then
  if p.restDate==p.date then return false,'RECOVERY_ALREADY_USED'end
  if not C.recoveryNeeded(p)then return false,'RECOVERY_NOT_NEEDED'end
  ok,code=E.spend(p,K.medicalSessionCost);if ok then p.restDate=p.date;for _,q in ipairs(p.roster)do q.fitness=math.min(100,q.fitness+20);q.injury=math.max(0,q.injury-1)end;C.repairLineup(p);code='TEAM_RECOVERED'end
 elseif action=='academy'then
  if p.academyYear==p.season then return false,'ACADEMY_ALREADY_RECRUITED'end
  if#p.academy+3>K.maxAcademy then return false,'ACADEMY_FULL'end
  ok,code=E.spend(p,K.academyIntake);if ok then
   local rng=C.rng(p.seed+p.season*919);p.academyYear=p.season
   for i=1,3 do local q=P.new(rng,p.clubId..':academy:'..p.season..':'..i,35+p.upgrades.academy*2+rng(0,5),({'GK','DEF','MID','FWD'})[(p.season+i)%4+1],p.country,p.season)
    q.age=rng(15,17);q.potential=math.min(96,q.rating+rng(13,23));q.contractEnd=p.season+4;q.wage=100;q.acquiredAbs=(p.season-1)*K.seasonDays+p.date;p.academy[#p.academy+1]=q;event(p,'event.academy',{name=q.name})
   end;code='ACADEMY_RECRUITED'
  end
 elseif action=='promote'then
  if#p.roster>=K.maxRoster then return false,'ROSTER_FULL'end
  for i,q in ipairs(p.academy)do if q.id==arg.id then if q.loanOut then return false,'LOAN_UNAVAILABLE'end;q.wage=math.max(160,q.rating*5);p.roster[#p.roster+1]=q;table.remove(p.academy,i);p.youthPromotions=p.youthPromotions+1;achievement(p,'academy',p.youthPromotions>=2);ok,code,params=true,'YOUTH_PROMOTED',{name=q.name};break end end
  if not ok then return false,'PLAYER_NOT_FOUND'end
 elseif action=='releaseAcademy'then
  for i,q in ipairs(p.academy)do if q.id==arg.id then if q.loanOut then return false,'LOAN_UNAVAILABLE'end;table.remove(p.academy,i);ok,code=true,'YOUTH_RELEASED';break end end;if not ok then return false,'PLAYER_NOT_FOUND'end
 elseif action=='train'then
  local q=C.find(p,arg.id);if not q then for _,y in ipairs(p.academy)do if y.id==arg.id then q=y end end end
  if not q or not q.attributes[arg.focus]then return false,'INVALID_TRAINING'end
  q.focus=arg.focus;ok,code=true,'TRAINING_ASSIGNED'
 elseif action=='renew'then
  local q=C.find(p,arg.id);if not q or q.loan then return false,'PLAYER_NOT_FOUND'end
  if q.contractEnd>=p.season+3 then return false,'CONTRACT_NOT_DUE'end
  local bonus=math.floor(q.wage*6);ok,code=E.spend(p,bonus);if ok then q.wage=math.floor(q.wage*1.07);q.contractEnd=p.season+3;code='CONTRACT_RENEWED'end
 elseif action=='restructure'then
  if p.restructured then return false,'RESTRUCTURE_USED'end
  if p.cash>=100000 and p.debt<=0 then return false,'RESTRUCTURE_UNAVAILABLE'end
  p.cash=p.cash+K.restructureCredit;p.debt=p.debt+K.restructureCredit;p.restructured=true;ok,code=true,'FINANCE_RESTRUCTURED'
 elseif action=='scoutRegion'then
  if not W.country(arg.value)then return false,'INVALID_ARGUMENT'end
  if p.scoutRegionChangedSeason==p.season then return false,'SCOUT_REGION_LOCKED'end
  p.scoutRegion=arg.value;p.scoutRegionChangedSeason=p.season;ok,code=true,'SETTINGS_SAVED'
 elseif action=='goal'then
  if not contains({'league','youth','finance'},arg.value)or p.round>3 then return false,'GOAL_LOCKED'end;p.goals.priority=arg.value;ok,code=true,'GOAL_SELECTED'
 elseif action=='claim'then
  ensureCosmetics(p);local count=0
  for _,a in pairs(p.achievements)do if a.done and not a.claimed then a.claimed=true;p.cosmetics.tokens=p.cosmetics.tokens+30;count=count+1 end end
  if count==0 then return false,'NO_REWARD'end;ok,code,params=true,'REWARD_CLAIMED',{amount=count*30}
 elseif action=='settings'then ok,code,params=settings(p,arg)
 elseif action=='tutorial'then if type(arg.value)~='boolean'then return false,'INVALID_ARGUMENT'end;p.tutorial=arg.value;ok,code=true,'SETTINGS_SAVED'
 elseif action=='season'then ok,code,params=season(p)
 elseif action=='job'then
  if p.round~=1 or p.date>1 or p.legacy then return false,'JOB_WINDOW_CLOSED'end
  if p.season<=(p.manager.contractEnd or 0)then return false,'JOB_CONTRACT_ACTIVE'end
  local n=arg.index;if not finite(n)or n%1~=0 or not(p.jobOffers or{})[n]then return false,'JOB_UNAVAILABLE'end
  local offer=p.jobOffers[n];if p.reputation<offer.requiredReputation then return false,'REPUTATION_REQUIRED'end
  local oldClub=W.club(p.world,p.clubId);oldClub.cash=p.cash;oldClub.debt=p.debt;oldClub.rating=math.floor(C.strength(p));oldClub.retainedAt=p.season;oldClub.retainedSquad=C.copy(p.roster);oldClub.retainedUpgrades=C.copy(p.upgrades)
  bounded(p.manager.clubHistory,{club=p.clubId,season=p.season,trophies=p.trophies},40)
  local club=W.club(p.world,offer.id);p.clubId=club.id;p.club=club.name;p.country=club.country;p.division=club.division;p.cash=club.cash;p.debt=club.debt or 0
  p.scoutRegion=club.country;p.scoutRegionChangedSeason=p.season;p.upgrades=C.copy(club.retainedUpgrades or{training=club.infrastructure.training,academy=club.infrastructure.academy,stadium=club.infrastructure.stadium,medical=1});p.staff={coach=1,scout=1,doctor=1};p.academy={};p.financeLedger=E.newLedger();p.sponsor='stable';p.formation='4-3-3'
  if club.retainedSquad then p.roster=C.copy(club.retainedSquad);p.lineup={};C.repairLineup(p)else createSquad(p,C.rng(club.squadSeed+p.season),club.id..':generation:'..p.season,club.rating)end
  p.manager.contractEnd=p.season+2;p.jobOffers={};p.completedMatches={};p.marketConsumed={};C.compactClubs(p);C.buildLeague(p);C.market(p);ok,code,params=true,'JOB_ACCEPTED',{club=p.club}
 else return false,'ACTION_UNAVAILABLE'end
 if ok then p.revision=p.revision+1 end
 return ok,code,params
end
local function publicPlayer(p,q,market)
 local r=C.copy(q);local country=W.country(q.country);r.countryName=country and country.name or q.country;r.potentialRange=P.range(q,p.staff.scout);r.potential=nil;r.history=nil;r.currentSeason=nil;r.acquiredAbs=nil;r.paid=nil
 r.teamImpact=market and C.transferImpact(p,q)or nil;r.value=E.value(q);local offer=not market and B.quote(p,C.copy(q))or nil;r.sellOffer=offer and offer.amount or nil;r.sellOfferId=offer and offer.id or nil;r.sellOfferExpiry=offer and offer.expires or nil;r.buyerId=offer and offer.buyerId or nil
 if r.loan then r.loan.sellerId=q.loan.sellerId end
 return r
end
function C.public(p)
 local fields={'version','revision','club','clubId','country','division','season','date','round','cash','debt','reputation','formation','mentality','style','difficulty','chemistry','lineup','upgrades','staff','sponsor','history','news','seasonHistory','hallOfFame','records','trophies','wins','tutorial','achievements','goals','manager','settings','jobOffers','captain','setPieces','favorites','scoutRegion','challengeRewards','boardLast','lastResult','youthPromotions'}
 local out={};for _,key in ipairs(fields)do out[key]=C.copy(p[key])end
 out.roster={};for _,q in ipairs(p.roster)do out.roster[#out.roster+1]=publicPlayer(p,q,false)end
 out.market={};for _,q in ipairs(p.market)do out.market[#out.market+1]=publicPlayer(p,q,true)end
 out.academy={};for _,q in ipairs(p.academy)do out.academy[#out.academy+1]=publicPlayer(p,q,false)end
 out.restAvailable=C.recoveryNeeded(p);out.restPrice=K.medicalSessionCost;out.scoutRegions={};for _,country in ipairs(W.config.COUNTRIES)do out.scoutRegions[#out.scoutRegions+1]={id=country.id,name=country.name}end;out.facilityPrices={};for key,n in pairs(p.upgrades)do out.facilityPrices[key]=E.upgradeCost(n)end;out.staffPrices={};for key,n in pairs(p.staff)do out.staffPrices[key]=E.staffCost(n)end;out.facilityWeeklyIncrease=K.facilityUpkeep;out.staffWeeklyIncrease=K.staffUpkeep;out.squadUnavailable=not C.isPlayable(p);out.strength=math.floor(C.strength(p));out.table=C.sorted(p);out.next=C.next(p);if out.next then out.next.seed=nil end;out.finance=E.forecast(p);out.marketOpen=B.isOpen(p)
 out.cosmetics={design=Branding.effective(p),tokens=p.cosmetics.tokens,owned=C.copy(p.cosmetics.owned),equipped=C.copy(p.cosmetics.equipped),passes=C.copy(p.cosmetics.passes),support=p.cosmetics.support}
 if p.legacy then out.calendar={};out.legacy=true else local tp=T.public(p.tournament,p.clubId);out.calendar=tp.calendar;out.competitions=tp.cups;out.clubLabels={};for _,cup in pairs(tp.cups)do for _,id in ipairs(cup.participants)do local club=p.world.clubs[id];if club then out.clubLabels[id]=club.name end end end end
 return out
end
function C.migrate(old)
 if type(old)~='table'then return nil,'CORRUPT_PROFILE'end
 if old.version==C.VERSION then
  if old.featuresVersion~=1 then
   old.scoutRegion=old.scoutRegion or old.country
   if type(old.world)=='table'and type(old.world.clubs)=='table'then
    for _,club in pairs(old.world.clubs)do local country=W.country(club.country);if country then
     local styles={development='possession',pressing='press',possession='possession',compact='lowblock',wings='wings',physical='press',counter='counter',technical='possession'}
     club.style=club.style or styles[country.culture];club.formation=club.formation or(country.culture=='compact'and'5-3-2'or country.culture=='counter'and'4-4-2'or'4-3-3')
    end end
   end
   for _,list in ipairs({old.roster or {},old.academy or {}})do for _,q in ipairs(list)do
    if finite(q.rating)and finite(q.potential)then q.potential=math.max(q.rating,q.potential)end
    if q.pos=='GK'and type(q.keeping)=='table'and type(q.attributes)=='table'and finite(q.attributes.goalkeeping)and finite(q.keeping.handling)then
     local delta=q.attributes.goalkeeping-q.keeping.handling
     for _,key in ipairs({'handling','reflexes','positioning'})do if finite(q.keeping[key])then q.keeping[key]=math.max(1,math.min(99,q.keeping[key]+delta))end end
    end
   end end
   old.featuresVersion=1
  end
  return old
 end
 if old.version~=1 then return nil,'UNSUPPORTED_SCHEMA'end
 local p=C.new(old.seed or 1);p.season=old.season or 1;p.world.season=p.season
 local legacyKeys={'cash','club','reputation','formation','mentality','roster','lineup','upgrades','history','trophies','wins','tutorial','academyYear','lastResult'}
 for _,k in ipairs(legacyKeys)do if old[k]~=nil then p[k]=C.copy(old[k])end end
 p.upgrades.medical=p.upgrades.medical or 1;p.manager.reputation=p.reputation;p.manager.trophies=p.trophies
 p.legacy={version=1,division=old.division or 3,league=C.copy(old.league),schedule=C.copy(old.schedule or{}),startedRound=old.round or 1}
 p.league=C.copy(old.league or{});p.schedule=C.copy(old.schedule or{});p.round=old.round or 1;p.cupStage=old.cupStage or 1;p.cupAlive=old.cupAlive~=false;p.cupDone=old.cupDone==true
 for i,row in ipairs(p.league)do row.id='legacy:'..i end
 for _,q in ipairs(p.roster)do P.normalize(q,p.season);q.acquiredAbs=-1000;q.currentSeason=p.season end
 p.date=math.max(0,(p.round-1)*7);p.migration={from=1,to=2,legacySeason=p.season,policy='finish_legacy_then_expand',cashPreserved=p.cash}
 p.world.clubs[p.clubId].name=p.club
 p.pending=old.pending and C.next(p)or nil
 C.market(p);C.repairLineup(p);event(p,'event.migrated',{season=p.season});p.version=2
 return p
end
function C.validate(p)
 if type(p)~='table'or p.version~=2 then return false,'INVALID_SCHEMA'end
 for _,key in ipairs({'seed','season','date','round','cash','debt','reputation','trophies','wins','revision'})do if not finite(p[key])then return false,'INVALID_'..key end end
 if p.cash<0 or p.debt<0 or p.season<1 or p.season%1~=0 or p.date<0 or p.date>K.seasonDays then return false,'INVALID_FINANCES_OR_DATE'end
 for _,key in ipairs({'news','history','seasonHistory','hallOfFame','records','achievements','favorites','marketConsumed','setPieces','goals','league','schedule'})do if type(p[key])~='table'then return false,'INVALID_PROFILE_STRUCTURE'end end
 if p.legacy and(#p.league~=8 or#p.schedule~=14)then return false,'INVALID_LEGACY_CALENDAR'end
 if not p.legacy and(type(p.tournament)~='table'or type(p.tournament.calendar)~='table'or type(p.tournament.cups)~='table')then return false,'INVALID_TOURNAMENT'end
 if type(p.roster)~='table'or#p.roster<11 or#p.roster>K.maxRoster or type(p.lineup)~='table'or#p.lineup~=11 then return false,'INVALID_ROSTER'end
 if type(p.academy)~='table'or#p.academy>K.maxAcademy or type(p.market)~='table'then return false,'INVALID_ACADEMY_OR_MARKET'end
 local seen={}
 for _,list in ipairs({p.roster,p.academy})do for _,q in ipairs(list)do
  if type(q.id)~='string'or#q.id>160 or seen[q.id]then return false,'DUPLICATE_PLAYER'end;seen[q.id]=true
  if q.pos=='GK'then if type(q.keeping)~='table'then return false,'INVALID_KEEPING'end;for _,key in ipairs({'handling','reflexes','positioning'})do if not finite(q.keeping[key])or q.keeping[key]<1 or q.keeping[key]>99 then return false,'INVALID_KEEPING'end end end
  if type(q.name)~='string'or#q.name>200 or not finite(q.rating)or q.rating<1 or q.rating>99 or not finite(q.fitness)or q.fitness<0 or q.fitness>100 or not finite(q.wage)or q.wage<0 or not finite(q.age)or q.age<14 or not finite(q.contractEnd)then return false,'INVALID_PLAYER'end
  if not contains({'GK','DEF','MID','FWD'},q.pos)or(q.secondary~=nil and type(q.secondary)~='table')or(q.loan~=nil and type(q.loan)~='table')then return false,'INVALID_PLAYER_STATE'end
  for _,key in ipairs({'form','morale','potential','xp','goals','assists','grown','careerGoals','careerAssists','injury','suspension'})do if not finite(q[key])or q[key]<0 then return false,'INVALID_PLAYER_STATE'end end
  if q.form>100 or q.morale>100 or q.potential>99 or q.potential<q.rating then return false,'INVALID_PLAYER_STATE'end
  if type(q.attributes)~='table'then return false,'INVALID_ATTRIBUTES'end
  for _,attr in ipairs({'pace','shooting','passing','dribbling','defending','physical','goalkeeping'})do if not finite(q.attributes[attr])or q.attributes[attr]<1 or q.attributes[attr]>99 then return false,'INVALID_ATTRIBUTES'end end
 end end
 local lineup={};for _,id in ipairs(p.lineup)do if lineup[id]or not C.find(p,id)then return false,'INVALID_LINEUP'end;lineup[id]=true end
 if not C.find(p,p.lineup[1])or C.find(p,p.lineup[1]).pos~='GK'then return false,'KEEPER_REQUIRED'end
 if not formations[p.formation]or not contains(C.styles,p.style)or not K.difficulty[p.difficulty]then return false,'INVALID_TACTIC'end
 for _,map in ipairs({p.upgrades,p.staff})do if type(map)~='table'then return false,'INVALID_FACILITIES'end;for _,level in pairs(map)do if not finite(level)or level<1 or level>10 or level%1~=0 then return false,'INVALID_FACILITIES'end end end
 for _,key in ipairs({'training','academy','stadium','medical'})do if not finite(p.upgrades[key])then return false,'INVALID_FACILITIES'end end
 for _,key in ipairs({'coach','scout','doctor'})do if not finite(p.staff[key])or p.staff[key]>K.maxStaff then return false,'INVALID_FACILITIES'end end
 if p.prepared~=nil and(type(p.prepared)~='table'or type(p.prepared.matchId)~='string'or#p.prepared.matchId>160 or not finite(p.prepared.costs)or p.prepared.costs<0 or not finite(p.prepared.fromDate)or p.prepared.fromDate<0 or p.prepared.fromDate>p.date)then return false,'INVALID_PREPARED_MATCH'end
 if type(p.completedMatches)~='table'or type(p.settings)~='table'or type(p.financeLedger)~='table'or type(p.manager)~='table'then return false,'INVALID_PROFILE_STRUCTURE'end
 for _,key in ipairs({'music','sfx','crowd'})do local value=p.settings[key];if value~=nil and(not finite(value)or value<0 or value>1)then return false,'INVALID_SETTINGS'end end
 for _,key in ipairs({'reducedMotion','shake','colorblind','haptics'})do local value=p.settings[key];if value~=nil and type(value)~='boolean'then return false,'INVALID_SETTINGS'end end
 if p.settings.textScale~=nil and(not finite(p.settings.textScale)or p.settings.textScale<.8 or p.settings.textScale>1.5)then return false,'INVALID_SETTINGS'end
 if type(p.cosmetics)~='table'or type(p.cosmetics.owned)~='table'or type(p.cosmetics.equipped)~='table'or type(p.cosmetics.passes)~='table'or not finite(p.cosmetics.tokens)or p.cosmetics.tokens<0 or type(p.cosmetics.receipts)~='table'then return false,'INVALID_COSMETICS'end
 local ok,err=W.validate(p.world);if not ok then return false,err end
 return true
end
return C
