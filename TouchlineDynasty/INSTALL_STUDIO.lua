-- Studio Edit mode only. Refuses occupied names; never deletes existing objects.
assert(not game:GetService('RunService'):IsRunning(), 'Stop Play first')
local ss=game:GetService('ServerScriptService');local rs=game:GetService('ReplicatedStorage');local sp=game:GetService('StarterPlayer'):WaitForChild('StarterPlayerScripts')
assert(not ss:FindFirstChild('TouchlineServer') and not rs:FindFirstChild('TouchlineShared') and not sp:FindFirstChild('TouchlineClient'), 'Touchline names occupied: use the supplied place or move the old project objects to a backup')
local server=Instance.new('Folder');server.Name='TouchlineServer'
local shared=Instance.new('Folder');shared.Name='TouchlineShared'
local function put(class,name,source,parent)local s=Instance.new(class);s.Name=name;s.Source=source;s.Parent=parent;return s end
put('ModuleScript','Audio',[========[local Config=require(script.Parent.AudioConfig)
local Audio={}
function Audio.new(service)
 local self=setmetatable({sounds={},settings={},lastSeq=-1,lastOwner=nil,lastPhase=nil},{__index=Audio})
 for key,item in pairs(Config)do
  if type(item.id)=='number'and item.id>0 and item.id%1==0 then
   local s=Instance.new('Sound');s.Name='Touchline_'..key;s.SoundId='rbxassetid://'..item.id;s.Looped=item.looped==true;s.Volume=0;s.Parent=service;self.sounds[key]=s
  end
 end
 return self
end
function Audio:settingsChanged(settings)
 self.settings=settings or {};for key,sound in pairs(self.sounds)do local item=Config[key];local volume=tonumber(self.settings[item.category])or 0;sound.Volume=math.max(0,math.min(1,volume))*item.volume end
end
function Audio:play(key)
 local sound=self.sounds[key];if sound then pcall(function()sound.TimePosition=0;sound:Play()end)end
end
function Audio:match(active)
 for _,key in ipairs({'crowd','music'})do local sound=self.sounds[key];if sound then pcall(function()if active then sound:Play()else sound:Stop()end end)end end
 if not active then self.lastSeq=-1;self.lastOwner=nil;self.lastPhase=nil end
end
function Audio:snapshot(data)
 if type(data)~='table'or type(data.seq)~='number'or data.seq<=self.lastSeq then return end;self.lastSeq=data.seq
 if data.phase~=self.lastPhase and (data.phase=='kickoff'or data.phase=='halftime'or data.phase=='ended'or data.phase=='restart')then self:play('whistle')end
 if self.lastOwner and not data.owner and data.phase=='play'then self:play('kick')end
 self.lastOwner=data.owner;self.lastPhase=data.phase
end
function Audio:destroy()
 for _,sound in pairs(self.sounds)do sound:Destroy()end;self.sounds={}
end
return Audio
]========],shared)
put('ModuleScript','AudioConfig',[========[-- Owner uploads supplied original WAV files, then assigns Roblox audio IDs here.
-- Zero means unavailable: silent fallback, never a fabricated ID.
return {
 kick={id=0,category='sfx',volume=.65},whistle={id=0,category='sfx',volume=.4},
 ui={id=0,category='sfx',volume=.25},crowd={id=0,category='crowd',volume=.4,looped=true},
 music={id=0,category='music',volume=.3,looped=true},
}
]========],shared)
put('ModuleScript','Branding',[========[-- Filtering adapter is injected; profile transforms below never yield or call services.
local Config=require(script.Parent.MonetizationConfig)
local B={shapes={shield=true,round=true,diamond=true,star=true}}
function B.filter(service,userId,raw)
 if type(raw)~='string'or raw:find('%c')then return nil,'NAME_INVALID'end
 raw=raw:gsub('^%s+',''):gsub('%s+$','');local ok,count=pcall(utf8.len,raw)
 if not ok or not count or count<2 or count>24 then return nil,'NAME_INVALID'end
 local success,text=pcall(function()return service:FilterStringAsync(raw,userId):GetNonChatStringForBroadcastAsync()end)
 if not success then return nil,'NAME_FILTER_UNAVAILABLE'end
 if type(text)~='string'or text==''or text:find('#',1,true)then return nil,'NAME_REJECTED'end
 return text
end
function B.rename(p,text,now)
 if p.lastRenameAt and now-p.lastRenameAt<60 then return false,'NAME_COOLDOWN'end
 for id,club in pairs(p.world.clubs)do if id~=p.clubId and club.name:lower()==text:lower()then return false,'NAME_IN_USE'end end
 p.club=text;p.world.clubs[p.clubId].name=text;p.lastRenameAt=now
 for _,row in ipairs(p.league)do if row.id==p.clubId or row.id=='legacy:1'then row.name=text end end
 return true,'SETTINGS_SAVED'
end
function B.premium(palette,shape,symbol)return palette>2 or symbol>2 or(shape~='shield'and shape~='round')end
function B.design(p,arg)
 local palette,shape,symbol=arg.palette,arg.shape,arg.symbol
 if type(palette)~='number'or palette%1~=0 or not Config.editorPalettes[palette]or not B.shapes[shape]or type(symbol)~='number'or symbol%1~=0 or symbol<1 or symbol>8 then return false,'INVALID_ARGUMENT'end
 if B.premium(palette,shape,symbol)and not(p.cosmetics.passes and p.cosmetics.passes.identity) then return false,'PASS_REQUIRED'end
 p.cosmetics.design={palette=palette,shape=shape,symbol=symbol};p.cosmetics.equipped.crest=nil;return true,'COSMETIC_APPLIED'
end
function B.effective(p)
 local design=p.cosmetics and p.cosmetics.design
 if type(design)~='table'or not Config.editorPalettes[design.palette]or not B.shapes[design.shape]or type(design.symbol)~='number'then return nil end
 if B.premium(design.palette,design.shape,design.symbol)and not(p.cosmetics.passes and p.cosmetics.passes.identity) then return nil end
 return {palette=design.palette,shape=design.shape,symbol=design.symbol,color=Config.editorPalettes[design.palette]}
end
return B
]========],server)
put('ModuleScript','Career',[========[-- Touchline Dynasty career domain. All mutations run on the server's serialized queue.
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
]========],server)
put('ModuleScript','CareerScreens',[========[-- Page models. All economic operations remain server intentions.
local UI=require(script.Parent.UI)
local Screens={}
local function array(value) return type(value)=='table' and value or {} end
local function display(value) return value==nil and '—' or tostring(value) end
function Screens.new(tr,send)
 local s={tr=tr,send=send,slot=1,compare={},shopFilter='all',prices={},priceBusy={},ui=nil,profile=nil,tutorial=false}
 setmetatable(s,{__index=Screens}); return s
end
function Screens:t(key,params) return self.tr:t('ui.'..key,params) end
function Screens:action(key,fn,primary,danger,enabled) return {label=self:t(key),callback=fn,primary=primary,danger=danger,enabled=enabled} end
function Screens:command(action,arg) return function() self.send(action,arg or {}) end end
function Screens:entry(title,body,actions,highlight) return {title=title,body=body,actions=actions or {},highlight=highlight} end
function Screens:confirm(title,body,action,arg)
 self.ui:modal(title,body,{self:action('confirm',self:command(action,arg),true),self:action('cancel',function() end)})
end
function Screens:player(q,p)
 local attrs={}; for _,key in ipairs({'pace','shooting','passing','dribbling','defending','physical','goalkeeping'}) do
  if q.attributes and q.attributes[key] then attrs[#attrs+1]=self.tr:t('attribute.'..key)..' '..q.attributes[key] end
 end
 if q.pos=='GK' and q.keeping then for _,key in ipairs({'handling','reflexes','positioning'})do attrs[#attrs+1]=self.tr:t('attribute.'..key)..' '..q.keeping[key]end end
 local traits={};for _,key in ipairs(q.traits or {})do traits[#traits+1]=self.tr:t('trait.'..key)end
 local range=q.potentialRange or {}; local lines={self.tr:t('player.details',{country=q.countryName or q.country,foot=self.tr:t('foot.'..(q.foot or 'right')),traits=table.concat(traits,', ')}),self.tr:t('player.formMorale',{form=q.form,morale=q.morale}),q.pos..' · '..display(q.age)..' · '..self:t('rating')..' '..display(q.rating),table.concat(attrs,' / '),self:t('potential')..' '..display(range.low)..'–'..display(range.high),self:t('fitness')..' '..display(q.fitness)..' / '..self:t('wages')..' '..self.tr:money(q.wage or 0),self:t('contract')..' '..display(q.contractEnd)}
 if q.loanOut then lines[#lines+1]=self.tr:t('loan.outStatus',{club=q.loanOut.clubName,season=q.loanOut.ends,played=q.loanOut.played})end
 local youth=false;for _,a in ipairs(p.academy or {})do if a.id==q.id then youth=true end end
 self.ui:modal(q.name,table.concat(lines,'\n\n'),{self:action(youth and 'promote' or 'assign',self:command(youth and 'promote' or 'swap',{slot=self.slot,id=q.id}),true),self:action('development',function()
  self.ui:modal(q.name,self:t('development'),{self:action('train',function()
   self.ui:modal(self:t('train'),q.name,{self:action('passing',self:command('train',{id=q.id,focus='passing'})),self:action('physical',self:command('train',{id=q.id,focus='physical'})),self:action('shooting',self:command('train',{id=q.id,focus='shooting'})),self:action('close',function()end)})
  end),self:action('scout',self:command('scout',{id=q.id})),self:action('loanOut',function()self:confirm(self:t('loanOut'),self.tr:t('loan.confirm',{name=q.name}),'loanOut',{id=q.id})end),self:action('close',function()self:player(q,p)end)})
 end),self:action('contract',function()
  self.ui:modal(q.name,self:t('contract'),{self:action('renew',self:command('renew',{id=q.id})),self:action('history',self:command('playerHistory',{id=q.id})),self:action('close',function()self:player(q,p)end)})
 end),self:action('close',function()end)})
end
function Screens:marketPlayer(q,p)
 local body=self.tr:t('market.impact',{gain=string.format('%.1f',q.teamImpact or 0)})..'\n'..self:t('transferCost')..' '..self.tr:money(q.price or 0)..' + '..self.tr:money(q.bonus or 0)..' + '..self.tr:money(q.agentFee or 0)..'\n'..self:t('annualCost')..' '..self.tr:money((q.totalCost or q.price or 0)+(q.wage or 0)*26)..'\n'..self:t('wages')..' '..self.tr:money(q.wage or 0)..'\n'..self:t('contract')..' '..display(q.contractEnd)
 if q.scoutReport then body=body..'\n'..self.tr:t('scout.report',{country=q.countryName or q.country,day=q.scoutReport.date,fee=self.tr:money(q.scoutReport.fee)})end
 self.ui:modal(q.name,body,{self:action('buy',self:command('buy',{id=q.id}),true),self:action('loan',self:command('loan',{id=q.id})),self:action('negotiate',self:command('negotiate',{id=q.id})),self:action('close',function() end)})
end
function Screens:players(p,filter,market)
 local rows={}; local source=market and p.market or p.roster
 local positions={'all','GK','DEF','MID','FWD'}; local pos=positions[filter.position or 1]; local query=(filter.query or ''):lower()
 for _,q in ipairs(array(source)) do
  local extra=filter.advanced or 'all';local accepted=extra=='all' or extra=='young' and q.age<=21 or extra=='strong' and q.rating>=60 or extra=='affordable' and (q.totalCost or 0)<=p.cash*.5 or extra=='wage' and q.wage<=(p.finance.wages or 10000)/11 or extra=='contract'and(q.contractEnd or p.season)-p.season<=2 or extra=='free' and q.free or extra=='favorite' and p.favorites and p.favorites[q.id]
  if accepted and (pos=='all' or q.pos==pos) and (query=='' or q.name:lower():find(query,1,true)) then rows[#rows+1]=q end
 end
 local field=({'name','rating','age','totalCost','wage','contractEnd'})[filter.sort or 1]
 table.sort(rows,function(a,b) local av,bv=a[field],b[field]; if av==bv then return a.id<b.id end; if field=='rating' then return (av or 0)>(bv or 0) end; return (av or (field=='name' and '' or 0))<(bv or (field=='name' and '' or 0)) end)
 return rows
end
function Screens:board(p)
 local veil=self.ui:modal(self:t('tactics'),'',{self:action('close',function() end)})
 local panel=veil:FindFirstChild('Panel'); local field=UI.frame(panel,'Board',Color3.fromRGB(35,105,66)); field.Position=UDim2.fromOffset(20,78); field.Size=UDim2.new(1,-40,1,-220); field.ZIndex=52
 local formation=p.formation or '4-3-3'; local counts={}; for n in formation:gmatch('%d+') do counts[#counts+1]=tonumber(n) end
 local slots={{x=.1,y=.5}}; for g,count in ipairs(counts) do for i=1,count do slots[#slots+1]={x=.22+g*.65/#counts,y=i/(count+1)} end end
 for i,id in ipairs(array(p.lineup)) do
  local q; for _,player in ipairs(array(p.roster)) do if player.id==id then q=player; break end end
  local b=UI.button(field,display(i),function() self.slot=i; veil:Destroy(); self.ui.modalFrame=nil; self.ui:open('squad') end,true)
  local slot=slots[i] or {x=.5,y=.5}; b.AnchorPoint=Vector2.new(.5,.5); b.Position=UDim2.fromScale(slot.x,slot.y); b.Size=UDim2.fromOffset(44,44); b.ZIndex=54
  local name=UI.label(field,q and q.name or '—',11,false); name.AnchorPoint=Vector2.new(.5,0); name.Position=UDim2.new(slot.x,0,slot.y,22); name.Size=UDim2.fromOffset(100,26); name.TextXAlignment=Enum.TextXAlignment.Center; name.ZIndex=54
 end
end
function Screens:upgrade(p,key,staff)
 local action=staff and 'staff' or 'upgrade';local prices=staff and p.staffPrices or p.facilityPrices
 local price=prices and prices[key]or 0;local upkeep=staff and p.staffWeeklyIncrease or p.facilityWeeklyIncrease
 self:confirm(self.tr:t((staff and 'staff.' or 'facility.')..key),self.tr:t('finance.confirmUpgrade',{price=self.tr:money(price),upkeep=self.tr:money(upkeep or 0)}),action,{key=key})
end
function Screens:items(page,p,filter,ui)
 self.ui=ui; self.profile=p
 if not p then return {self:entry(self:t('loading'),'',{self:action('retry',self:command('ready'))})} end
 local out={}; local function add(...) out[#out+1]=self:entry(...) end
 if page=='hub' then
  local op=p.next
  add(p.club,self:t('season')..' '..p.season..' · '..self:t('division')..' '..p.division..' · '..self.tr:date(p.season,p.date or 1),{self:action('squad',function() ui:open('squad') end),self:action('market',function() ui:open('market') end),self:action('save',self:command('save'))},true)
  if op then
   if p.squadUnavailable then add(self.tr:t('code.SQUAD_UNAVAILABLE'),'',{self:action('squad',function()ui:open('squad')end),self:action('rest',function()self:confirm(self:t('rest'),self.tr:t('training.recovery',{rate=self.tr:number((p.finance or {}).recoveryPerDay or 0,2),price=self.tr:money(p.restPrice or 0)}),'rest',{})end,false,false,p.restAvailable~=false),self:action('forfeit',function()self:confirm(self:t('forfeit'),self.tr:t('team.technicalForfeit'),'technicalForfeit',{})end,false,true)})end
   add((op.home==false and '↗ ' or '⌂ ')..(op.name or ''),self.tr:t('competition.'..(op.kind or 'league'))..' · '..self:t('rating')..' '..display(op.rating),{self:action('play',self:command('play'),true,false,not p.squadUnavailable),self:action('highlights',self:command('highlights'),false,false,not p.squadUnavailable),self:action('simulate',self:command('simulate'),false,false,not p.squadUnavailable)},true)
  else add(self:t('nextSeason'),self:t('financeForecast'),{self:action('nextSeason',self:command('season'),true)}) end
  add(self.tr:t('club.identity'),self.tr:t('club.identityHelp'),{self:action('rename',function()if self.onRename then self.onRename()end end),self:action('design',function()self:design(p)end)})
  local finance=p.finance or {}
  add(self:t('clubBudget')..' '..self.tr:money(p.cash or 0),self:t('net')..' '..self.tr:money(finance.net or 0)..' · '..self:t('wages')..' '..self.tr:money(finance.wages or 0),{self:action('finances',function() ui:open('finances') end)})
  if p.tutorial then add(self:t('tutorialStart'),self:t('trainingHelp'),{self:action('tutorialStart',function() if self.onTutorial then self.onTutorial() end end,true),self:action('tutorialSkip',self:command('tutorial',{value=false}))}) end
  for i=#array(p.news),math.max(1,#array(p.news)-2),-1 do local n=p.news[i]; add(self.tr:event(n),self.tr:date(n.season or p.season,n.date or p.date),{self:action('inbox',function() ui:open('inbox') end)}) end
 elseif page=='inbox' or page=='history' then
  local source=page=='inbox' and p.news or p.history
  for i=#array(source),1,-1 do local e=source[i]; add(self.tr:event(e),type(e)=='table' and self.tr:date(e.season or p.season,e.date or 1) or '') end
  if page=='history' then
   add(self:t('reputation')..' '..display(p.reputation),self:t('trophies')..' '..display(p.trophies)..' · '..self:t('wins')..' '..display(p.wins))
   for i,offer in ipairs(array(p.jobOffers)) do add(offer.name or offer.club or offer.clubId or self:t('job'),self:t('contract')..' '..display(offer.years or 2),{self:action('job',function() self:confirm(self:t('job'),self:t('confirmJob'),'job',{index=i}) end)}) end
  end
 elseif page=='calendar' then
  for i,e in ipairs(array(p.calendar)) do
   local date=e.date or e.day or i; local op=e.name or e.opponent or (e.op and e.op.name)
   add(self.tr:date(p.season,date)..' · '..self.tr:t('competition.'..(e.kind or 'league')),type(op)=='string' and op or display(e.round),{},date==(p.date or 0))
  end
 elseif page=='squad' then
  add(self.tr:t('team.auto'),self.tr:t('team.autoHelp'),{self:action('apply',self:command('autoLineup'),true)})
  add(self:t('selected')..' '..self:t('role')..' '..self.slot,self:t('formation')..' '..display(p.formation),{self:action('position',function() self.slot=self.slot%11+1; ui:refresh(false) end),self:action('tactics',function() ui:open('tactics') end)})
  for _,q in ipairs(self:players(p,filter,false)) do
   local active=false; for _,id in ipairs(array(p.lineup)) do if id==q.id then active=true end end
   add((active and '● ' or '')..q.name,q.pos..'  '..display(q.rating)..'  ·  '..self:t('age')..' '..display(q.age)..'  ·  '..self:t('fitness')..' '..display(q.fitness)..'  ·  '..self.tr:money(q.wage or 0),{
    self:action('view',function() self:player(q,p) end),self:action('assign',self:command('swap',{id=q.id,slot=self.slot}),true),self:action('renew',self:command('renew',{id=q.id})),self:action(q.loan and 'buyout' or 'sell',function() if q.loan then self.send('buyout',{id=q.id}) else self:confirm(self:t('sell'),self:t('confirmSell')..'\n'..q.name..' · '..self.tr:money(q.sellOffer or 0),'sell',{id=q.id,offerId=q.sellOfferId}) end end,false,true)
   })
  end
 elseif page=='tactics' then
  add(p.formation or '',self:t('selected')..' '..self:t('role')..' '..self.slot,{self:action('view',function() self:board(p) end,true),self:action('squad',function() ui:open('squad') end)})
  for index=1,3 do local preset=index;add(self.tr:t('team.preset',{index=index}),self.tr:t('team.presetHelp'),{self:action('apply',self:command('tactic',{index=preset}))})end
  local selected=p.lineup[self.slot];for _,q in ipairs(p.roster)do if q.id==selected then add(q.name,self.tr:t('team.roles'),{self:action('captain',self:command('captain',{id=selected})),self:action('freeKick',self:command('setPiece',{key='freeKick',id=selected})),self:action('penalty',self:command('setPiece',{key='penalty',id=selected})),self:action('corner',self:command('setPiece',{key='corner',id=selected}))})end end
  for _,formation in ipairs({'4-3-3','4-4-2','3-5-2','4-2-3-1','5-3-2','4-1-4-1','3-4-3'}) do add(formation,self:t('formations'),{self:action('apply',self:command('formation',{value=formation}),formation==p.formation)}) end
  for _,style in ipairs({'possession','counter','press','lowblock','wings'}) do add(self.tr:t('style.'..style),self.tr:t('style.'..style..'.description'),{self:action('apply',self:command('style',{value=style}),p.style==style)}) end
  for _,value in ipairs({'attack','balanced','defend'}) do add(self.tr:t('mentality.'..value),'',{self:action('apply',self:command('mentality',{value=value}),p.mentality==value)}) end
 elseif page=='academy' then
  add(self:t('academy'),self:t('potential'),{self:action('recruit',self:command('academy'),true)})
  for _,q in ipairs(array(p.academy)) do add(q.name,q.pos..' · '..display(q.age)..' · '..display(q.rating),{self:action('view',function() self:player(q,p) end),self:action('promote',self:command('promote',{id=q.id}),true)}) end
 elseif page=='training' then
  add(self:t('training'),self:t('trainingHelp'),{self:action('rest',function()self:confirm(self:t('rest'),self.tr:t('training.recovery',{rate=self.tr:number((p.finance or {}).recoveryPerDay or 0,2),price=self.tr:money(p.restPrice or 0)}),'rest',{})end,false,false,p.restAvailable~=false),self:action('squad',function() ui:open('squad') end)})
  for _,key in ipairs({'training','academy','medical'}) do add(self.tr:t('facility.'..key)..' '..display((p.upgrades or {})[key]),self:t('upkeep'),{self:action('upgrade',function()self:upgrade(p,key,false)end)}) end
  for _,key in ipairs({'coach','scout','doctor'}) do add(self.tr:t('staff.'..key)..' '..display((p.staff or {})[key]),self:t('upkeep'),{self:action('staff',function()self:upgrade(p,key,true)end)}) end
 elseif page=='table' then
  for i,t in ipairs(array(p.table)) do add(display(i)..'  '..(t.name or t.id or ''),self:t('played')..' '..display(t.played)..' · '..self:t('points')..' '..display(t.pts)..' · '..display(t.gf)..':'..display(t.ga),{},t.id==p.clubId or t.name==p.club) end
 elseif page=='cup' then
  add(self:t('cup'),self:t('qualificationRules'))
  for _,e in ipairs(array(p.calendar)) do if e.kind~='league' then add(self.tr:date(p.season,e.date or e.day),self.tr:t('competition.'..(e.kind or 'cup'))..' · '..display(e.name or e.round)) end end
  local ids={};for id in pairs(p.competitions or {})do ids[#ids+1]=id end;table.sort(ids)
  local function club(id)return (p.clubLabels or {})[id]or id end
  for _,id in ipairs(ids)do local cup=p.competitions[id];add(self.tr:t('competition.'..cup.kind),self.tr:t('bracket.round',{round=cup.round})..(cup.winner and ' · '..self.tr:t('bracket.winner',{club=club(cup.winner)})or ''))
   for _,round in ipairs(cup.rounds or {})do
    for _,team in ipairs(round.byes or {})do add(club(team),self.tr:t('bracket.bye',{round=round.number}))end
    for _,game in ipairs(round.games or {})do add(club(game.homeId)..' — '..club(game.awayId),self.tr:t('bracket.round',{round=round.number})..' · '..display(game.homeScore)..' : '..display(game.awayScore),{},game.homeId==p.clubId or game.awayId==p.clubId)end
   end
  end
 elseif page=='market' or page=='scout' then
  if page=='scout'then for _,region in ipairs(p.scoutRegions or {})do local id=region.id;add(region.name,self.tr:t('scout.specialism'),{self:action('apply',self:command('scoutRegion',{value=id}),p.scoutRegion==id)})end end
  local presets={'all','young','strong','affordable','wage','contract','free','favorite'}
  add(self.tr:t('market.filter.'..(filter.advanced or 'all')),self.tr:t('market.filterHelp'),{self:action('filter',function()local n=1;for i,key in ipairs(presets)do if key==filter.advanced then n=i%#presets+1 end end;filter.advanced=presets[n];ui:refresh(false)end)})
  if #self.compare>0 then
   local names={}; for _,q in ipairs(self.compare) do names[#names+1]=q.name..' · '..q.pos..' '..q.rating..' · '..self.tr:money(q.totalCost or q.price or 0) end
   add(self:t('compare'),table.concat(names,'\n'),{self:action('close',function() self.compare={}; ui:refresh(false) end)})
  end
  for _,q in ipairs(self:players(p,filter,true)) do
   add(q.name..(q.free and ' · '..self:t('freeAgent') or ''),q.pos..' '..display(q.rating)..' · '..self:t('age')..' '..display(q.age)..' · '..self.tr:money(q.totalCost or q.price or 0)..' · '..self:t('wage')..' '..self.tr:money(q.wage or 0),{
    self:action('view',function() self:marketPlayer(q,p) end),self:action('scoutPlayer',self:command('scout',{id=q.id})),self:action('compare',function() if #self.compare>=3 then table.remove(self.compare,1) end; for _,v in ipairs(self.compare) do if v.id==q.id then return end end; self.compare[#self.compare+1]=q; ui:refresh(false) end),self:action('favorite',self:command('favorite',{id=q.id}))
   })
  end
 elseif page=='stadium' then
  add(self:t('stadium')..' '..display((p.upgrades or {}).stadium),self:t('upkeep'),{self:action('upgrade',function()self:upgrade(p,'stadium',false)end,true),self:action('inventory',function() ui:open('inventory') end)})
 elseif page=='finances' then
  local f=p.finance or {}; add(self:t('clubBudget'),self.tr:money(p.cash or 0)..' · '..self:t('debt')..' '..self.tr:money(p.debt or 0))
  add(self:t('financeForecast'),self:t('income')..' '..self.tr:money(f.projectedIncome or 0)..'\n'..self:t('expenses')..' '..self.tr:money(f.projectedExpenses or 0)..' · '..self:t('net')..' '..self.tr:money(f.net or 0))
  add(self.tr:t('finance.broadcast'),self.tr:money((f.ledger or {}).broadcast or 0))
  for _,value in ipairs({'stable','performance'}) do add(self:t('sponsor')..' · '..self:t(value),self.tr:t('sponsor.'..value..'.description'),{self:action('apply',self:command('sponsor',{value=value}),p.sponsor==value)}) end
 elseif page=='goals' then
  if p.boardLast then add(self.tr:t(p.boardLast.completed and 'board.reward' or 'board.missed'),self.tr:date(p.boardLast.season,180))end
  for _,mode in ipairs({'manual','highlights','simulate'})do add(self.tr:t('records.title')..' · '..self.tr:t(mode=='simulate' and 'ui.modeSimulate' or mode=='highlights' and 'ui.modeHighlights' or 'ui.modeManual'),self.tr:t('records.rules'),{self:action('view',self:command('records',{mode=mode,difficulty=p.difficulty}))})end
  for _,kind in ipairs({'passing','finishing'})do add(self.tr:t('training.'..kind),self.tr:t('training.fixed'),{self:action('play',self:command('practice',{kind=kind}),true)})end
  for _,value in ipairs({'league','youth','finance'}) do add(self:t('goalsPriority')..' · '..self:t(value),self.tr:t('goal.'..value..'.description'),{self:action('apply',self:command('goal',{value=value}),(p.goals or {}).priority==value)}) end
  add(self:t('achievements'),self:t('tokens')..' '..display(p.cosmetics and p.cosmetics.tokens or 0),{self:action('claim',self:command('claim'),true)})
  for key,value in pairs(p.achievements or {}) do add(self.tr:t('achievement.'..tostring(key)),self.tr:t(value.claimed and 'goal.claimed' or 'goal.unclaimed')) end
 elseif page=='shop' or page=='inventory' then
  local shop=p.shop or {}; local catalog=shop.catalog or {}; add(self:t('tokens')..' '..display(shop.tokens or p.cosmetics and p.cosmetics.tokens or 0),self:t('cosmeticOnly'),{
   self:action('all',function() self.shopFilter='all'; ui:refresh(false) end),self:action('appearance',function() self.shopFilter='item'; ui:refresh(false) end),self:action('passes',function() self.shopFilter='pass'; ui:refresh(false) end),self:action('restorePurchases',self:command('refreshPasses'))
  },true)
  for _,item in ipairs(array(catalog)) do if (page~='inventory' or item.owned) and (self.shopFilter=='all' or self.shopFilter==item.kind) then
   local price=item.kind=='item' and (display(item.tokenCost or 0)..' '..self:t('tokens')) or self.prices[item.id] and ('R$ '..self.prices[item.id]) or self:t(item.enabled and 'priceLoading' or 'purchasesDisabled')
   add(self.tr:t(item.nameKey or 'shop.'..item.id),self.tr:t(item.descriptionKey or 'shop.'..item.id..'.description')..' · '..price..(item.pass and ' · '..self.tr:t('shop.requires',{pass=self.tr:t('shop.'..item.pass)})or ''),{
    self:action('view',function() self:preview(item) end),self:action(item.owned and 'apply' or 'buy',self:command(item.owned and 'cosmeticEquip' or item.kind=='item' and 'cosmeticBuy' or 'purchase',{id=item.id}),true,false,item.owned or item.enabled and (item.kind=='item' or self.prices[item.id]~=nil))
   },item.equipped)
  end end
 elseif page=='settings' then
  for _,value in ipairs({'easy','normal','hard'}) do add(self:t('difficulty'),self.tr:t('difficulty.'..value),{self:action('apply',self:command('difficulty',{value=value}),p.difficulty==value)}) end
  local settings=p.settings or {}; local languages={'auto','en','uk','ru','es','pt-br','pl','de','fr','tr','ja','ko','qps-ploc'}
  add(self:t('language'),display(settings.locale or 'auto'),{self:action('language',function() local i=1; for n,v in ipairs(languages) do if v==settings.locale then i=n%#languages+1 end end; self.send('settings',{key='locale',value=languages[i]}) end)})
  add(self:t('textScale'),display(settings.textScale or 1),{self:action('apply',self:command('settings',{key='textScale',value=(settings.textScale or 1)>=1.3 and 1 or math.min(1.35,(settings.textScale or 1)+.1)}))})
  for _,key in ipairs({'reducedMotion','shake','colorblind','haptics'}) do add(self:t(key),self:t(settings[key] and 'on' or 'off'),{self:action('apply',self:command('settings',{key=key,value=not settings[key]}))}) end
  for _,key in ipairs({'music','sfx','crowd'}) do add(self:t(key),display(settings[key] or 0),{self:action('apply',self:command('settings',{key=key,value=(settings[key] or 0)>=1 and 0 or math.min(1,(settings[key] or 0)+.25)}))}) end
  for _,action in ipairs({'pass','shoot','through','switch','tackle','sprint'}) do
   add(self:t('remap')..' · '..self:t(action),display((settings.bindings or {})[action]),{self:action('remap',function() if self.onRemap then self.onRemap(action) end end)})
  end
 elseif page=='help' then
  add(self.tr:t('training.practice'),self.tr:t('training.safe'),{self:action('play',self:command('practice',{kind='practice'}),true)})
  add(self:t('controls'),self:t('trainingHelp'),{self:action('tutorialStart',function() if self.onTutorial then self.onTutorial() end end,true)})
  add(self:t('difficulty'),self:t('difficultyHelp'))
  add(self:t('save'),self:t('saveHelp'),{self:action('save',self:command('save'))})
 end
 if #out==0 then add(self:t('empty'),self:t('none')) end
 return out
end
function Screens:design(p,state)
 state=state or {palette=(p.cosmetics.design or {}).palette or 1,shape=(p.cosmetics.design or {}).shape or 'shield',symbol=(p.cosmetics.design or {}).symbol or 1}
 local premium=p.cosmetics.passes and p.cosmetics.passes.identity;local shapes=premium and {'shield','round','diamond','star'}or{'shield','round'}
 self.ui:modal(self.tr:t('club.identity'),self.tr:t('club.designHelp',{palette=state.palette,shape=self.tr:t('crest.'..state.shape),symbol=state.symbol}),{
 self:action('palette',function()state.palette=state.palette%(premium and 8 or 2)+1;self:design(p,state)end),
 self:action('shape',function()local n=1;for i,key in ipairs(shapes)do if key==state.shape then n=i%#shapes+1 end end;state.shape=shapes[n];self:design(p,state)end),
 self:action('symbol',function()state.symbol=state.symbol%(premium and 8 or 2)+1;self:design(p,state)end),
 self:action('apply',function()self:confirm(self.tr:t('club.identity'),self.tr:t('club.designHelp',{palette=state.palette,shape=self.tr:t('crest.'..state.shape),symbol=state.symbol}),'identityDesign',state)end,true)})
end
function Screens:preview(item)
 local veil=self.ui:modal(self.tr:t(item.nameKey or 'shop.'..item.id),self.tr:t(item.descriptionKey or 'shop.'..item.id..'.description'),{
  self:action(item.owned and 'apply' or 'buy',self:command(item.owned and 'cosmeticEquip' or item.kind=='item' and 'cosmeticBuy' or 'purchase',{id=item.id}),true,false,item.owned or item.enabled and (item.kind=='item' or self.prices[item.id]~=nil)),self:action('close',function() end)
 })
 local panel=veil:FindFirstChild('Panel'); local swatch=UI.round(UI.frame(panel,'Preview',item.id=='sunset' and Color3.fromRGB(249,150,98) or item.id=='night' and Color3.fromRGB(8,17,38) or UI.colors.lime)); swatch.Position=UDim2.new(.5,-36,1,-204); swatch.Size=UDim2.fromOffset(72,64); swatch.ZIndex=54
 local crest=UI.label(swatch,'TD',24,true); crest.Size=UDim2.fromScale(1,1); crest.TextXAlignment=Enum.TextXAlignment.Center; crest.TextColor3=UI.colors.bg; crest.ZIndex=55
end
return Screens
]========],shared)
put('LocalScript','TouchlineClient',[========[local Players=game:GetService('Players')
local RS=game:GetService('ReplicatedStorage')
local Run=game:GetService('RunService')
local shared=RS:WaitForChild('TouchlineShared')
local L=require(shared.Localization)
local UI=require(shared.UI)
local Screens=require(shared.CareerScreens)
local View=require(shared.MatchView)
local Input=require(shared.Input)
local Results=require(shared.Results)
local Audio=require(shared.Audio)
local player=Players.LocalPlayer
task.spawn(function()pcall(function()local module=player:WaitForChild('PlayerScripts'):WaitForChild('PlayerModule');require(module):GetControls():Disable()end)end)
local camera=workspace.CurrentCamera
if not camera then camera=Instance.new('Camera');camera.Parent=workspace;workspace.CurrentCamera=camera end
camera.CameraType=Enum.CameraType.Scriptable;camera.CFrame=CFrame.new(0,40,50)
local net=RS:WaitForChild('TouchlineNet')
local command=net:WaitForChild('Command')
local event=net:WaitForChild('Event')
local tr=L.new({robloxLocale=player.LocaleId})
local profile,revision=nil,0
local audio=Audio.new(game:GetService('SoundService'))
local pending,requestCounter=nil,0
local function send(action,arg)
 local interactive=action=='input' or action=='control' or action=='ready'
 if not interactive then if pending then return end;audio:play('ui');requestCounter=requestCounter+1;local id=requestCounter;pending=id;task.delay(8,function()if pending==id then pending=nil;command:FireServer('ready',{})end end)end
 command:FireServer(action,arg or {})
end
local screens=Screens.new(tr,send)
local ui=UI.new(player,tr,{items=function(...) return screens:items(...) end})
screens.ui=ui
local view=View.new(ui.gui,tr,send)
local input=Input.new(ui.gui,view,tr,send)
view.onForfeit=function()
 input:setBlocked(true)
 ui:modal(tr:t('ui.forfeit'),tr:t('ui.confirmForfeit'),{{label=tr:t('ui.confirm'),callback=function() send('forfeit');input:setBlocked(false) end},{label=tr:t('ui.cancel'),callback=function() input:setBlocked(false) end}})
end
local function choose(title,items,onChoose,index)
 index=index or 1;local actions={}
 for n=index,math.min(#items,index+1)do local item=items[n];actions[#actions+1]={label=item.name,callback=function()onChoose(item)end}end
 if index+2<=#items then actions[#actions+1]={label=tr:t('ui.continue'),callback=function()choose(title,items,onChoose,index+2)end}end
 actions[#actions+1]={label=tr:t('ui.cancel'),callback=function()input:setBlocked(false)end}
 ui:modal(title,'',actions)
end
view.onTactics=function()
 input:setBlocked(true);send('control',{action='teamTalk'})
 ui:modal(tr:t('ui.tactics'),tr:t('training.pause'),{
 {label=tr:t('ui.style'),callback=function()local items={};for _,id in ipairs({'possession','counter','press','lowblock','wings'})do items[#items+1]={name=tr:t('style.'..id),id=id}end;choose(tr:t('ui.style'),items,function(item)send('control',{action='style',value=item.id});send('control',{action='continue'});input:setBlocked(false)end)end},
 {label=tr:t('ui.substitute'),callback=function()
  local active,items={},{};for _,q in ipairs(view.latest and view.latest.players or {})do if q.team==1 then active[q.id]=true;if q.active then items[#items+1]={id=q.id,name=tostring(q.number)..' · '..q.id}end end end
  choose(tr:t('ui.substitute'),items,function(out)
   local eligible={};for _,entry in ipairs(view.latest.bench or {})do eligible[entry.id]=true end
   local bench={};for _,q in ipairs(profile.roster)do if eligible[q.id] then bench[#bench+1]={id=q.id,name=q.name..' · '..q.pos}end end
   choose(tr:t('ui.substitute'),bench,function(incoming)send('control',{action='substitute',out=out.id,inId=incoming.id});input:setBlocked(false)end)
  end)
 end},
 {label=tr:t('ui.continue'),callback=function()send('control',{action='continue'});input:setBlocked(false)end},
 {label=tr:t('ui.cancel'),callback=function()input:setBlocked(false)end}})
end
local function refresh()
 if not profile then return end
 tr:setLocale((profile.settings or {}).locale or 'auto',player.LocaleId)
 for _,item in ipairs((profile.shop or {}).catalog or {}) do
  if item.enabled and item.robloxId and item.robloxId>0 and not screens.prices[item.id] and not screens.priceBusy[item.id] then
   screens.priceBusy[item.id]=true
   task.spawn(function()
    local ok,info=pcall(function() return game:GetService('MarketplaceService'):GetProductInfoAsync(item.robloxId,Enum.InfoType[item.infoType]) end)
    if ok and info and info.IsForSale~=false then screens.prices[item.id]=info.PriceInRobux end
    screens.priceBusy[item.id]=nil;ui:refresh(false)
   end)
  end
 end
 audio:settingsChanged(profile.settings or {});input:setSettings(profile.settings or {}); screens.profile=profile; ui:update(profile)
end
screens.onRename=function()
 local box;ui:modal(tr:t('club.rename'),tr:t('club.renameHelp'),{{label=tr:t('ui.confirm'),callback=function()send('rename',{name=box.Text})end},{label=tr:t('ui.cancel'),callback=function()end}})
 box=UI.make('TextBox',{Text=profile.club,ClearTextOnFocus=false,TextSize=18,Font=Enum.Font.Gotham,TextColor3=UI.colors.text,BackgroundColor3=UI.colors.card,Position=UDim2.fromOffset(20,150),Size=UDim2.new(1,-40,0,48),ZIndex=54},ui.modalFrame:FindFirstChild('Panel'))
end
screens.onRemap=function(action)
 input:remap(function(key) local bindings={}; for k,v in pairs((profile.settings or {}).bindings or {}) do bindings[k]=v end; bindings[action]=key; send('settings',{key='bindings',value=bindings}) end)
end
screens.onTutorial=function() send('practice',{kind='tutorial'}) end
tr:attachRoblox(player,nil,function()if profile then ui:update(profile)end end)
event.OnClientEvent:Connect(function(kind,data)
 if kind~='snapshot' then pending=nil end
 if kind=='profile' then profile=data; revision=data.revision or 0; refresh()
 elseif kind=='patch' then
  if not profile or data.base~=revision then send('ready'); return end
  for k,v in pairs(data.fields) do profile[k]=v end
  for _,k in ipairs(data.removed or {}) do profile[k]=nil end
  revision=data.revision; profile.revision=revision; refresh()
 elseif kind=='records' then
  local lines={};for i,row in ipairs(data.rows)do lines[#lines+1]=i..'. '..row.userId..' · '..row.points end
  ui:modal(tr:t('records.title')..' · '..tr:t(data.mode=='simulate' and 'ui.modeSimulate' or data.mode=='highlights' and 'ui.modeHighlights' or 'ui.modeManual')..' / '..tr:t('difficulty.'..data.difficulty),#lines>0 and table.concat(lines,'\n')or tr:t('ui.empty'),{{label=tr:t('ui.continue'),callback=function()end}})
 elseif kind=='playerHistory' then
  local lines={};for _,row in ipairs(data.rows or {})do lines[#lines+1]=tr:t('player.historyRow',{season=row.season,age=row.age or "—",rating=row.rating or "—",goals=row.goals or 0,assists=row.assists or 0})end
  ui:modal(data.name,#lines>0 and table.concat(lines,'\n')or tr:t('ui.empty'),{{label=tr:t('ui.close'),callback=function()end}})
 elseif kind=='toast' then ui:message(tr:event(data))
 elseif kind=='matchStart' then ui.matchActive=true;ui:clearSelection();audio:match(true);audio:snapshot(data);view:show(profile,data); input:setActive(true)
 elseif kind=='snapshot' then audio:snapshot(data);view:push(data)
 elseif kind=='result' then
  ui.matchActive=false;audio:match(false);input:setActive(false); view:hide()
  Results.show(ui,tr,data,profile,function()ui:open('hub')end)
 end
end)
Run.RenderStepped:Connect(function() view:render(); input:step() end)
send('ready')
]========],sp)
put('ModuleScript','Diagnostics',[========[-- Explicit Studio CLIENT measurement. Never enabled in a published client.
local D={}
function D.run(seconds,options)
 local Run=game:GetService('RunService');assert(Run:IsStudio()and Run:IsClient(),'Use the CLIENT Command Bar during Studio Play')
 options=options or {};seconds=math.max(10,math.min(1800,tonumber(seconds)or 60));local warmup=5
 local Stats=game:GetService('Stats');local Input=game:GetService('UserInputService');local player=game:GetService('Players').LocalPlayer
 local gui=player:WaitForChild('PlayerGui');local function memory()local ok,n=pcall(function()return Stats:GetTotalMemoryUsageMb()end);return ok and n or nil end
 local function traffic(name)local ok,n=pcall(function()return Stats.Network.ServerStatsItem[name]:GetValue()end);return ok and n or nil end
 local samples={};local start=os.clock();local active=false;local memoryBefore;local instancesBefore
 local connection=Run.RenderStepped:Connect(function(dt)if active then samples[#samples+1]=dt*1000 end end)
 while os.clock()-start<warmup do task.wait(.1)end
 memoryBefore=memory();instancesBefore=#gui:GetDescendants();local downloadBefore=traffic('Data Receive Kbps');active=true;start=os.clock()
 while os.clock()-start<seconds do task.wait(.1)end
 active=false;connection:Disconnect();table.sort(samples)
 local function percentile(p)if #samples==0 then return nil end;return samples[math.max(1,math.ceil(#samples*p))]end
 local view=workspace.CurrentCamera.ViewportSize
 local report={environment='Roblox Studio CLIENT',deviceLabel=options.deviceLabel or 'not supplied',viewport={x=view.X,y=view.Y},touch=Input.TouchEnabled,gamepad=Input.GamepadEnabled,warmupSeconds=warmup,elapsedSeconds=os.clock()-start,frames=#samples,frameP50Ms=percentile(.5),frameP95Ms=percentile(.95),memoryBeforeMb=memoryBefore,memoryAfterMb=memory(),playerGuiInstancesBefore=instancesBefore,playerGuiInstancesAfter=#gui:GetDescendants(),allTrafficReceiveKbpsBefore=downloadBefore,allTrafficReceiveKbpsAfter=traffic('Data Receive Kbps'),allTrafficSendKbpsAfter=traffic('Data Send Kbps')}
 print('TOUCHLINE_CLIENT_QA '..game:GetService('HttpService'):JSONEncode(report));return report
end
return D
]========],shared)
put('ModuleScript','Economy',[========[local K=require(script.Parent.EconomyConfig)
local Loans=require(script.Parent.Loans)
local E={}
local function finite(x)return type(x)=='number'and x==x and math.abs(x)<1e15 end
function E.value(q,reputation)
 local age=q.age<=21 and 1.25 or q.age>=33 and .58 or q.age>=29 and .82 or 1
 local years=math.max(0,(q.contractEnd or 3)-(q.currentSeason or 1));local contract=.7+math.min(4,years)*.10
 local potential=1+math.max(0,(q.scouted and q.potential or q.rating+5)-q.rating)*.008
 local form=.9+(q.form or 65)*.002
 return math.max(8000,math.floor((q.rating-20)^2*95*age*contract*potential*form*(1+(reputation or 0)*.0005)))
end
function E.spend(p,amount)
 if not finite(amount)or amount<0 or amount%1~=0 then return false,'INVALID_AMOUNT'end
 if p.cash<amount then return false,'INSUFFICIENT_FUNDS'end
 p.cash=p.cash-amount;return true
end
function E.credit(p,amount)
 if not finite(amount)or amount<0 or amount%1~=0 then return false,'INVALID_AMOUNT'end
 local repayment=math.min(p.debt or 0,math.floor(amount*.20));p.debt=math.max(0,(p.debt or 0)-repayment)
 p.cash=p.cash+amount-repayment;return true
end
function E.charge(p,amount)
 amount=math.max(0,math.floor(amount));local covered=math.min(p.cash,amount);p.cash=p.cash-covered;p.debt=(p.debt or 0)+amount-covered
end
function E.wages(p)
 local n=0;for _,q in ipairs(p.roster)do n=n+math.floor((q.wage or K.minimumWage)*(q.loanOut and .5 or 1))end
 for _,q in ipairs(p.academy or{})do n=n+math.floor((q.wage or 100)*.35*(q.loanOut and .5 or 1))end
 return math.floor(n)
end
function E.upkeep(p)
 local n=0;for _,v in pairs(p.upgrades)do n=n+v*K.facilityUpkeep end
 for _,v in pairs(p.staff)do n=n+v*K.staffUpkeep end
 return n
end
function E.recoveryPerDay(p)
 return K.recoveryPerDay+(math.max(1,p.upgrades.medical or 1)-1)*K.medicalRecoveryPerLevel+(math.max(1,p.staff.doctor or 1)-1)*K.doctorRecoveryPerLevel
end
function E.advance(p,newDate)
 local oldAbs=(p.season-1)*K.seasonDays+(p.date or 0);local newAbs=(p.season-1)*K.seasonDays+newDate
 local oldWeek=math.floor(oldAbs/7);local newWeek=math.floor(newAbs/7);local weeks=math.max(0,newWeek-oldWeek)
 Loans.advance(p,p.date or 0,newDate,weeks)
 local elapsed=math.max(0,newDate-(p.date or 0));local recovery=elapsed*E.recoveryPerDay(p)
 for _,q in ipairs(p.roster)do q.fitness=math.min(100,q.fitness+recovery)end
 local costs=weeks*(E.wages(p)+E.upkeep(p));E.charge(p,costs)
 p.financeLedger.wages=p.financeLedger.wages+weeks*E.wages(p);p.financeLedger.upkeep=p.financeLedger.upkeep+weeks*E.upkeep(p)
 p.date=newDate;return costs
end
function E.matchIncome(p,op,x,y,forfeit)
 if forfeit then return 0,{tickets=0,sponsor=0,prize=0}end
 local won=x>y;local league=op.kind=='league';local occupancy=math.min(.95,.48+p.reputation*.001+(7-p.division)*.035+(op.derby and K.derbyOccupancyBonus or 0))
 local tickets=op.neutral and math.floor(K.neutralCapacity*K.neutralOccupancy*K.ticketPrice/2)or op.home and math.floor((K.stadiumCapacity+(p.upgrades.stadium-1)*K.capacityPerLevel)*occupancy*K.ticketPrice)or 0
 if op.kind=='friendly'then tickets=math.floor(tickets*.40)end
 local sponsor=league and(p.sponsor=='performance'and(K.sponsorPerformanceBase+(won and K.sponsorWinBonus or 0))or K.sponsorStable)or 0
 local broadcast=league and (K.leagueBroadcast[p.division]or 0)or 0
 local breakdown={tickets=tickets,sponsor=sponsor,broadcast=broadcast,prize=0};local income=tickets+sponsor+broadcast;E.credit(p,income)
 p.financeLedger.broadcast=(p.financeLedger.broadcast or 0)+broadcast;p.financeLedger.tickets=p.financeLedger.tickets+tickets;p.financeLedger.sponsors=p.financeLedger.sponsors+sponsor
 return income,breakdown
end
function E.upgradeCost(level)return K.upgradeBase*level end
function E.staffCost(level)return K.staffBase*level*level end
function E.forecast(p)
 local wages=E.wages(p);local upkeep=E.upkeep(p);local weeks=math.ceil(K.seasonDays/7)
 local avgTickets=math.floor((K.stadiumCapacity+(p.upgrades.stadium-1)*K.capacityPerLevel)*math.min(.95,.48+p.reputation*.001+(7-p.division)*.035)*K.ticketPrice)
 local income=30*(K.leagueBroadcast[p.division]or 0)+15*avgTickets+30*(p.sponsor=='stable'and K.sponsorStable or K.sponsorPerformanceBase+K.sponsorWinBonus*.4)
 return{broadcastPerMatch=K.leagueBroadcast[p.division]or 0,recoveryPerDay=E.recoveryPerDay(p),wages=wages,upkeep=upkeep,projectedIncome=income,projectedExpenses=weeks*(wages+upkeep),net=income-weeks*(wages+upkeep),ledger=p.financeLedger,debt=p.debt or 0}
end
function E.endSeason(p,place)
 local prize=math.floor((17-place)*K.prizePerPlace*(1+(6-p.division)*K.prizeDivisionFactor));E.credit(p,prize)
 p.financeLedger.prizes=p.financeLedger.prizes+prize;E.charge(p,math.floor((p.debt or 0)*K.loanInterest));return prize
end
function E.newLedger()return{broadcast=0,tickets=0,sponsors=0,prizes=0,transfersIn=0,transfersOut=0,wages=0,upkeep=0}end
return E
]========],server)
put('ModuleScript','EconomyConfig',[========[-- All amounts are fictional club currency, never sold for Robux.
return {
 medicalSessionCost=12000,neutralCapacity=3000,neutralOccupancy=.75,derbyOccupancyBonus=.08,
 leagueBroadcast={22000,15000,9500,6000,3500,1500},
 recoveryPerDay=1.2,medicalRecoveryPerLevel=.12,doctorRecoveryPerLevel=.15,
 initialCash=320000,maxRoster=30,maxAcademy=6,maxFacility=10,maxStaff=5,
 saleHoldDays=56,seasonDays=180,windowOneEnd=36,windowTwoStart=70,windowTwoEnd=92,
 signingBonus=.22,freeSigningBonus=.38,agentRate=.065,loanRate=.18,buyoutRate=1.08,
 weeklyWageFactor=7,minimumWage=120,academyIntake=24000,scoutFee=2500,
 stadiumCapacity=1400,capacityPerLevel=400,ticketPrice=14,
 sponsorStable=8000,sponsorPerformanceBase=3000,sponsorWinBonus=11000,
 facilityUpkeep=125,staffUpkeep=350,upgradeBase=65000,staffBase=22000,
 prizePerPlace=12000,prizeDivisionFactor=.32,cupPrize=45000,
 emergencyWage=140,restructureCredit=90000,loanInterest=.04,
 retainedClubLimit=4,historyLimit=120,newsLimit=48,seasonHistoryLimit=40,
 difficulty={easy={ai=.93,label='difficulty.easy'},normal={ai=1,label='difficulty.normal'},hard={ai=1.07,label='difficulty.hard'}},
}
]========],server)
put('ModuleScript','Input',[========[-- Input intentions only; movement, power and cooldowns are validated by the server.
local UI=require(script.Parent.UI)
local I={}
local defaults={pass='Space',shoot='F',through='E',switch='Q',tackle='R',sprint='LeftShift'}
I.defaults=defaults
local function keyName(input) local k=input.KeyCode; if type(k)=='string' then return k:match('%.([^%.]+)$') or k end; return k and k.Name end
function I.new(gui,view,tr,send)
 local UIS=game:GetService('UserInputService'); local self={uis=UIS,view=view,tr=tr,send=send,active=false,blocked=false,keys={},bindings={},connections={},move=Vector2.new(0,0),stick=Vector2.new(0,0),pad=Vector2.new(0,0),aim=0,sprint=false,lastSent=0,charge=nil,joystickTouch=nil,shootTouch=nil,dead=false}
 setmetatable(self,{__index=I}); self:setSettings({})
 self.root=UI.make('Frame',{Name='MatchControls',BackgroundTransparency=1,Size=UDim2.fromScale(1,1),Visible=false,ZIndex=20},gui)
 self.joystick=UI.round(UI.make('Frame',{Name='Movement',Size=UDim2.fromOffset(138,138),BackgroundColor3=UI.colors.panel,BackgroundTransparency=.2,Active=true},self.root),100)
 self.knob=UI.round(UI.make('Frame',{Size=UDim2.fromOffset(54,54),Position=UDim2.new(.5,-27,.5,-27),BackgroundColor3=UI.colors.muted,BackgroundTransparency=.15},self.joystick),100)
 self.actions={}
 for index,action in ipairs({'pass','shoot','through','switch','tackle','sprint'}) do
  local b=UI.button(self.root,tr:t('ui.'..action),nil,action=='shoot'); b.Name=action; self.actions[action]=b
  if action=='shoot' then
   self.connections[#self.connections+1]=b.InputBegan:Connect(function(input) if self:touch(input) and self:canControl() then self.shootTouch=input; self.charge=os.clock() end end)
   self.connections[#self.connections+1]=b.InputEnded:Connect(function(input) if input==self.shootTouch then self:shoot(); self.shootTouch=nil end end)
  elseif action=='sprint' then
   self.connections[#self.connections+1]=b.InputBegan:Connect(function(input) if self:touch(input) and self:canControl() then self:setSprint(true); self.sprintTouch=input end end)
   self.connections[#self.connections+1]=b.InputEnded:Connect(function(input) if input==self.sprintTouch then self:setSprint(false); self.sprintTouch=nil end end)
  else
   self.connections[#self.connections+1]=b.Activated:Connect(function() if self:canControl() then self.send('control',{action=action}) end end)
  end
 end
 self.hint=UI.label(self.root,'',13,false); self.hint.TextColor3=UI.colors.muted; self.hint.TextXAlignment=Enum.TextXAlignment.Center
 self.connections[#self.connections+1]=self.joystick.InputBegan:Connect(function(input) if self:touch(input) and self:canControl() and not self.joystickTouch then self.joystickTouch=input; self:updateTouch(input) end end)
 self.connections[#self.connections+1]=UIS.InputBegan:Connect(function(input,processed) self:began(input,processed) end)
 self.connections[#self.connections+1]=UIS.InputChanged:Connect(function(input,processed)
  if input==self.joystickTouch then self:updateTouch(input) end
  local key=keyName(input)
  if key=='Thumbstick1' and not processed then self.pad=Vector2.new(input.Position.X,-input.Position.Y) end
  if key=='Thumbstick2' and not processed then self.aim=-input.Position.Y end
 end)
 self.connections[#self.connections+1]=UIS.InputEnded:Connect(function(input) self:ended(input) end)
 self.connections[#self.connections+1]=UIS.WindowFocusReleased:Connect(function() self:reset() end)
 self.connections[#self.connections+1]=UIS.TextBoxFocused:Connect(function() self:reset() end)
 self.connections[#self.connections+1]=workspace.CurrentCamera:GetPropertyChangedSignal('ViewportSize'):Connect(function() self:resize() end)
 self:resize(); return self
end
function I:touch(input) return input.UserInputType==Enum.UserInputType.Touch or input.UserInputType==Enum.UserInputType.MouseButton1 end
function I:setSettings(settings)
 self.settings=settings;for action,button in pairs(self.actions or {})do button.Text=self.tr:t('ui.'..action)end; for action,key in pairs(defaults) do self.bindings[action]=(settings.bindings or {})[action] or key end
end
function I:canControl()
 return self.active and not self.view.replay and not self.blocked and not self.uis:GetFocusedTextBox() and (not self.view.latest or self.view.latest.phase~='penalties' and self.view.latest.interactive~=false)
end
function I:resize()
 local v=workspace.CurrentCamera.ViewportSize; self.joystick.Position=UDim2.new(0,16,1,-214)
 local touch=self.uis.TouchEnabled; self.joystick.Visible=touch
 local index=0
 for _,action in ipairs({'pass','shoot','through','switch','tackle','sprint'}) do
  local b=self.actions[action]; local col=index%3; local row=math.floor(index/3)
  b.Visible=touch; b.Position=UDim2.new(1,-(3-col)*63-10,1,-190+row*62); b.Size=UDim2.fromOffset(58,54); b.TextSize=11; index=index+1
 end
 self.hint.Position=UDim2.new(.5,-math.min(310,v.X/2),1,-84); self.hint.Size=UDim2.fromOffset(math.min(620,v.X),24)
 local parts={}; for _,a in ipairs({'pass','shoot','through','switch','tackle','sprint'}) do parts[#parts+1]=self.tr:t('ui.'..a)..' ['..self.bindings[a]..']' end
 self.hint.Text=touch and '' or table.concat(parts,'  ·  ')
end
function I:updateTouch(input)
 local center=self.joystick.AbsolutePosition+self.joystick.AbsoluteSize/2; local delta=Vector2.new(input.Position.X,input.Position.Y)-center
 local len=delta.Magnitude; if len>48 then delta=delta/len*48 end
 self.stick=delta/48; self.knob.Position=UDim2.new(.5,delta.X-27,.5,delta.Y-27)
end
function I:setSprint(enabled)
 if self.sprint==enabled then return end; self.sprint=enabled
 if self.active then self.send('control',{action='sprint',enabled=enabled}) end
end
function I:began(input,processed)
 local key=keyName(input)
 if self.remapping and not processed and input.UserInputType==Enum.UserInputType.Keyboard then
  local callback=self.remapping; self.remapping=nil; callback(key); return
 end
 if processed or not self:canControl() then return end
 self.keys[key]=true
 local pads={ButtonA='pass',ButtonX='through',ButtonB='shoot',ButtonY='switch',ButtonR1='tackle',ButtonR2='sprint'}
 local action=pads[key]; for a,k in pairs(self.bindings) do if k==key then action=a; break end end
 if action=='shoot' then self.charge=os.clock()
 elseif action=='sprint' then self:setSprint(true)
 elseif action then self.send('control',{action=action}) end
end
function I:ended(input)
 local key=keyName(input); self.keys[key]=nil
 if input==self.joystickTouch then self.joystickTouch=nil; self.stick=Vector2.new(0,0); self.knob.Position=UDim2.new(.5,-27,.5,-27) end
 if input==self.shootTouch then self:shoot(); self.shootTouch=nil end
 if input==self.sprintTouch or key==self.bindings.sprint or key=='ButtonR2' then self:setSprint(false); self.sprintTouch=nil end
 if key==self.bindings.shoot or key=='ButtonB' then self:shoot() end
end
function I:shoot()
 if not self.charge then return end
 local duration=os.clock()-self.charge; self.charge=nil
 if not self:canControl() then return end
 local y=32+self.aim*11
 if not self.uis.TouchEnabled and self.uis.MouseEnabled then
  local mouse=self.uis:GetMouseLocation(); local pos,size=self.view.pitch.AbsolutePosition,self.view.pitch.AbsoluteSize
  if size.Y>0 then y=math.max(0,math.min(64,(mouse.Y-pos.Y)/size.Y*64)) end
 end
 self.send('control',{action='shoot',y=y,power=math.max(.25,math.min(1,.35+duration*.9))})
 if self.settings.haptics then pcall(function() game:GetService('HapticService'):SetMotor(Enum.UserInputType.Gamepad1,Enum.VibrationMotor.Small,.2); task.delay(.08,function() pcall(function() game:GetService('HapticService'):SetMotor(Enum.UserInputType.Gamepad1,Enum.VibrationMotor.Small,0) end) end) end) end
end
function I:step()
 if not self:canControl() then return end
 local x,y=self.stick.X+self.pad.X,self.stick.Y+self.pad.Y
 if self.keys.W or self.keys.Up then y=y-1 end; if self.keys.S or self.keys.Down then y=y+1 end
 if self.keys.A or self.keys.Left then x=x-1 end; if self.keys.D or self.keys.Right then x=x+1 end
 local length=math.sqrt(x*x+y*y); if length>1 then x,y=x/length,y/length end
 if os.clock()-self.lastSent>=.08 then self.lastSent=os.clock(); self.send('input',{x=x,y=y}) end
end
function I:setActive(active)
 self.active=active; self.root.Visible=active; self:reset(); self:resize()
end
function I:setBlocked(blocked) self.blocked=blocked; if blocked then self:reset() end end
function I:reset()
 self.keys={}; self.stick=Vector2.new(0,0); self.pad=Vector2.new(0,0); self.charge=nil; self.joystickTouch=nil; self.shootTouch=nil
 if self.active then self.send('input',{x=0,y=0}) end; self:setSprint(false); self.knob.Position=UDim2.new(.5,-27,.5,-27)
end
function I:remap(callback) self.remapping=callback; self:reset() end
function I:destroy() self.dead=true; self:reset(); for _,c in ipairs(self.connections) do c:Disconnect() end; self.root:Destroy() end
return I
]========],shared)
put('ModuleScript','Loans',[========[-- Outgoing NPC loans use game dates, never wall-clock waiting.
local P=require(script.Parent.Players)
local W=require(script.Parent.World)
local K=require(script.Parent.EconomyConfig)
local L={}
function L.out(p,C,id,E)
 if not W.transferOpen(p.date)then return false,'TRANSFER_WINDOW_CLOSED'end
 local q=C.find(p,id);local youth=false
 if not q then for _,a in ipairs(p.academy)do if a.id==id then q=a;youth=true;break end end end
 if not q then return false,'PLAYER_NOT_FOUND'end
 if q.loan or q.loanOut or q.emergency or not P.available(q)then return false,'LOAN_UNAVAILABLE'end
 if not youth then
  for _,starter in ipairs(p.lineup)do if starter==id then return false,'PLAYER_IN_LINEUP'end end
  local count,gk=0,0;for _,a in ipairs(p.roster)do if P.available(a)then count=count+1;if a.pos=='GK'then gk=gk+1 end end end
  if count<=16 then return false,'SQUAD_DEPTH_REQUIRED'end;if q.pos=='GK'and gk<=2 then return false,'KEEPER_REQUIRED'end
 end
 local fee=math.floor(E.value(q)*.12);local clubs={}
 for _,club in pairs(p.world.clubs)do if club.id~=p.clubId and club.rating>=q.rating-18 and club.rating<=q.rating+8 and club.cash>=fee+q.wage*13 then clubs[#clubs+1]=club end end
 table.sort(clubs,function(a,b)return a.id<b.id end);if#clubs==0 then return false,'NO_BUYER'end
 local club=clubs[W.hash(id..':'..p.season)%#clubs+1];club.cash=club.cash-fee;E.credit(p,fee)
 p.financeLedger.transfersIn=p.financeLedger.transfersIn+fee;p.financeLedger.loans=(p.financeLedger.loans or 0)+fee
 q.loanOut={clubId=club.id,clubName=club.name,ends=p.season,fee=fee,wageShare=.5,played=0}
 return true,'PLAYER_LOANED_OUT',{name=q.name,buyer=club.name,amount=fee}
end
function L.advance(p,from,to,weeks)
 local games=math.max(0,math.floor(math.min(120,to)/4)-math.floor(math.min(120,from)/4))
 for _,list in ipairs({p.roster,p.academy})do for _,q in ipairs(list)do
  if q.loanOut and q.loanOut.ends>=p.season then
   local club=p.world.clubs[q.loanOut.clubId]
   if club then club.cash=math.max(0,club.cash-math.floor(q.wage*q.loanOut.wageShare*weeks));for _=1,games do P.develop(q,club.infrastructure.training,true,false)end end
   q.loanOut.played=q.loanOut.played+games
  end
 end end
end
return L
]========],server)
put('ModuleScript','Locales',[========[-- Generated by localization/build_locales.py. Edit strings.tsv, then regenerate.
return {
  en = {
    ["ALREADY_NEGOTIATED"] = "This offer has already been negotiated.",
    ["ALREADY_OWNED"] = "You already own this item.",
    ["ALREADY_SCOUTED"] = "The scouting report is already available.",
    ["COSMETIC_APPLIED"] = "Cosmetic applied to the club.",
    ["COSMETIC_NOT_OWNED"] = "This cosmetic is not in your collection.",
    ["COSMETIC_OWNED"] = "Cosmetic added to your collection.",
    ["COSMETIC_UPDATED"] = "Cosmetic collection updated.",
    ["DUPLICATE_PLAYER"] = "This player is already in your squad.",
    ["INSUFFICIENT_FUNDS"] = "Not enough club budget.",
    ["INVALID_AMOUNT"] = "The amount is invalid.",
    ["KEEPER_REQUIRED"] = "Keep enough available goalkeepers.",
    ["LOAN_UNAVAILABLE"] = "This loan action is unavailable.",
    ["LOCK_LOST"] = "This server lost profile ownership. Rejoin to protect progress.",
    ["MIGRATION_FAILED"] = "The older career could not be converted safely. Original data was preserved.",
    ["NEGOTIATION_COMPLETE"] = "Negotiation completed. Total signing cost: {amount}.",
    ["NO_BUYER"] = "There is no interested NPC buyer right now.",
    ["NO_SESSION"] = "No active profile session. Rejoin and retry.",
    ["OFFER_EXPIRED"] = "This offer has expired on the football calendar.",
    ["OFFER_UNAVAILABLE"] = "This offer is no longer available.",
    ["OPERATION_FAILED"] = "The profile operation failed. Please retry.",
    ["OPERATION_REJECTED"] = "The profile operation was rejected.",
    ["PASSES_CURRENT"] = "Pass ownership refreshed.",
    ["PASS_CHECK_FAILED"] = "Pass ownership could not be checked. Retry shortly.",
    ["PASS_REQUIRED"] = "This cosmetic requires the corresponding pass.",
    ["PLAYER_IN_LINEUP"] = "Move this player out of the starting eleven first.",
    ["PLAYER_LOANED"] = "{name} joined on loan. Signing cost: {amount}.",
    ["PLAYER_LOANED_OUT"] = "{name} loaned to {buyer}; fee {amount}.",
    ["PLAYER_NOT_FOUND"] = "Player not found.",
    ["PLAYER_NOT_OWNED"] = "This player belongs to another club.",
    ["PLAYER_SIGNED"] = "{name} signed. Total signing cost: {amount}.",
    ["PLAYER_SOLD"] = "{name} sold. Transfer income: {amount}.",
    ["PRODUCT_NOT_CONFIGURED"] = "This Roblox product has not been connected yet.",
    ["PROFILE_INVALID"] = "The profile could not be validated. Saved data was not reset.",
    ["PROFILE_LOCKED_OR_INVALID"] = "The career is in another session or needs validation. Please rejoin later.",
    ["PROFILE_STALE"] = "The profile changed. Refresh and retry.",
    ["PURCHASE_PROMPT"] = "Complete or cancel the Roblox purchase window.",
    ["PURCHASE_UNAVAILABLE"] = "The Roblox purchase window could not be opened.",
    ["RESALE_HOLD"] = "Recently signed players cannot be sold immediately.",
    ["ROSTER_FULL"] = "The first-team contract limit has been reached.",
    ["SAVED"] = "Career saved.",
    ["SCOUT_COMPLETE"] = "Scouting report ready for {name}.",
    ["SESSION_EXISTS"] = "This profile session is already open.",
    ["SHOP_ACTION_INVALID"] = "This shop action is unavailable.",
    ["SHOP_ITEM_INVALID"] = "Shop item not found.",
    ["SHOP_UNAVAILABLE"] = "The club shop is temporarily unavailable.",
    ["SQUAD_DEPTH_REQUIRED"] = "Keep enough players to field a legal squad.",
    ["STORE_BUSY"] = "A profile operation is in progress.",
    ["STORE_THROTTLED"] = "The save service is busy. Retry shortly.",
    ["STORE_UNAVAILABLE"] = "Saving is temporarily unavailable. Retry shortly.",
    ["STUDIO_PURCHASE_DISABLED"] = "Real purchases are disabled in Studio. Use the isolated test adapter.",
    ["TEST_SESSION"] = "Studio sandbox session: live data is not used.",
    ["TOKENS_REQUIRED"] = "Not enough cosmetic tokens.",
    ["TOKEN_LIMIT"] = "The cosmetic token limit has been reached.",
    ["TRANSFER_WINDOW_CLOSED"] = "The transfer window is closed.",
    ["WAGE_RESERVE_REQUIRED"] = "Keep a reserve to cover the squad's wages.",
    ["achievement.academy"] = "Two academy graduates",
    ["achievement.firstWin"] = "First victory",
    ["achievement.promotion"] = "Promotion",
    ["achievement.tenWins"] = "Ten victories",
    ["attribute.defending"] = "Defending",
    ["attribute.dribbling"] = "Dribbling",
    ["attribute.foot"] = "Preferred foot",
    ["attribute.form"] = "Form",
    ["attribute.goalkeeping"] = "Goalkeeping",
    ["attribute.handling"] = "Handling",
    ["attribute.morale"] = "Morale",
    ["attribute.pace"] = "Pace",
    ["attribute.passing"] = "Passing",
    ["attribute.physical"] = "Physical",
    ["attribute.positioning"] = "Positioning",
    ["attribute.reflexes"] = "Reflexes",
    ["attribute.shooting"] = "Shooting",
    ["attribute.stamina"] = "Stamina",
    ["board.missed"] = "The previous season’s board objective was not met. Career continues.",
    ["board.reward"] = "Board objective completed: +20 cosmetic tokens.",
    ["bracket.bye"] = "Seeded bye in round {round}",
    ["bracket.round"] = "Round {round}",
    ["bracket.winner"] = "Winner: {club}",
    ["club.designHelp"] = "Palette {palette}; crest {shape}; motif {symbol}. Changes are cosmetic only.",
    ["club.identity"] = "Club identity",
    ["club.identityHelp"] = "Basic naming, two palettes and two crest shapes are free. Club Identity unlocks more safe design elements.",
    ["club.rename"] = "Club name",
    ["club.renameHelp"] = "2–24 characters. Roblox filters the name before saving. One successful rename per minute.",
    ["code.ACADEMY_ALREADY_RECRUITED"] = "This season’s academy intake has already taken place.",
    ["code.ACADEMY_FULL"] = "The academy has six players. Promote or release one first.",
    ["code.CONTRACT_NOT_DUE"] = "This contract already covers at least three more seasons.",
    ["code.GOAL_LOCKED"] = "Choose a board priority during the first three rounds.",
    ["code.JOB_CONTRACT_ACTIVE"] = "Your three-year manager contract is active. Offers arrive at the next season opening after expiry.",
    ["code.JOB_WINDOW_CLOSED"] = "Manager appointments are available only at the start of a new season.",
    ["code.KEEPER_REQUIRED"] = "Keep eligible goalkeepers and assign a goalkeeper to slot 1.",
    ["code.MAX_LEVEL"] = "The maximum upgrade level has been reached.",
    ["code.NAME_COOLDOWN"] = "Wait one minute between successful renames.",
    ["code.NAME_FILTER_UNAVAILABLE"] = "Roblox filtering is unavailable. The name was not changed. Retry later.",
    ["code.NAME_INVALID"] = "Use 2–24 valid characters without line breaks or control codes.",
    ["code.NAME_IN_USE"] = "Another club already uses this name.",
    ["code.NAME_REJECTED"] = "Choose a different name accepted by the Roblox filter.",
    ["code.NO_BUYER"] = "No NPC club currently has demand for this player.",
    ["code.NO_REWARD"] = "There are no unclaimed achievement rewards.",
    ["code.OFFER_EXPIRED"] = "The offer has expired on the game calendar.",
    ["code.OFFER_UNAVAILABLE"] = "This offer is no longer available; refresh the market.",
    ["code.PASS_REQUIRED"] = "This element requires Club Identity. Two palettes and two basic crest shapes remain free.",
    ["code.PLAYER_IN_LINEUP"] = "Move this player out of the starting XI before selling.",
    ["code.PLAYER_UNAVAILABLE"] = "The player is injured, suspended or ineligible for registration.",
    ["code.RECOVERY_ALREADY_USED"] = "Recovery has already been used on this game date.",
    ["code.RECOVERY_NOT_NEEDED"] = "Calendar recovery is sufficient before the next fixture; a paid session is unnecessary.",
    ["code.REPUTATION_REQUIRED"] = "Your reputation does not meet this club’s appointment requirement.",
    ["code.RESALE_HOLD"] = "A new signing must stay registered for 56 game days before sale.",
    ["code.RESTRUCTURE_USED"] = "Restructuring is available once per season and has already been used.",
    ["code.ROSTER_FULL"] = "The club already has 30 senior contracts. Sell a reserve before signing.",
    ["code.SCOUT_REGION_LOCKED"] = "Regional specialization can be changed once per season.",
    ["code.SEASON_COMPLETE"] = "All fixtures are complete. Start the next season in the club centre.",
    ["code.SEASON_NOT_COMPLETE"] = "Complete the remaining scheduled fixtures first.",
    ["code.SPONSOR_LOCKED"] = "The sponsor can only be changed once per season.",
    ["code.SQUAD_DEPTH_REQUIRED"] = "Keep at least 16 players before selling.",
    ["code.SQUAD_UNAVAILABLE"] = "Eleven eligible starters are required. Change the XI, use recovery, or accept a technical defeat to serve suspensions.",
    ["code.TRANSFER_WINDOW_CLOSED"] = "The transfer window is closed. Next opening is shown on the calendar.",
    ["code.WAGE_RESERVE_REQUIRED"] = "Keep enough cash to cover four weekly salaries for this signing.",
    ["competition.cup"] = "Cup",
    ["competition.friendly"] = "Friendly",
    ["competition.international"] = "International cup",
    ["competition.league"] = "League",
    ["competition.supercup"] = "Supercup",
    ["crest.diamond"] = "Diamond",
    ["crest.round"] = "Circle",
    ["crest.shield"] = "Shield",
    ["crest.star"] = "Star",
    ["difficulty.easy"] = "Assisted",
    ["difficulty.hard"] = "Expert",
    ["difficulty.normal"] = "Standard",
    ["error.alreadyClaimed"] = "This reward has already been claimed.",
    ["error.invalid"] = "Invalid request.",
    ["error.loan"] = "A loan player cannot be sold.",
    ["error.lockLost"] = "Profile ownership was lost. Rejoin to protect your progress.",
    ["error.matchActive"] = "Finish the current match first.",
    ["error.money"] = "Not enough club budget.",
    ["error.noTokens"] = "Not enough cosmetic tokens.",
    ["error.notOwned"] = "This cosmetic item is not owned.",
    ["error.player"] = "Player not found.",
    ["error.productDisabled"] = "This product is not connected to Roblox yet.",
    ["error.rateLimited"] = "Too many requests. Wait briefly and retry.",
    ["error.receiptPending"] = "Purchase delivery is pending. Roblox will retry automatically.",
    ["error.resale"] = "This player cannot be resold immediately after signing.",
    ["error.roster"] = "This action would leave an illegal squad.",
    ["error.save"] = "Saving is temporarily unavailable. Retry shortly.",
    ["error.seasonIncomplete"] = "Complete the scheduled football dates first.",
    ["error.server"] = "The operation failed. Your saved career was not reset.",
    ["error.unavailable"] = "This action is unavailable now.",
    ["error.windowClosed"] = "The transfer window is closed.",
    ["event.academy"] = "{name} joined the academy intake.",
    ["event.academy_released"] = "Academy player released: {name}.",
    ["event.achievement"] = "Achievement earned: {name}.",
    ["event.contract_expired"] = "{name}'s contract has expired.",
    ["event.derby"] = "Derby result: {club} {home}–{away} {opponent}.",
    ["event.emergency_registration"] = "Emergency registration: {name}.",
    ["event.goal_complete"] = "Season {season}: board objective completed, +20 cosmetic tokens.",
    ["event.legacy_completed"] = "The legacy season is complete.",
    ["event.loan_returned"] = "Loan ended: {name}.",
    ["event.manager_renewed"] = "Manager contract renewed through season {season}.",
    ["event.match_pen_loss"] = "{club} {home}–{away} {opponent}: lost on penalties.",
    ["event.match_pen_win"] = "{club} {home}–{away} {opponent}: won on penalties.",
    ["event.match_result"] = "{club} {home}–{away} {opponent}",
    ["event.migrated"] = "Your previous career has been preserved.",
    ["event.promotion"] = "The club will play in division {division}.",
    ["event.retired"] = "{name} has retired from football.",
    ["event.retirement_warning"] = "Retirement approaching: {name}.",
    ["event.season"] = "Season {season}: place {place}; prize {prize}.",
    ["event.transfer"] = "Transfer: {name}, amount {amount}.",
    ["event.welcome"] = "Welcome to {club}, division {division}.",
    ["facility.academy"] = "Academy facilities",
    ["facility.medical"] = "Medical centre",
    ["facility.stadium"] = "Stadium",
    ["facility.training"] = "Training centre",
    ["finance.broadcast"] = "League broadcast income",
    ["finance.confirmUpgrade"] = "One-time cost: {price}. Additional weekly upkeep: {upkeep}. Confirm this budget expense?",
    ["foot.left"] = "Left",
    ["foot.right"] = "Right",
    ["format.age"] = "{age} years old",
    ["format.contract"] = "Contract until season {season}",
    ["format.cost"] = "Fee {fee}; signing bonus {bonus}; agent {agent}; annual wage {wage}",
    ["format.date"] = "Season {season}, day {day}",
    ["format.division"] = "Division {division}",
    ["format.expiry"] = "Expires on day {day}",
    ["format.fixture"] = "{home} vs {away}",
    ["format.level"] = "Level {level}",
    ["format.money"] = "{amount} cr",
    ["format.players.few"] = "{count} players",
    ["format.players.many"] = "{count} players",
    ["format.players.one"] = "{count} player",
    ["format.players.other"] = "{count} players",
    ["format.score"] = "{home} {goalsHome}–{goalsAway} {away}",
    ["format.season"] = "Season {season}",
    ["goal.claimed"] = "Reward claimed",
    ["goal.finance.description"] = "Finish debt-free, cash at least the starting balance, and no technical defeats. Reward: 20 cosmetic tokens.",
    ["goal.league.description"] = "Finish in the top eight, with at most two technical defeats. Reward: 20 cosmetic tokens.",
    ["goal.unclaimed"] = "Reward available — use Claim",
    ["goal.youth.description"] = "Promote two academy players this season, with at most two technical defeats. Reward: 20 cosmetic tokens.",
    ["language.de"] = "Deutsch",
    ["language.en"] = "English",
    ["language.es"] = "Español",
    ["language.fr"] = "Français",
    ["language.ja"] = "日本語",
    ["language.ko"] = "한국어",
    ["language.pl"] = "Polski",
    ["language.pt-br"] = "Português (Brasil)",
    ["language.qps-ploc"] = "Pseudo (+50%)",
    ["language.ru"] = "Русский",
    ["language.tr"] = "Türkçe",
    ["language.uk"] = "Українська",
    ["loan.confirm"] = "{name}: loan until the end of this season. Your club pays half the wages and receives a fee of 12% of the valuation. No early recall. An NPC club must accept.",
    ["loan.outStatus"] = "On loan at {club} until season {season} ends; matches: {played}",
    ["market.filter.affordable"] = "Affordable fee",
    ["market.filter.all"] = "All players",
    ["market.filter.contract"] = "Contract: up to two seasons",
    ["market.filter.favorite"] = "Favourites",
    ["market.filter.free"] = "Free agents",
    ["market.filter.strong"] = "Rating 60+",
    ["market.filter.wage"] = "Lower wage",
    ["market.filter.young"] = "Age up to 21",
    ["market.filterHelp"] = "Cycle filters: age ≤21, rating ≥60, price ≤half budget, below-average wage, free agent, favourites.",
    ["market.impact"] = "Projected XI strength gain: {gain}. This does not guarantee results.",
    ["match.away"] = "Away",
    ["match.corner"] = "Corner kick",
    ["match.ended"] = "Full-time",
    ["match.extraTime"] = "Extra time",
    ["match.forfeit"] = "Forfeit: 0–3; no income or development.",
    ["match.foul"] = "Foul",
    ["match.freeKick"] = "Free kick",
    ["match.fulltime"] = "Full-time",
    ["match.goal"] = "Goal!",
    ["match.goalKick"] = "Goal kick",
    ["match.goalkeeperRequired"] = "Keep an eligible goalkeeper on the pitch.",
    ["match.halftime"] = "Half-time: adjust tactics and substitutions.",
    ["match.highlights"] = "Key moments",
    ["match.home"] = "Home",
    ["match.injury"] = "Injury",
    ["match.interception"] = "Interception",
    ["match.kickoff"] = "Kick-off",
    ["match.manual"] = "Manual",
    ["match.offside"] = "Offside",
    ["match.opponentGoal"] = "Opponent goal",
    ["match.pauseLimit"] = "Both tactical pauses have been used.",
    ["match.penalties"] = "Penalty shoot-out",
    ["match.penalty"] = "Penalty kick",
    ["match.penaltyGoal"] = "Penalty scored",
    ["match.penaltyMiss"] = "Penalty missed",
    ["match.penaltySave"] = "Penalty saved",
    ["match.penaltySaved"] = "Penalty saved",
    ["match.playerUnavailable"] = "This player is unavailable.",
    ["match.red"] = "Red card — player sent off",
    ["match.redCard"] = "Red card — player sent off",
    ["match.save"] = "Goalkeeper save",
    ["match.simulate"] = "Simulation",
    ["match.substitution"] = "Substitution",
    ["match.substitutionUnavailable"] = "No substitution is available now.",
    ["match.technicalDefeat"] = "Too many dismissals: technical defeat.",
    ["match.throwIn"] = "Throw-in",
    ["match.yellow"] = "Yellow card",
    ["match.yellowCard"] = "Yellow card",
    ["mentality.attack"] = "Attacking",
    ["mentality.balanced"] = "Balanced",
    ["mentality.defend"] = "Defensive",
    ["player.details"] = "Country: {country}. Foot: {foot}. Traits: {traits}.",
    ["player.formMorale"] = "Form: {form}; morale: {morale}.",
    ["player.historyRow"] = "Season {season}: age {age}, rating {rating}, goals {goals}, assists {assists}",
    ["position.DEF"] = "Defender",
    ["position.FWD"] = "Forward",
    ["position.GK"] = "Goalkeeper",
    ["position.MID"] = "Midfielder",
    ["records.rules"] = "3 points per win, 1 per draw. Separate categories for control mode and difficulty. Updates at most once per 120 seconds.",
    ["records.title"] = "Global career records",
    ["report.away"] = "Your opponent had home advantage.",
    ["report.back"] = "Back to report",
    ["report.dismissal"] = "Your team played with a dismissal.",
    ["report.factors"] = "Match factors",
    ["report.fewerShots"] = "The opponent had more shots on target.",
    ["report.home"] = "Home advantage was applied.",
    ["report.moreShots"] = "Your team had at least as many shots on target.",
    ["report.neutral"] = "Neutral venue: no home advantage; gate receipts are shared.",
    ["report.onTarget"] = "Shots on target",
    ["report.passAccuracy"] = "Pass accuracy %",
    ["report.possessionPercent"] = "Possession %",
    ["report.ratings"] = "Player ratings",
    ["report.red"] = "Red cards",
    ["report.shootout"] = "Penalties: {home}–{away}.",
    ["report.shots"] = "Shots",
    ["report.technical"] = "Administrative 3–0 result; individual goals and assists are not added.",
    ["report.yellow"] = "Yellow cards",
    ["scout.report"] = "Scouting report: {country}, game day {day}, fee {fee}.",
    ["scout.specialism"] = "Select a region once per season. Reports there cost 25% less and narrow potential to ±1 instead of ±2.",
    ["shop.badge_desc"] = "A cosmetic badge showing your support for development.",
    ["shop.broadcast"] = "Broadcast Studio",
    ["shop.broadcast.classic"] = "Classic broadcast",
    ["shop.broadcastStudio"] = "Broadcast Studio",
    ["shop.broadcast_cosmetic"] = "Changes the match scoreboard accent colour. Cosmetic only.",
    ["shop.broadcast_desc"] = "Broadcast colours and scoreboard presentation. Controls are unchanged.",
    ["shop.broadcast_pro"] = "Blue broadcast",
    ["shop.classic"] = "Classic club kit",
    ["shop.clean"] = "Clean broadcast",
    ["shop.clubIdentity"] = "Club Identity",
    ["shop.crest.shield"] = "Shield crest",
    ["shop.crest_desc"] = "A safe original crest element for your club identity.",
    ["shop.crest_star"] = "Star crest",
    ["shop.customization"] = "Customisation",
    ["shop.designer"] = "Designer floodlights",
    ["shop.donation_desc"] = "Voluntary repeatable support. No gameplay rewards or advantages.",
    ["shop.donation_l"] = "Large contribution",
    ["shop.donation_m"] = "Medium contribution",
    ["shop.donation_s"] = "Small contribution",
    ["shop.hoops"] = "Sky hoops",
    ["shop.identity"] = "Club Identity",
    ["shop.identity_desc"] = "Additional kit patterns, palettes and crest elements. Cosmetic only.",
    ["shop.kit.classic"] = "Classic kit",
    ["shop.kit.lime"] = "Lime kit",
    ["shop.kit.navy"] = "Navy kit",
    ["shop.kit_desc"] = "Preview the colours and pattern, then apply them to your team.",
    ["shop.lime"] = "Lime stripes",
    ["shop.night"] = "Night atmosphere",
    ["shop.passDescription"] = "Permanent cosmetic access. Football progression stays free.",
    ["shop.passes"] = "Passes",
    ["shop.prompt"] = "Confirm or cancel in the Roblox purchase window. Rewards arrive only after receipt validation.",
    ["shop.requires"] = "Requires {pass}",
    ["shop.stadium"] = "Stadium Designer",
    ["shop.stadium.classic"] = "Classic stands",
    ["shop.stadiumDesigner"] = "Stadium Designer",
    ["shop.stadium_cosmetic"] = "Changes the visible match pitch atmosphere. Cosmetic only.",
    ["shop.stadium_desc"] = "Cosmetic pitch and lighting styles. No home advantage bonus.",
    ["shop.sunset"] = "Sunset sash",
    ["shop.support"] = "Support development",
    ["shop.supportDescription"] = "A voluntary contribution. No football advantage is granted.",
    ["shop.supporter"] = "Supporter",
    ["shop.supporter_badge"] = "Supporter badge",
    ["shop.supporter_desc"] = "Supporter badge and cosmetic collection. No football advantage.",
    ["shop.tokens"] = "Tokens",
    ["shop.tokensDescription"] = "Tokens buy cosmetics only. They cannot be exchanged for players, budget or results.",
    ["shop.tokensLarge"] = "800 cosmetic tokens",
    ["shop.tokensMedium"] = "300 cosmetic tokens",
    ["shop.tokensSmall"] = "100 cosmetic tokens",
    ["shop.tokens_l"] = "800 cosmetic tokens",
    ["shop.tokens_m"] = "300 cosmetic tokens",
    ["shop.tokens_only"] = "Spend only on cosmetic club items. Cannot buy players or match results.",
    ["shop.tokens_s"] = "100 cosmetic tokens",
    ["sponsor.performance.description"] = "3,000 per completed league match plus 11,000 per win. Technical defeats pay nothing.",
    ["sponsor.stable.description"] = "8,000 per completed league match, independent of score. Technical defeats pay nothing.",
    ["staff.coach"] = "Coach",
    ["staff.doctor"] = "Doctor",
    ["staff.scout"] = "Scout",
    ["status.LOAN_UNAVAILABLE"] = "This player cannot be loaned out now.",
    ["status.loaded"] = "Career loaded",
    ["status.saved"] = "Saved",
    ["status.saving"] = "Saving…",
    ["status.studio"] = "Studio sandbox: data is separate from the live game.",
    ["status.success"] = "Completed",
    ["status.updated"] = "Updated",
    ["style.balanced"] = "Balanced",
    ["style.counter"] = "Counterattack",
    ["style.counter.desc"] = "Direct runs after recovery; less control against a deep defence.",
    ["style.counter.description"] = "Direct runs after recovery; less control against a deep defence.",
    ["style.lowblock"] = "Low block",
    ["style.lowblock.desc"] = "Compact defensive shape; fewer attacking runs and shots.",
    ["style.lowblock.description"] = "Compact defensive shape; fewer attacking runs and shots.",
    ["style.possession"] = "Possession",
    ["style.possession.desc"] = "Close support and accurate passing; vulnerable to pressure and fast breaks.",
    ["style.possession.description"] = "Close support and accurate passing; vulnerable to pressure and fast breaks.",
    ["style.press"] = "Pressing",
    ["style.press.description"] = "Win the ball high; consumes stamina and leaves space behind.",
    ["style.pressing"] = "Pressing",
    ["style.pressing.desc"] = "Win the ball high; consumes stamina and leaves space behind.",
    ["style.wings"] = "Wing play",
    ["style.wings.desc"] = "Wide outlets and crosses; fewer central passing options.",
    ["style.wings.description"] = "Wide outlets and crosses; fewer central passing options.",
    ["team.auto"] = "Choose strongest available XI",
    ["team.autoHelp"] = "Uses role attributes, position eligibility and fitness. Review before confirming transfers.",
    ["team.preset"] = "Free tactic preset {index}",
    ["team.presetHelp"] = "1: 4-3-3 possession; 2: 4-4-2 counter; 3: 5-3-2 low block. Review player roles after changing formation.",
    ["team.roles"] = "Assign roles to the selected starting slot. Sent-off or substituted takers are replaced by an eligible teammate.",
    ["team.technicalForfeit"] = "A 0–3 defeat advances the calendar and serves suspensions. No income, goals, assists or XP; ordinary wages remain due.",
    ["training.ended"] = "Practice ended",
    ["training.finishing"] = "Finishing challenge: 3 shots on target",
    ["training.fixed"] = "Fixed squad, normal difficulty, 90 seconds. First success: 25 cosmetic tokens. No repeat reward.",
    ["training.passing"] = "Passing challenge: 6 completed passes",
    ["training.pause"] = "Two tactical pauses per match, up to 30 seconds each. Substitutions require a stoppage.",
    ["training.practice"] = "Free practice",
    ["training.recovery"] = "Free recovery: {rate} fitness per game day. A paid session costs {price}, adds 20 fitness and reduces injury absence by one fixture. No XP; once per game date.",
    ["training.safe"] = "Practice never changes career dates, money, fitness or XP. Leave whenever you wish.",
    ["training.step1"] = "Move the footballer using your movement controls.",
    ["training.step2"] = "Complete a pass to a teammate.",
    ["training.step3"] = "Hold and release shoot to make a shot.",
    ["training.success"] = "Challenge complete",
    ["training.tutorial"] = "Interactive tutorial",
    ["trait.calm"] = "Calm",
    ["trait.leader"] = "Leader",
    ["trait.runner"] = "Runner",
    ["trait.technician"] = "Technician",
    ["ui.academy"] = "Academy",
    ["ui.achievements"] = "Achievements",
    ["ui.age"] = "Age",
    ["ui.all"] = "All",
    ["ui.annualCost"] = "Annual wage commitment",
    ["ui.appearance"] = "Appearance",
    ["ui.apply"] = "Apply",
    ["ui.assign"] = "Assign",
    ["ui.auto"] = "Automatic",
    ["ui.back"] = "Back",
    ["ui.business"] = "Club business",
    ["ui.buy"] = "Sign player",
    ["ui.buyout"] = "Exercise buy option",
    ["ui.calendar"] = "Calendar",
    ["ui.cancel"] = "Cancel",
    ["ui.captain"] = "Captain",
    ["ui.cards"] = "Cards",
    ["ui.career"] = "Career",
    ["ui.challenge"] = "Fixed challenge",
    ["ui.claim"] = "Claim reward",
    ["ui.close"] = "Close",
    ["ui.club"] = "Club",
    ["ui.clubBudget"] = "Club budget",
    ["ui.colorblind"] = "Distinct team colours",
    ["ui.compare"] = "Compare",
    ["ui.confirm"] = "Confirm",
    ["ui.confirmForfeit"] = "Forfeit 0–3? No match income, goals, assists or development will be awarded.",
    ["ui.confirmJob"] = "Join this club? Its budget and squad replace your current club; manager honours remain.",
    ["ui.confirmSell"] = "Sell this player? Check the squad and budget before confirming.",
    ["ui.continue"] = "Continue",
    ["ui.contract"] = "Contract",
    ["ui.controls"] = "Controls",
    ["ui.corner"] = "Corners",
    ["ui.cosmeticOnly"] = "Cosmetics only. Tokens never buy players, ratings or football money.",
    ["ui.crowd"] = "Crowd volume",
    ["ui.cup"] = "Cup",
    ["ui.date"] = "Football date",
    ["ui.debt"] = "Debt",
    ["ui.design"] = "Design",
    ["ui.details"] = "Details",
    ["ui.development"] = "Development",
    ["ui.difficulty"] = "Difficulty",
    ["ui.difficultyHelp"] = "Assisted: CPU attributes ×0.93. Standard: ×1. Expert: ×1.07. No hidden score adjustments; records are separate.",
    ["ui.division"] = "Division",
    ["ui.empty"] = "Nothing here yet.",
    ["ui.expenses"] = "Expenses",
    ["ui.favorite"] = "Favourite",
    ["ui.filter"] = "Filter",
    ["ui.finance"] = "Financial discipline",
    ["ui.financeForecast"] = "Season forecast",
    ["ui.finances"] = "Finances & sponsors",
    ["ui.fitness"] = "Fitness",
    ["ui.football"] = "Football",
    ["ui.forfeit"] = "Forfeit match",
    ["ui.formation"] = "Formation",
    ["ui.formations"] = "Formations",
    ["ui.freeAgent"] = "Free agent",
    ["ui.freeKick"] = "Free kicks",
    ["ui.goalkeeper"] = "Goalkeeper",
    ["ui.goals"] = "Objectives",
    ["ui.goalsPriority"] = "Board priority",
    ["ui.haptics"] = "Haptics",
    ["ui.help"] = "Help",
    ["ui.highlights"] = "Key moments",
    ["ui.history"] = "History & honours",
    ["ui.hub"] = "Club centre",
    ["ui.identity"] = "Club identity",
    ["ui.inbox"] = "Inbox",
    ["ui.income"] = "Income",
    ["ui.inventory"] = "Inventory",
    ["ui.job"] = "Manager offers",
    ["ui.language"] = "Language",
    ["ui.league"] = "League",
    ["ui.loading"] = "Loading your career…",
    ["ui.loan"] = "Loan",
    ["ui.loanOut"] = "Loan out",
    ["ui.market"] = "Transfers",
    ["ui.matchStats"] = "Match statistics",
    ["ui.mentality"] = "Mentality",
    ["ui.mode"] = "Match mode",
    ["ui.modeHighlights"] = "Key moments",
    ["ui.modeManual"] = "Full manual match",
    ["ui.modeSimulate"] = "Quick simulation",
    ["ui.music"] = "Music volume",
    ["ui.name"] = "Name",
    ["ui.negotiate"] = "Negotiate",
    ["ui.net"] = "Net cash flow",
    ["ui.networkTimeout"] = "The server did not respond. Retry to refresh your state.",
    ["ui.nextSeason"] = "Start next season",
    ["ui.none"] = "None",
    ["ui.off"] = "Off",
    ["ui.on"] = "On",
    ["ui.onTarget"] = "Shots on target",
    ["ui.owned"] = "Owned",
    ["ui.palette"] = "Palette",
    ["ui.pass"] = "Pass",
    ["ui.passes"] = "Pass completion",
    ["ui.passing"] = "Passing",
    ["ui.penalty"] = "Penalty",
    ["ui.performance"] = "Performance bonuses",
    ["ui.physical"] = "Physical",
    ["ui.play"] = "Play match",
    ["ui.played"] = "Played",
    ["ui.playerOfMatch"] = "Player of the match",
    ["ui.points"] = "Points",
    ["ui.position"] = "Position",
    ["ui.possession"] = "Possession",
    ["ui.potential"] = "Potential range",
    ["ui.practice"] = "Free practice",
    ["ui.pressKey"] = "Press a key for this action.",
    ["ui.price"] = "Price",
    ["ui.priceLoading"] = "Loading Roblox price…",
    ["ui.promote"] = "Promote to first team",
    ["ui.purchasesDisabled"] = "Product is not connected. Purchases are disabled.",
    ["ui.qualificationRules"] = "Top two qualify for Champions; third and cup winner for Challenge. Duplicate winners pass places down the league table.",
    ["ui.rating"] = "Rating",
    ["ui.recruit"] = "Recruit academy intake",
    ["ui.reducedMotion"] = "Reduce motion",
    ["ui.remap"] = "Remap keys",
    ["ui.rename"] = "Rename",
    ["ui.renew"] = "Renew contract",
    ["ui.replay"] = "Goal replay",
    ["ui.reputation"] = "Reputation",
    ["ui.rest"] = "Medical recovery",
    ["ui.restorePurchases"] = "Restore pass ownership",
    ["ui.result"] = "Match report",
    ["ui.retry"] = "Retry",
    ["ui.role"] = "Role",
    ["ui.save"] = "Save career",
    ["ui.saveHelp"] = "Critical changes save atomically. Studio uses a separate test store; temporary sessions do not persist.",
    ["ui.scout"] = "Scouting",
    ["ui.scoutPlayer"] = "Scout player",
    ["ui.search"] = "Search",
    ["ui.season"] = "Season",
    ["ui.selected"] = "Selected",
    ["ui.sell"] = "Sell player",
    ["ui.settings"] = "Settings",
    ["ui.sfx"] = "Effects volume",
    ["ui.shake"] = "Camera shake",
    ["ui.shape"] = "Shape",
    ["ui.shoot"] = "Shoot",
    ["ui.shooting"] = "Shooting",
    ["ui.shop"] = "Club shop",
    ["ui.shots"] = "Shots",
    ["ui.simulate"] = "Quick simulation",
    ["ui.skip"] = "Skip",
    ["ui.sort"] = "Sort",
    ["ui.sponsor"] = "Sponsor",
    ["ui.sprint"] = "Sprint",
    ["ui.squad"] = "Squad",
    ["ui.stable"] = "Stable income",
    ["ui.stadium"] = "Stadium",
    ["ui.staff"] = "Staff",
    ["ui.style"] = "Team style",
    ["ui.styles"] = "Team styles",
    ["ui.substitute"] = "Substitution",
    ["ui.swap"] = "Change player",
    ["ui.switch"] = "Switch player",
    ["ui.symbol"] = "Motif",
    ["ui.table"] = "Standings",
    ["ui.tackle"] = "Tackle",
    ["ui.tactics"] = "Tactics",
    ["ui.team"] = "Team",
    ["ui.textScale"] = "Text size",
    ["ui.through"] = "Through ball",
    ["ui.tokens"] = "Cosmetic tokens",
    ["ui.train"] = "Set training focus",
    ["ui.training"] = "Training & staff",
    ["ui.trainingHelp"] = "Training progresses on football dates. Opening this screen never grants development.",
    ["ui.transfer"] = "Transfer",
    ["ui.transferCost"] = "Total signing cost",
    ["ui.trophies"] = "Trophies",
    ["ui.tutorialDone"] = "Ready for your first match. You can replay this tutorial from Help.",
    ["ui.tutorialMove"] = "Move your player with the movement controls.",
    ["ui.tutorialPass"] = "Pass the ball to a teammate.",
    ["ui.tutorialShoot"] = "Aim and shoot at the goal.",
    ["ui.tutorialSkip"] = "Skip tutorial",
    ["ui.tutorialStart"] = "Start tutorial",
    ["ui.unavailable"] = "Unavailable",
    ["ui.unknown"] = "Unknown",
    ["ui.upgrade"] = "Upgrade",
    ["ui.upkeep"] = "Weekly upkeep grows with staff and facilities.",
    ["ui.view"] = "View",
    ["ui.wage"] = "Wage",
    ["ui.wages"] = "Wages",
    ["ui.windowClosed"] = "Transfer window closed",
    ["ui.wins"] = "Wins",
    ["ui.youth"] = "Youth development",
  },
  ru = {
    ["ALREADY_NEGOTIATED"] = "Переговоры по этому предложению уже проведены.",
    ["ALREADY_OWNED"] = "Этот предмет уже в коллекции.",
    ["ALREADY_SCOUTED"] = "Скаутский отчёт уже готов.",
    ["COSMETIC_APPLIED"] = "Оформление применено к клубу.",
    ["COSMETIC_NOT_OWNED"] = "Этого оформления нет в коллекции.",
    ["COSMETIC_OWNED"] = "Предмет добавлен в коллекцию.",
    ["COSMETIC_UPDATED"] = "Коллекция оформления обновлена.",
    ["DUPLICATE_PLAYER"] = "Этот игрок уже в составе.",
    ["INSUFFICIENT_FUNDS"] = "Недостаточно бюджета клуба.",
    ["INVALID_AMOUNT"] = "Некорректная сумма.",
    ["KEEPER_REQUIRED"] = "Сохрани достаточно доступных вратарей.",
    ["LOAN_UNAVAILABLE"] = "Это действие с арендой недоступно.",
    ["LOCK_LOST"] = "Сервер потерял право записи профиля. Перезайди для защиты прогресса.",
    ["MIGRATION_FAILED"] = "Старую карьеру не удалось безопасно преобразовать. Исходные данные сохранены.",
    ["NEGOTIATION_COMPLETE"] = "Переговоры завершены. Полная стоимость сделки: {amount}.",
    ["NO_BUYER"] = "Сейчас нет заинтересованного клуба-покупателя.",
    ["NO_SESSION"] = "Нет активной сессии профиля. Перезайди и повтори.",
    ["OFFER_EXPIRED"] = "Срок предложения истёк по игровому календарю.",
    ["OFFER_UNAVAILABLE"] = "Это предложение больше недоступно.",
    ["OPERATION_FAILED"] = "Операция с профилем не выполнена. Повтори запрос.",
    ["OPERATION_REJECTED"] = "Операция с профилем отклонена.",
    ["PASSES_CURRENT"] = "Владение пропусками обновлено.",
    ["PASS_CHECK_FAILED"] = "Не удалось проверить пропуски. Повтори позже.",
    ["PASS_REQUIRED"] = "Для этого оформления нужен соответствующий пропуск.",
    ["PLAYER_IN_LINEUP"] = "Сначала убери игрока из стартового состава.",
    ["PLAYER_LOANED"] = "{name} арендован. Расходы на сделку: {amount}.",
    ["PLAYER_LOANED_OUT"] = "{name} отдан в аренду в {buyer}; выплата {amount}.",
    ["PLAYER_NOT_FOUND"] = "Игрок не найден.",
    ["PLAYER_NOT_OWNED"] = "Этот игрок принадлежит другому клубу.",
    ["PLAYER_SIGNED"] = "{name} подписан. Полная стоимость сделки: {amount}.",
    ["PLAYER_SOLD"] = "{name} продан. Доход от трансфера: {amount}.",
    ["PRODUCT_NOT_CONFIGURED"] = "Этот товар Roblox ещё не подключён.",
    ["PROFILE_INVALID"] = "Профиль не прошёл проверку. Сохранённые данные не сброшены.",
    ["PROFILE_LOCKED_OR_INVALID"] = "Карьера открыта в другой сессии или требует проверки. Зайди позже.",
    ["PROFILE_STALE"] = "Профиль изменился. Обнови данные и повтори.",
    ["PURCHASE_PROMPT"] = "Заверши или отмени покупку в окне Roblox.",
    ["PURCHASE_UNAVAILABLE"] = "Не удалось открыть окно покупки Roblox.",
    ["RESALE_HOLD"] = "Недавно подписанных игроков нельзя сразу продать.",
    ["ROSTER_FULL"] = "Достигнут лимит контрактов основного состава.",
    ["SAVED"] = "Карьера сохранена.",
    ["SCOUT_COMPLETE"] = "Готов скаутский отчёт об игроке {name}.",
    ["SESSION_EXISTS"] = "Эта сессия профиля уже открыта.",
    ["SHOP_ACTION_INVALID"] = "Это действие в магазине недоступно.",
    ["SHOP_ITEM_INVALID"] = "Товар не найден.",
    ["SHOP_UNAVAILABLE"] = "Магазин клуба временно недоступен.",
    ["SQUAD_DEPTH_REQUIRED"] = "Сохрани достаточно игроков для допустимого состава.",
    ["STORE_BUSY"] = "Операция с профилем уже выполняется.",
    ["STORE_THROTTLED"] = "Сервис сохранений перегружен. Повтори позже.",
    ["STORE_UNAVAILABLE"] = "Хранилище временно недоступно. Повтори позже.",
    ["STUDIO_PURCHASE_DISABLED"] = "Реальные покупки отключены в Studio. Используй отдельный тестовый адаптер.",
    ["TEST_SESSION"] = "Тестовая сессия Studio: основные данные не используются.",
    ["TOKENS_REQUIRED"] = "Недостаточно косметических жетонов.",
    ["TOKEN_LIMIT"] = "Достигнут лимит косметических жетонов.",
    ["TRANSFER_WINDOW_CLOSED"] = "Трансферное окно закрыто.",
    ["WAGE_RESERVE_REQUIRED"] = "Сохрани резерв на зарплаты состава.",
    ["achievement.academy"] = "Два выпускника академии",
    ["achievement.firstWin"] = "Первая победа",
    ["achievement.promotion"] = "Повышение",
    ["achievement.tenWins"] = "Десять побед",
    ["attribute.defending"] = "Защита",
    ["attribute.dribbling"] = "Дриблинг",
    ["attribute.foot"] = "Ведущая нога",
    ["attribute.form"] = "Форма",
    ["attribute.goalkeeping"] = "Вратарское мастерство",
    ["attribute.handling"] = "Игра руками",
    ["attribute.morale"] = "Мораль",
    ["attribute.pace"] = "Скорость",
    ["attribute.passing"] = "Пас",
    ["attribute.physical"] = "Физика",
    ["attribute.positioning"] = "Выбор позиции",
    ["attribute.reflexes"] = "Реакция",
    ["attribute.shooting"] = "Удар",
    ["attribute.stamina"] = "Выносливость",
    ["board.missed"] = "Цель правления прошлого сезона не выполнена. Карьера продолжается.",
    ["board.reward"] = "Цель правления выполнена: +20 косметических жетонов.",
    ["bracket.bye"] = "Посев: пропуск раунда {round}",
    ["bracket.round"] = "Раунд {round}",
    ["bracket.winner"] = "Победитель: {club}",
    ["club.designHelp"] = "Палитра {palette}; герб {shape}; мотив {symbol}. Изменения только косметические.",
    ["club.identity"] = "Оформление клуба",
    ["club.identityHelp"] = "Название, две палитры и две формы герба бесплатны. Club Identity открывает дополнительные безопасные элементы.",
    ["club.rename"] = "Название клуба",
    ["club.renameHelp"] = "2–24 символа. Roblox фильтрует название перед сохранением. Одна успешная смена в минуту.",
    ["code.ACADEMY_ALREADY_RECRUITED"] = "Набор академии в этом сезоне уже проведён.",
    ["code.ACADEMY_FULL"] = "В академии шесть игроков. Сначала повысьте или отпустите одного.",
    ["code.CONTRACT_NOT_DUE"] = "Контракт уже действует ещё минимум три сезона.",
    ["code.GOAL_LOCKED"] = "Приоритет правления выбирается в первые три тура.",
    ["code.JOB_CONTRACT_ACTIVE"] = "Трёхлетний контракт тренера ещё действует. Предложения появятся в начале сезона после его завершения.",
    ["code.JOB_WINDOW_CLOSED"] = "Назначение в другой клуб доступно только в начале нового сезона.",
    ["code.KEEPER_REQUIRED"] = "Сохраните доступных вратарей; первый слот должен занимать вратарь.",
    ["code.MAX_LEVEL"] = "Достигнут максимальный уровень улучшения.",
    ["code.NAME_COOLDOWN"] = "Между успешными сменами названия нужна одна минута.",
    ["code.NAME_FILTER_UNAVAILABLE"] = "Фильтрация Roblox недоступна. Название не изменено. Повторите позже.",
    ["code.NAME_INVALID"] = "Используйте 2–24 допустимых символа без переносов строк и управляющих кодов.",
    ["code.NAME_IN_USE"] = "Такое название уже есть у другого клуба.",
    ["code.NAME_REJECTED"] = "Выберите другое название, которое пропустит фильтр Roblox.",
    ["code.NO_BUYER"] = "Сейчас ни один NPC-клуб не заинтересован в этом игроке.",
    ["code.NO_REWARD"] = "Неполученных наград за достижения нет.",
    ["code.OFFER_EXPIRED"] = "Срок предложения истёк по игровому календарю.",
    ["code.OFFER_UNAVAILABLE"] = "Предложение уже недоступно; обновите рынок.",
    ["code.PASS_REQUIRED"] = "Для этого элемента требуется Club Identity. Две палитры и две базовые формы герба бесплатны.",
    ["code.PLAYER_IN_LINEUP"] = "Перед продажей уберите игрока из стартового состава.",
    ["code.PLAYER_UNAVAILABLE"] = "Игрок травмирован, дисквалифицирован или недоступен для регистрации.",
    ["code.RECOVERY_ALREADY_USED"] = "Восстановление на эту игровую дату уже использовано.",
    ["code.RECOVERY_NOT_NEEDED"] = "До следующего матча достаточно календарного восстановления; платная процедура не нужна.",
    ["code.REPUTATION_REQUIRED"] = "Репутации недостаточно для назначения в этот клуб.",
    ["code.RESALE_HOLD"] = "Новичка можно продать после 56 игровых дней регистрации.",
    ["code.RESTRUCTURE_USED"] = "Реструктуризация доступна раз за сезон и уже использована.",
    ["code.ROSTER_FULL"] = "В клубе уже 30 основных контрактов. Перед подписанием продайте резервиста.",
    ["code.SCOUT_REGION_LOCKED"] = "Региональную специализацию можно менять один раз за сезон.",
    ["code.SEASON_COMPLETE"] = "Все встречи завершены. Начните следующий сезон в центре клуба.",
    ["code.SEASON_NOT_COMPLETE"] = "Сначала завершите оставшиеся встречи календаря.",
    ["code.SPONSOR_LOCKED"] = "Спонсора можно менять один раз за сезон.",
    ["code.SQUAD_DEPTH_REQUIRED"] = "Для продажи нужно сохранить минимум 16 игроков.",
    ["code.SQUAD_UNAVAILABLE"] = "Нужны 11 доступных игроков. Измените состав, используйте восстановление или примите техническое поражение для отбытия дисквалификаций.",
    ["code.TRANSFER_WINDOW_CLOSED"] = "Трансферное окно закрыто. Следующее открытие указано в календаре.",
    ["code.WAGE_RESERVE_REQUIRED"] = "Для подписания нужен запас денег на четыре недельные зарплаты игрока.",
    ["competition.cup"] = "Кубок",
    ["competition.friendly"] = "Товарищеский матч",
    ["competition.international"] = "Международный кубок",
    ["competition.league"] = "Лига",
    ["competition.supercup"] = "Суперкубок",
    ["crest.diamond"] = "Ромб",
    ["crest.round"] = "Круг",
    ["crest.shield"] = "Щит",
    ["crest.star"] = "Звезда",
    ["difficulty.easy"] = "С поддержкой",
    ["difficulty.hard"] = "Экспертная",
    ["difficulty.normal"] = "Стандартная",
    ["error.alreadyClaimed"] = "Награда уже получена.",
    ["error.invalid"] = "Некорректный запрос.",
    ["error.loan"] = "Арендованного игрока нельзя продать.",
    ["error.lockLost"] = "Право записи профиля потеряно. Перезайди, чтобы защитить прогресс.",
    ["error.matchActive"] = "Сначала закончи текущий матч.",
    ["error.money"] = "Недостаточно бюджета клуба.",
    ["error.noTokens"] = "Недостаточно косметических жетонов.",
    ["error.notOwned"] = "Этого предмета нет в коллекции.",
    ["error.player"] = "Игрок не найден.",
    ["error.productDisabled"] = "Этот товар ещё не подключён к Roblox.",
    ["error.rateLimited"] = "Слишком много запросов. Немного подожди и повтори.",
    ["error.receiptPending"] = "Выдача покупки ожидается. Roblox повторит её автоматически.",
    ["error.resale"] = "Игрока нельзя перепродать сразу после подписания.",
    ["error.roster"] = "После действия состав станет недопустимым.",
    ["error.save"] = "Сохранение временно недоступно. Повтори позже.",
    ["error.seasonIncomplete"] = "Сначала заверши запланированные игровые даты.",
    ["error.server"] = "Операция не выполнена. Сохранённая карьера не сброшена.",
    ["error.unavailable"] = "Сейчас действие недоступно.",
    ["error.windowClosed"] = "Трансферное окно закрыто.",
    ["event.academy"] = "{name} зачислен в академию.",
    ["event.academy_released"] = "Игрок академии отпущен: {name}.",
    ["event.achievement"] = "Получено достижение: {name}.",
    ["event.contract_expired"] = "Контракт игрока {name} истёк.",
    ["event.derby"] = "Результат дерби: {club} {home}:{away} {opponent}.",
    ["event.emergency_registration"] = "Экстренная регистрация: {name}.",
    ["event.goal_complete"] = "Сезон {season}: цель правления выполнена, +20 косметических жетонов.",
    ["event.legacy_completed"] = "Старый сезон завершён.",
    ["event.loan_returned"] = "Аренда завершена: {name}.",
    ["event.manager_renewed"] = "Контракт тренера продлён до конца сезона {season}.",
    ["event.match_pen_loss"] = "{club} {home}:{away} {opponent}: поражение по пенальти.",
    ["event.match_pen_win"] = "{club} {home}:{away} {opponent}: победа по пенальти.",
    ["event.match_result"] = "{club} {home}:{away} {opponent}",
    ["event.migrated"] = "Предыдущая карьера сохранена.",
    ["event.promotion"] = "Клуб будет играть в дивизионе {division}.",
    ["event.retired"] = "{name} завершил футбольную карьеру.",
    ["event.retirement_warning"] = "Приближается завершение карьеры: {name}.",
    ["event.season"] = "Сезон {season}: место {place}; призовые {prize}.",
    ["event.transfer"] = "Трансфер: {name}, сумма {amount}.",
    ["event.welcome"] = "Добро пожаловать в {club}, дивизион {division}.",
    ["facility.academy"] = "Инфраструктура академии",
    ["facility.medical"] = "Медицинский центр",
    ["facility.stadium"] = "Стадион",
    ["facility.training"] = "Тренировочный центр",
    ["finance.broadcast"] = "Доход от трансляций лиги",
    ["finance.confirmUpgrade"] = "Разовая стоимость: {price}. Дополнительное недельное содержание: {upkeep}. Подтвердить расход бюджета?",
    ["foot.left"] = "Левая",
    ["foot.right"] = "Правая",
    ["format.age"] = "Возраст: {age}",
    ["format.contract"] = "Контракт до сезона {season}",
    ["format.cost"] = "Трансфер {fee}; подписной бонус {bonus}; агент {agent}; зарплата за год {wage}",
    ["format.date"] = "Сезон {season}, день {day}",
    ["format.division"] = "Дивизион {division}",
    ["format.expiry"] = "Действует до дня {day}",
    ["format.fixture"] = "{home} — {away}",
    ["format.level"] = "Уровень {level}",
    ["format.money"] = "{amount} кр.",
    ["format.players.few"] = "{count} игрока",
    ["format.players.many"] = "{count} игроков",
    ["format.players.one"] = "{count} игрок",
    ["format.players.other"] = "{count} игроков",
    ["format.score"] = "{home} {goalsHome}:{goalsAway} {away}",
    ["format.season"] = "Сезон {season}",
    ["goal.claimed"] = "Награда получена",
    ["goal.finance.description"] = "Завершите сезон без долгов, с деньгами не меньше стартового баланса и без технических поражений. Награда: 20 косметических жетонов.",
    ["goal.league.description"] = "Завершите сезон в первой восьмёрке, не более двух технических поражений. Награда: 20 косметических жетонов.",
    ["goal.unclaimed"] = "Награда доступна — нажмите «Получить»",
    ["goal.youth.description"] = "Повысьте двух воспитанников за сезон, не более двух технических поражений. Награда: 20 косметических жетонов.",
    ["language.de"] = "Deutsch",
    ["language.en"] = "English",
    ["language.es"] = "Español",
    ["language.fr"] = "Français",
    ["language.ja"] = "日本語",
    ["language.ko"] = "한국어",
    ["language.pl"] = "Polski",
    ["language.pt-br"] = "Português (Brasil)",
    ["language.qps-ploc"] = "Псевдоперевод (+50%)",
    ["language.ru"] = "Русский",
    ["language.tr"] = "Türkçe",
    ["language.uk"] = "Українська",
    ["loan.confirm"] = "{name}: аренда до конца текущего сезона. Ваш клуб платит половину зарплаты и получает 12% стоимости игрока. Досрочного отзыва нет. Требуется согласие клуба NPC.",
    ["loan.outStatus"] = "В аренде в {club} до конца сезона {season}; матчей: {played}",
    ["market.filter.affordable"] = "Доступная цена",
    ["market.filter.all"] = "Все игроки",
    ["market.filter.contract"] = "Контракт: до двух сезонов",
    ["market.filter.favorite"] = "Избранное",
    ["market.filter.free"] = "Свободные агенты",
    ["market.filter.strong"] = "Рейтинг 60+",
    ["market.filter.wage"] = "Невысокая зарплата",
    ["market.filter.young"] = "Возраст до 21",
    ["market.filterHelp"] = "Фильтры: возраст ≤21, рейтинг ≥60, цена ≤половины бюджета, зарплата ниже средней, свободные агенты, избранное.",
    ["market.impact"] = "Ожидаемый прирост силы состава: {gain}. Результат не гарантирован.",
    ["match.away"] = "В гостях",
    ["match.corner"] = "Угловой",
    ["match.ended"] = "Матч завершён",
    ["match.extraTime"] = "Дополнительное время",
    ["match.forfeit"] = "Техническое поражение 0:3; без дохода и развития.",
    ["match.foul"] = "Нарушение",
    ["match.freeKick"] = "Штрафной",
    ["match.fulltime"] = "Матч завершён",
    ["match.goal"] = "Гол!",
    ["match.goalKick"] = "Удар от ворот",
    ["match.goalkeeperRequired"] = "Оставь доступного вратаря на поле.",
    ["match.halftime"] = "Перерыв: измени тактику и сделай замены.",
    ["match.highlights"] = "Ключевые моменты",
    ["match.home"] = "Дома",
    ["match.injury"] = "Травма",
    ["match.interception"] = "Перехват",
    ["match.kickoff"] = "Начало матча",
    ["match.manual"] = "Вручную",
    ["match.offside"] = "Офсайд",
    ["match.opponentGoal"] = "Гол соперника",
    ["match.pauseLimit"] = "Обе тактические паузы использованы.",
    ["match.penalties"] = "Серия пенальти",
    ["match.penalty"] = "Пенальти",
    ["match.penaltyGoal"] = "Пенальти забит",
    ["match.penaltyMiss"] = "Промах с пенальти",
    ["match.penaltySave"] = "Пенальти отражён",
    ["match.penaltySaved"] = "Пенальти отражён",
    ["match.playerUnavailable"] = "Этот игрок недоступен.",
    ["match.red"] = "Красная карточка — игрок удалён",
    ["match.redCard"] = "Красная карточка — игрок удалён",
    ["match.save"] = "Сейв вратаря",
    ["match.simulate"] = "Симуляция",
    ["match.substitution"] = "Замена",
    ["match.substitutionUnavailable"] = "Сейчас замена недоступна.",
    ["match.technicalDefeat"] = "Слишком много удалений: техническое поражение.",
    ["match.throwIn"] = "Аут",
    ["match.yellow"] = "Жёлтая карточка",
    ["match.yellowCard"] = "Жёлтая карточка",
    ["mentality.attack"] = "Атака",
    ["mentality.balanced"] = "Баланс",
    ["mentality.defend"] = "Оборона",
    ["player.details"] = "Страна: {country}. Нога: {foot}. Черты: {traits}.",
    ["player.formMorale"] = "Форма: {form}; мораль: {morale}.",
    ["player.historyRow"] = "Сезон {season}: возраст {age}, рейтинг {rating}, голы {goals}, передачи {assists}",
    ["position.DEF"] = "Защитник",
    ["position.FWD"] = "Нападающий",
    ["position.GK"] = "Вратарь",
    ["position.MID"] = "Полузащитник",
    ["records.rules"] = "3 очка за победу, 1 за ничью. Отдельные категории режима и сложности. Обновление не чаще раза в 120 секунд.",
    ["records.title"] = "Глобальные рекорды карьеры",
    ["report.away"] = "Преимущество домашнего поля было у соперника.",
    ["report.back"] = "Назад к отчёту",
    ["report.dismissal"] = "Ваша команда играла с удалением.",
    ["report.factors"] = "Факторы матча",
    ["report.fewerShots"] = "У соперника больше ударов в створ.",
    ["report.home"] = "Учтено преимущество домашнего поля.",
    ["report.moreShots"] = "У вашей команды не меньше ударов в створ.",
    ["report.neutral"] = "Нейтральное поле: домашнего преимущества нет; билеты делятся поровну.",
    ["report.onTarget"] = "Удары в створ",
    ["report.passAccuracy"] = "Точность пасов %",
    ["report.possessionPercent"] = "Владение %",
    ["report.ratings"] = "Оценки игроков",
    ["report.red"] = "Красные карточки",
    ["report.shootout"] = "Пенальти: {home}:{away}.",
    ["report.shots"] = "Удары",
    ["report.technical"] = "Административный счёт 3:0; индивидуальные голы и ассисты не начисляются.",
    ["report.yellow"] = "Жёлтые карточки",
    ["scout.report"] = "Скаутский отчёт: {country}, игровой день {day}, стоимость {fee}.",
    ["scout.specialism"] = "Выберите регион один раз за сезон. Отчёты там дешевле на 25% и сужают потенциал до ±1 вместо ±2.",
    ["shop.badge_desc"] = "Косметический значок поддержки разработки.",
    ["shop.broadcast"] = "Broadcast Studio",
    ["shop.broadcast.classic"] = "Классическая трансляция",
    ["shop.broadcastStudio"] = "Broadcast Studio",
    ["shop.broadcast_cosmetic"] = "Меняет акцентный цвет табло матча. Только оформление.",
    ["shop.broadcast_desc"] = "Цвета трансляции и оформление табло. Управление остаётся прежним.",
    ["shop.broadcast_pro"] = "Синяя трансляция",
    ["shop.classic"] = "Классическая клубная форма",
    ["shop.clean"] = "Лаконичная трансляция",
    ["shop.clubIdentity"] = "Club Identity",
    ["shop.crest.shield"] = "Герб-щит",
    ["shop.crest_desc"] = "Безопасный оригинальный элемент герба клуба.",
    ["shop.crest_star"] = "Звёздный герб",
    ["shop.customization"] = "Оформление",
    ["shop.designer"] = "Дизайнерские прожекторы",
    ["shop.donation_desc"] = "Добровольная повторяемая поддержка. Без игровых наград и преимуществ.",
    ["shop.donation_l"] = "Большой взнос",
    ["shop.donation_m"] = "Средний взнос",
    ["shop.donation_s"] = "Небольшой взнос",
    ["shop.hoops"] = "Небесные кольца",
    ["shop.identity"] = "Club Identity",
    ["shop.identity_desc"] = "Дополнительные узоры формы, палитры и элементы герба. Только оформление.",
    ["shop.kit.classic"] = "Классическая форма",
    ["shop.kit.lime"] = "Лаймовая форма",
    ["shop.kit.navy"] = "Тёмно-синяя форма",
    ["shop.kit_desc"] = "Посмотри цвета и узор, затем примени их к команде.",
    ["shop.lime"] = "Лаймовые полосы",
    ["shop.night"] = "Ночная атмосфера",
    ["shop.passDescription"] = "Постоянный доступ к оформлению. Футбольное развитие остаётся бесплатным.",
    ["shop.passes"] = "Пропуски",
    ["shop.prompt"] = "Подтвердите или отмените покупку в окне Roblox. Выдача произойдёт только после проверки квитанции.",
    ["shop.requires"] = "Требуется {pass}",
    ["shop.stadium"] = "Stadium Designer",
    ["shop.stadium.classic"] = "Классические трибуны",
    ["shop.stadiumDesigner"] = "Stadium Designer",
    ["shop.stadium_cosmetic"] = "Меняет видимую атмосферу поля в матче. Только оформление.",
    ["shop.stadium_desc"] = "Оформление поля и освещения. Без прибавки к домашнему преимуществу.",
    ["shop.sunset"] = "Закатная перевязь",
    ["shop.support"] = "Поддержать разработку",
    ["shop.supportDescription"] = "Добровольный взнос. Не даёт преимуществ в футболе.",
    ["shop.supporter"] = "Supporter",
    ["shop.supporter_badge"] = "Значок сторонника",
    ["shop.supporter_desc"] = "Значок сторонника и коллекция оформления. Без футбольных преимуществ.",
    ["shop.tokens"] = "Жетоны",
    ["shop.tokensDescription"] = "Жетоны нужны только для оформления. Их нельзя обменять на игроков, бюджет или результаты.",
    ["shop.tokensLarge"] = "800 косметических жетонов",
    ["shop.tokensMedium"] = "300 косметических жетонов",
    ["shop.tokensSmall"] = "100 косметических жетонов",
    ["shop.tokens_l"] = "800 косметических жетонов",
    ["shop.tokens_m"] = "300 косметических жетонов",
    ["shop.tokens_only"] = "Только на оформление клуба. Нельзя купить игроков или результаты матчей.",
    ["shop.tokens_s"] = "100 косметических жетонов",
    ["sponsor.performance.description"] = "3 000 за завершённый матч лиги и ещё 11 000 за победу. За техническое поражение выплат нет.",
    ["sponsor.stable.description"] = "8 000 за завершённый матч лиги независимо от счёта. За техническое поражение выплат нет.",
    ["staff.coach"] = "Тренер",
    ["staff.doctor"] = "Врач",
    ["staff.scout"] = "Скаут",
    ["status.LOAN_UNAVAILABLE"] = "Этого игрока сейчас нельзя отдать в аренду.",
    ["status.loaded"] = "Карьера загружена",
    ["status.saved"] = "Сохранено",
    ["status.saving"] = "Сохранение…",
    ["status.studio"] = "Тестовая среда Studio: данные отделены от основной игры.",
    ["status.success"] = "Выполнено",
    ["status.updated"] = "Обновлено",
    ["style.balanced"] = "Сбалансированный",
    ["style.counter"] = "Контратака",
    ["style.counter.desc"] = "Быстрые забегания после отбора; меньше контроля против глубокой обороны.",
    ["style.counter.description"] = "Быстрые забегания после отбора; меньше контроля против глубокой обороны.",
    ["style.lowblock"] = "Низкий блок",
    ["style.lowblock.desc"] = "Компактная оборона; меньше подключений и ударов.",
    ["style.lowblock.description"] = "Компактная оборона; меньше подключений и ударов.",
    ["style.possession"] = "Владение",
    ["style.possession.desc"] = "Поддержка и точные пасы; уязвимость к прессингу и быстрым контратакам.",
    ["style.possession.description"] = "Поддержка и точные пасы; уязвимость к прессингу и быстрым контратакам.",
    ["style.press"] = "Прессинг",
    ["style.press.description"] = "Отбор на чужой половине; расход выносливости и пространство за спиной.",
    ["style.pressing"] = "Прессинг",
    ["style.pressing.desc"] = "Отбор на чужой половине; расход выносливости и пространство за спиной.",
    ["style.wings"] = "Игра флангами",
    ["style.wings.desc"] = "Широкие открывания и подачи; меньше вариантов паса в центре.",
    ["style.wings.description"] = "Широкие открывания и подачи; меньше вариантов паса в центре.",
    ["team.auto"] = "Подобрать сильнейших доступных 11",
    ["team.autoHelp"] = "Учитывает характеристики роли, доступность позиции и выносливость. Проверяйте состав перед трансферами.",
    ["team.preset"] = "Бесплатный пресет тактики {index}",
    ["team.presetHelp"] = "1: 4-3-3 владение; 2: 4-4-2 контратака; 3: 5-3-2 низкий блок. После смены схемы проверьте позиции игроков.",
    ["team.roles"] = "Назначьте роли выбранному слоту состава. Удалённого или заменённого исполнителя заменит доступный партнёр.",
    ["team.technicalForfeit"] = "Поражение 0:3 продвинет календарь и срок дисквалификаций. Дохода, голов, ассистов и опыта нет; обычные зарплаты сохраняются.",
    ["training.ended"] = "Тренировка завершена",
    ["training.finishing"] = "Испытание: 3 удара в створ",
    ["training.fixed"] = "Фиксированный состав, обычная сложность, 90 секунд. Первый успех: 25 косметических жетонов. Повторной награды нет.",
    ["training.passing"] = "Испытание: 6 точных пасов",
    ["training.pause"] = "Две тактические паузы за матч, до 30 секунд каждая. Замены доступны при остановке.",
    ["training.practice"] = "Свободная тренировка",
    ["training.recovery"] = "Бесплатное восстановление: {rate} выносливости за игровой день. Процедура за {price} добавляет 20 и сокращает травму на одну встречу. Опыта нет; раз за игровую дату.",
    ["training.safe"] = "Тренировка не меняет даты карьеры, деньги, выносливость и опыт. Можно выйти в любой момент.",
    ["training.step1"] = "Передвиньте футболиста с помощью управления движением.",
    ["training.step2"] = "Выполните точный пас партнёру.",
    ["training.step3"] = "Удерживайте и отпустите кнопку удара.",
    ["training.success"] = "Задание выполнено",
    ["training.tutorial"] = "Интерактивное обучение",
    ["trait.calm"] = "Спокойный",
    ["trait.leader"] = "Лидер",
    ["trait.runner"] = "Бегунок",
    ["trait.technician"] = "Техничный",
    ["ui.academy"] = "Академия",
    ["ui.achievements"] = "Достижения",
    ["ui.age"] = "Возраст",
    ["ui.all"] = "Все",
    ["ui.annualCost"] = "Годовые расходы на зарплату",
    ["ui.appearance"] = "Оформление",
    ["ui.apply"] = "Применить",
    ["ui.assign"] = "Назначить",
    ["ui.auto"] = "Автоматически",
    ["ui.back"] = "Назад",
    ["ui.business"] = "Управление клубом",
    ["ui.buy"] = "Подписать",
    ["ui.buyout"] = "Выкупить",
    ["ui.calendar"] = "Календарь",
    ["ui.cancel"] = "Отмена",
    ["ui.captain"] = "Капитан",
    ["ui.cards"] = "Карточки",
    ["ui.career"] = "Карьера",
    ["ui.challenge"] = "Испытание",
    ["ui.claim"] = "Получить награду",
    ["ui.close"] = "Закрыть",
    ["ui.club"] = "Клуб",
    ["ui.clubBudget"] = "Бюджет клуба",
    ["ui.colorblind"] = "Различимые цвета команд",
    ["ui.compare"] = "Сравнить",
    ["ui.confirm"] = "Подтвердить",
    ["ui.confirmForfeit"] = "Сдаться со счётом 0:3? Доход, голы, передачи и развитие за матч не начисляются.",
    ["ui.confirmJob"] = "Возглавить этот клуб? Его бюджет и состав заменят текущий клуб; личные трофеи тренера сохранятся.",
    ["ui.confirmSell"] = "Продать игрока? Проверь состав и бюджет перед подтверждением.",
    ["ui.continue"] = "Продолжить",
    ["ui.contract"] = "Контракт",
    ["ui.controls"] = "Управление",
    ["ui.corner"] = "Угловые",
    ["ui.cosmeticOnly"] = "Только оформление. Жетоны не покупают игроков, рейтинг или футбольные деньги.",
    ["ui.crowd"] = "Громкость трибун",
    ["ui.cup"] = "Кубок",
    ["ui.date"] = "Игровая дата",
    ["ui.debt"] = "Долг",
    ["ui.design"] = "Оформить",
    ["ui.details"] = "Подробности",
    ["ui.development"] = "Развитие",
    ["ui.difficulty"] = "Сложность",
    ["ui.difficultyHelp"] = "С поддержкой: характеристики CPU ×0,93. Стандарт: ×1. Эксперт: ×1,07. Без скрытого изменения счёта; рекорды раздельные.",
    ["ui.division"] = "Дивизион",
    ["ui.empty"] = "Пока ничего нет.",
    ["ui.expenses"] = "Расходы",
    ["ui.favorite"] = "В избранное",
    ["ui.filter"] = "Фильтр",
    ["ui.finance"] = "Финансовая дисциплина",
    ["ui.financeForecast"] = "Прогноз на сезон",
    ["ui.finances"] = "Финансы и спонсоры",
    ["ui.fitness"] = "Готовность",
    ["ui.football"] = "Футбол",
    ["ui.forfeit"] = "Сдаться",
    ["ui.formation"] = "Схема",
    ["ui.formations"] = "Схемы",
    ["ui.freeAgent"] = "Свободный агент",
    ["ui.freeKick"] = "Штрафные",
    ["ui.goalkeeper"] = "Вратарь",
    ["ui.goals"] = "Цели",
    ["ui.goalsPriority"] = "Приоритет правления",
    ["ui.haptics"] = "Вибрация",
    ["ui.help"] = "Помощь",
    ["ui.highlights"] = "Ключевые моменты",
    ["ui.history"] = "История и награды",
    ["ui.hub"] = "Центр клуба",
    ["ui.identity"] = "Оформление клуба",
    ["ui.inbox"] = "Входящие",
    ["ui.income"] = "Доходы",
    ["ui.inventory"] = "Инвентарь",
    ["ui.job"] = "Предложения клубов",
    ["ui.language"] = "Язык",
    ["ui.league"] = "Лига",
    ["ui.loading"] = "Загрузка карьеры…",
    ["ui.loan"] = "Арендовать",
    ["ui.loanOut"] = "Отдать в аренду",
    ["ui.market"] = "Трансферы",
    ["ui.matchStats"] = "Статистика матча",
    ["ui.mentality"] = "Настрой",
    ["ui.mode"] = "Режим матча",
    ["ui.modeHighlights"] = "Ключевые моменты",
    ["ui.modeManual"] = "Ручной матч",
    ["ui.modeSimulate"] = "Быстрая симуляция",
    ["ui.music"] = "Громкость музыки",
    ["ui.name"] = "Имя",
    ["ui.negotiate"] = "Переговоры",
    ["ui.net"] = "Чистый денежный поток",
    ["ui.networkTimeout"] = "Сервер не ответил. Повтори запрос, чтобы обновить данные.",
    ["ui.nextSeason"] = "Начать следующий сезон",
    ["ui.none"] = "Нет",
    ["ui.off"] = "Выкл.",
    ["ui.on"] = "Вкл.",
    ["ui.onTarget"] = "Удары в створ",
    ["ui.owned"] = "В коллекции",
    ["ui.palette"] = "Палитра",
    ["ui.pass"] = "Пас",
    ["ui.passes"] = "Точность пасов",
    ["ui.passing"] = "Пас",
    ["ui.penalty"] = "Пенальти",
    ["ui.performance"] = "Бонусы за результаты",
    ["ui.physical"] = "Физика",
    ["ui.play"] = "Играть матч",
    ["ui.played"] = "Сыграно",
    ["ui.playerOfMatch"] = "Игрок матча",
    ["ui.points"] = "Очки",
    ["ui.position"] = "Позиция",
    ["ui.possession"] = "Владение",
    ["ui.potential"] = "Диапазон потенциала",
    ["ui.practice"] = "Свободная тренировка",
    ["ui.pressKey"] = "Нажми клавишу для этого действия.",
    ["ui.price"] = "Цена",
    ["ui.priceLoading"] = "Загрузка цены Roblox…",
    ["ui.promote"] = "Перевести в основу",
    ["ui.purchasesDisabled"] = "Товар не подключён. Покупки отключены.",
    ["ui.qualificationRules"] = "Первые два — Champions; третье место и победитель кубка — Challenge. При совпадении места передаются следующим клубам таблицы.",
    ["ui.rating"] = "Рейтинг",
    ["ui.recruit"] = "Набрать воспитанников",
    ["ui.reducedMotion"] = "Снизить анимации",
    ["ui.remap"] = "Переназначить клавиши",
    ["ui.rename"] = "Переименовать",
    ["ui.renew"] = "Продлить контракт",
    ["ui.replay"] = "Повтор гола",
    ["ui.reputation"] = "Репутация",
    ["ui.rest"] = "Медицинское восстановление",
    ["ui.restorePurchases"] = "Восстановить пропуски",
    ["ui.result"] = "Отчёт о матче",
    ["ui.retry"] = "Повторить",
    ["ui.role"] = "Роль",
    ["ui.save"] = "Сохранить карьеру",
    ["ui.saveHelp"] = "Критические изменения сохраняются атомарно. Studio использует тестовое хранилище; временные сессии не сохраняются.",
    ["ui.scout"] = "Скаутинг",
    ["ui.scoutPlayer"] = "Изучить игрока",
    ["ui.search"] = "Поиск",
    ["ui.season"] = "Сезон",
    ["ui.selected"] = "Выбрано",
    ["ui.sell"] = "Продать",
    ["ui.settings"] = "Настройки",
    ["ui.sfx"] = "Громкость эффектов",
    ["ui.shake"] = "Тряска камеры",
    ["ui.shape"] = "Форма",
    ["ui.shoot"] = "Удар",
    ["ui.shooting"] = "Удар",
    ["ui.shop"] = "Магазин клуба",
    ["ui.shots"] = "Удары",
    ["ui.simulate"] = "Быстрая симуляция",
    ["ui.skip"] = "Пропустить",
    ["ui.sort"] = "Сортировка",
    ["ui.sponsor"] = "Спонсор",
    ["ui.sprint"] = "Спринт",
    ["ui.squad"] = "Состав",
    ["ui.stable"] = "Стабильный доход",
    ["ui.stadium"] = "Стадион",
    ["ui.staff"] = "Персонал",
    ["ui.style"] = "Стиль команды",
    ["ui.styles"] = "Стили игры",
    ["ui.substitute"] = "Замена",
    ["ui.swap"] = "Заменить",
    ["ui.switch"] = "Сменить игрока",
    ["ui.symbol"] = "Мотив",
    ["ui.table"] = "Турнирная таблица",
    ["ui.tackle"] = "Отбор",
    ["ui.tactics"] = "Тактика",
    ["ui.team"] = "Команда",
    ["ui.textScale"] = "Размер текста",
    ["ui.through"] = "Пас на ход",
    ["ui.tokens"] = "Косметические жетоны",
    ["ui.train"] = "Выбрать тренировку",
    ["ui.training"] = "Тренировки и персонал",
    ["ui.trainingHelp"] = "Тренировки идут по игровому календарю. Открытие экрана не даёт развития.",
    ["ui.transfer"] = "Трансфер",
    ["ui.transferCost"] = "Полная стоимость сделки",
    ["ui.trophies"] = "Трофеи",
    ["ui.tutorialDone"] = "Ты готов к первому матчу. Обучение можно повторить в разделе «Помощь».",
    ["ui.tutorialMove"] = "Перемести игрока с помощью управления движением.",
    ["ui.tutorialPass"] = "Отдай пас партнёру.",
    ["ui.tutorialShoot"] = "Прицелься и пробей по воротам.",
    ["ui.tutorialSkip"] = "Пропустить обучение",
    ["ui.tutorialStart"] = "Пройти обучение",
    ["ui.unavailable"] = "Недоступно",
    ["ui.unknown"] = "Неизвестно",
    ["ui.upgrade"] = "Улучшить",
    ["ui.upkeep"] = "Недельное содержание растёт с уровнем персонала и инфраструктуры.",
    ["ui.view"] = "Открыть",
    ["ui.wage"] = "Зарплата",
    ["ui.wages"] = "Зарплаты",
    ["ui.windowClosed"] = "Трансферное окно закрыто",
    ["ui.wins"] = "Победы",
    ["ui.youth"] = "Развитие молодёжи",
  },
  uk = {
    ["ALREADY_NEGOTIATED"] = "Переговори щодо цієї пропозиції вже проведено.",
    ["ALREADY_OWNED"] = "Цей предмет уже в колекції.",
    ["ALREADY_SCOUTED"] = "Скаутський звіт уже готовий.",
    ["COSMETIC_APPLIED"] = "Оформлення застосовано до клубу.",
    ["COSMETIC_NOT_OWNED"] = "Цього оформлення немає в колекції.",
    ["COSMETIC_OWNED"] = "Предмет додано до колекції.",
    ["COSMETIC_UPDATED"] = "Колекцію оформлення оновлено.",
    ["DUPLICATE_PLAYER"] = "Цей гравець уже у складі.",
    ["INSUFFICIENT_FUNDS"] = "Недостатньо бюджету клубу.",
    ["INVALID_AMOUNT"] = "Некоректна сума.",
    ["KEEPER_REQUIRED"] = "Збережи достатньо доступних воротарів.",
    ["LOAN_UNAVAILABLE"] = "Ця дія з орендою недоступна.",
    ["LOCK_LOST"] = "Сервер втратив право запису профілю. Зайди знову для захисту прогресу.",
    ["MIGRATION_FAILED"] = "Стару кар'єру не вдалося безпечно перетворити. Початкові дані збережено.",
    ["NEGOTIATION_COMPLETE"] = "Переговори завершено. Повна вартість угоди: {amount}.",
    ["NO_BUYER"] = "Зараз немає зацікавленого клубу-покупця.",
    ["NO_SESSION"] = "Немає активної сесії профілю. Зайди знову й повтори.",
    ["OFFER_EXPIRED"] = "Строк пропозиції сплив за ігровим календарем.",
    ["OFFER_UNAVAILABLE"] = "Ця пропозиція більше недоступна.",
    ["OPERATION_FAILED"] = "Операцію з профілем не виконано. Повтори запит.",
    ["OPERATION_REJECTED"] = "Операцію з профілем відхилено.",
    ["PASSES_CURRENT"] = "Володіння перепустками оновлено.",
    ["PASS_CHECK_FAILED"] = "Не вдалося перевірити перепустки. Повтори пізніше.",
    ["PASS_REQUIRED"] = "Для цього оформлення потрібна відповідна перепустка.",
    ["PLAYER_IN_LINEUP"] = "Спочатку прибери гравця зі стартового складу.",
    ["PLAYER_LOANED"] = "{name} орендований. Витрати на угоду: {amount}.",
    ["PLAYER_LOANED_OUT"] = "{name} відданий в оренду в {buyer}; виплата {amount}.",
    ["PLAYER_NOT_FOUND"] = "Гравця не знайдено.",
    ["PLAYER_NOT_OWNED"] = "Цей гравець належить іншому клубу.",
    ["PLAYER_SIGNED"] = "{name} підписаний. Повна вартість угоди: {amount}.",
    ["PLAYER_SOLD"] = "{name} проданий. Дохід від трансферу: {amount}.",
    ["PRODUCT_NOT_CONFIGURED"] = "Цей товар Roblox ще не підключено.",
    ["PROFILE_INVALID"] = "Профіль не пройшов перевірку. Збережені дані не скинуто.",
    ["PROFILE_LOCKED_OR_INVALID"] = "Кар'єра відкрита в іншій сесії або потребує перевірки. Зайди пізніше.",
    ["PROFILE_STALE"] = "Профіль змінився. Онови дані й повтори.",
    ["PURCHASE_PROMPT"] = "Заверши або скасуй покупку у вікні Roblox.",
    ["PURCHASE_UNAVAILABLE"] = "Не вдалося відкрити вікно покупки Roblox.",
    ["RESALE_HOLD"] = "Нещодавно підписаних гравців не можна одразу продати.",
    ["ROSTER_FULL"] = "Досягнуто ліміту контрактів основного складу.",
    ["SAVED"] = "Кар'єру збережено.",
    ["SCOUT_COMPLETE"] = "Готовий скаутський звіт про гравця {name}.",
    ["SESSION_EXISTS"] = "Ця сесія профілю вже відкрита.",
    ["SHOP_ACTION_INVALID"] = "Ця дія в магазині недоступна.",
    ["SHOP_ITEM_INVALID"] = "Товар не знайдено.",
    ["SHOP_UNAVAILABLE"] = "Магазин клубу тимчасово недоступний.",
    ["SQUAD_DEPTH_REQUIRED"] = "Збережи достатньо гравців для допустимого складу.",
    ["STORE_BUSY"] = "Операція з профілем уже виконується.",
    ["STORE_THROTTLED"] = "Сервіс збережень перевантажений. Повтори пізніше.",
    ["STORE_UNAVAILABLE"] = "Сховище тимчасово недоступне. Повтори пізніше.",
    ["STUDIO_PURCHASE_DISABLED"] = "Реальні покупки вимкнено у Studio. Використовуй окремий тестовий адаптер.",
    ["TEST_SESSION"] = "Тестова сесія Studio: основні дані не використовуються.",
    ["TOKENS_REQUIRED"] = "Недостатньо косметичних жетонів.",
    ["TOKEN_LIMIT"] = "Досягнуто ліміту косметичних жетонів.",
    ["TRANSFER_WINDOW_CLOSED"] = "Трансферне вікно закрито.",
    ["WAGE_RESERVE_REQUIRED"] = "Збережи резерв на зарплати складу.",
    ["achievement.academy"] = "Два випускники академії",
    ["achievement.firstWin"] = "Перша перемога",
    ["achievement.promotion"] = "Підвищення",
    ["achievement.tenWins"] = "Десять перемог",
    ["attribute.defending"] = "Захист",
    ["attribute.dribbling"] = "Дриблінг",
    ["attribute.foot"] = "Робоча нога",
    ["attribute.form"] = "Форма",
    ["attribute.goalkeeping"] = "Воротарська майстерність",
    ["attribute.handling"] = "Гра руками",
    ["attribute.morale"] = "Мораль",
    ["attribute.pace"] = "Швидкість",
    ["attribute.passing"] = "Пас",
    ["attribute.physical"] = "Фізика",
    ["attribute.positioning"] = "Вибір позиції",
    ["attribute.reflexes"] = "Реакція",
    ["attribute.shooting"] = "Удар",
    ["attribute.stamina"] = "Витривалість",
    ["board.missed"] = "Мету правління минулого сезону не виконано. Кар’єра триває.",
    ["board.reward"] = "Мету правління виконано: +20 косметичних жетонів.",
    ["bracket.bye"] = "Посів: пропуск раунду {round}",
    ["bracket.round"] = "Раунд {round}",
    ["bracket.winner"] = "Переможець: {club}",
    ["club.designHelp"] = "Палітра {palette}; герб {shape}; мотив {symbol}. Зміни лише косметичні.",
    ["club.identity"] = "Оформлення клубу",
    ["club.identityHelp"] = "Назва, дві палітри та дві форми герба безкоштовні. Club Identity відкриває додаткові безпечні елементи.",
    ["club.rename"] = "Назва клубу",
    ["club.renameHelp"] = "2–24 символи. Roblox фільтрує назву перед збереженням. Одна успішна зміна на хвилину.",
    ["code.ACADEMY_ALREADY_RECRUITED"] = "Набір академії в цьому сезоні вже проведено.",
    ["code.ACADEMY_FULL"] = "В академії шість гравців. Спочатку підвищте або відпустіть одного.",
    ["code.CONTRACT_NOT_DUE"] = "Контракт уже діє ще щонайменше три сезони.",
    ["code.GOAL_LOCKED"] = "Пріоритет правління обирається протягом перших трьох турів.",
    ["code.JOB_CONTRACT_ACTIVE"] = "Трирічний контракт тренера ще діє. Пропозиції з’являться на початку сезону після його завершення.",
    ["code.JOB_WINDOW_CLOSED"] = "Призначення до іншого клубу доступне лише на початку нового сезону.",
    ["code.KEEPER_REQUIRED"] = "Збережіть доступних воротарів; перший слот має займати воротар.",
    ["code.MAX_LEVEL"] = "Досягнуто максимального рівня поліпшення.",
    ["code.NAME_COOLDOWN"] = "Між успішними змінами назви потрібна одна хвилина.",
    ["code.NAME_FILTER_UNAVAILABLE"] = "Фільтрація Roblox недоступна. Назву не змінено. Спробуйте пізніше.",
    ["code.NAME_INVALID"] = "Використайте 2–24 допустимі символи без переносів рядків і керівних кодів.",
    ["code.NAME_IN_USE"] = "Така назва вже є в іншого клубу.",
    ["code.NAME_REJECTED"] = "Оберіть іншу назву, яку пропустить фільтр Roblox.",
    ["code.NO_BUYER"] = "Зараз жоден NPC-клуб не зацікавлений у цьому гравцеві.",
    ["code.NO_REWARD"] = "Неотриманих нагород за досягнення немає.",
    ["code.OFFER_EXPIRED"] = "Строк пропозиції минув за ігровим календарем.",
    ["code.OFFER_UNAVAILABLE"] = "Пропозиція вже недоступна; оновіть ринок.",
    ["code.PASS_REQUIRED"] = "Для цього елемента потрібен Club Identity. Дві палітри та дві базові форми герба безкоштовні.",
    ["code.PLAYER_IN_LINEUP"] = "Перед продажем приберіть гравця зі стартового складу.",
    ["code.PLAYER_UNAVAILABLE"] = "Гравець травмований, дискваліфікований або недоступний для реєстрації.",
    ["code.RECOVERY_ALREADY_USED"] = "Відновлення на цю ігрову дату вже використано.",
    ["code.RECOVERY_NOT_NEEDED"] = "До наступного матчу достатньо календарного відновлення; платна процедура не потрібна.",
    ["code.REPUTATION_REQUIRED"] = "Репутації недостатньо для призначення до цього клубу.",
    ["code.RESALE_HOLD"] = "Новачка можна продати після 56 ігрових днів реєстрації.",
    ["code.RESTRUCTURE_USED"] = "Реструктуризація доступна раз на сезон і вже використана.",
    ["code.ROSTER_FULL"] = "У клубі вже 30 основних контрактів. Перед підписанням продайте резервіста.",
    ["code.SCOUT_REGION_LOCKED"] = "Регіональну спеціалізацію можна змінювати один раз за сезон.",
    ["code.SEASON_COMPLETE"] = "Усі зустрічі завершено. Почніть наступний сезон у центрі клубу.",
    ["code.SEASON_NOT_COMPLETE"] = "Спочатку завершіть решту зустрічей календаря.",
    ["code.SPONSOR_LOCKED"] = "Спонсора можна змінювати один раз за сезон.",
    ["code.SQUAD_DEPTH_REQUIRED"] = "Для продажу потрібно зберегти щонайменше 16 гравців.",
    ["code.SQUAD_UNAVAILABLE"] = "Потрібні 11 доступних гравців. Змініть склад, використайте відновлення або прийміть технічну поразку для відбуття дискваліфікацій.",
    ["code.TRANSFER_WINDOW_CLOSED"] = "Трансферне вікно закрито. Наступне відкриття вказано в календарі.",
    ["code.WAGE_RESERVE_REQUIRED"] = "Для підписання потрібен запас грошей на чотири тижневі зарплати гравця.",
    ["competition.cup"] = "Кубок",
    ["competition.friendly"] = "Товариський матч",
    ["competition.international"] = "Міжнародний кубок",
    ["competition.league"] = "Ліга",
    ["competition.supercup"] = "Суперкубок",
    ["crest.diamond"] = "Ромб",
    ["crest.round"] = "Коло",
    ["crest.shield"] = "Щит",
    ["crest.star"] = "Зірка",
    ["difficulty.easy"] = "З підтримкою",
    ["difficulty.hard"] = "Експертна",
    ["difficulty.normal"] = "Стандартна",
    ["error.alreadyClaimed"] = "Нагороду вже отримано.",
    ["error.invalid"] = "Некоректний запит.",
    ["error.loan"] = "Орендованого гравця не можна продати.",
    ["error.lockLost"] = "Право запису профілю втрачено. Зайди знову, щоб захистити прогрес.",
    ["error.matchActive"] = "Спочатку заверши поточний матч.",
    ["error.money"] = "Недостатньо бюджету клубу.",
    ["error.noTokens"] = "Недостатньо косметичних жетонів.",
    ["error.notOwned"] = "Цього предмета немає в колекції.",
    ["error.player"] = "Гравця не знайдено.",
    ["error.productDisabled"] = "Цей товар ще не підключено до Roblox.",
    ["error.rateLimited"] = "Забагато запитів. Трохи зачекай і повтори.",
    ["error.receiptPending"] = "Видача покупки очікується. Roblox повторить її автоматично.",
    ["error.resale"] = "Гравця не можна перепродати одразу після підписання.",
    ["error.roster"] = "Після дії склад стане недопустимим.",
    ["error.save"] = "Збереження тимчасово недоступне. Повтори пізніше.",
    ["error.seasonIncomplete"] = "Спочатку заверши заплановані ігрові дати.",
    ["error.server"] = "Операцію не виконано. Збережену кар'єру не скинуто.",
    ["error.unavailable"] = "Зараз дія недоступна.",
    ["error.windowClosed"] = "Трансферне вікно закрито.",
    ["event.academy"] = "{name} зарахований до академії.",
    ["event.academy_released"] = "Гравця академії відпущено: {name}.",
    ["event.achievement"] = "Отримано досягнення: {name}.",
    ["event.contract_expired"] = "Контракт гравця {name} завершився.",
    ["event.derby"] = "Результат дербі: {club} {home}:{away} {opponent}.",
    ["event.emergency_registration"] = "Екстрена реєстрація: {name}.",
    ["event.goal_complete"] = "Сезон {season}: мету правління виконано, +20 косметичних жетонів.",
    ["event.legacy_completed"] = "Старий сезон завершено.",
    ["event.loan_returned"] = "Оренду завершено: {name}.",
    ["event.manager_renewed"] = "Контракт тренера продовжено до кінця сезону {season}.",
    ["event.match_pen_loss"] = "{club} {home}:{away} {opponent}: поразка за пенальті.",
    ["event.match_pen_win"] = "{club} {home}:{away} {opponent}: перемога за пенальті.",
    ["event.match_result"] = "{club} {home}:{away} {opponent}",
    ["event.migrated"] = "Попередню кар’єру збережено.",
    ["event.promotion"] = "Клуб гратиме в дивізіоні {division}.",
    ["event.retired"] = "{name} завершив футбольну кар'єру.",
    ["event.retirement_warning"] = "Наближається завершення кар’єри: {name}.",
    ["event.season"] = "Сезон {season}: місце {place}; призові {prize}.",
    ["event.transfer"] = "Трансфер: {name}, сума {amount}.",
    ["event.welcome"] = "Ласкаво просимо до {club}, дивізіон {division}.",
    ["facility.academy"] = "Інфраструктура академії",
    ["facility.medical"] = "Медичний центр",
    ["facility.stadium"] = "Стадіон",
    ["facility.training"] = "Тренувальний центр",
    ["finance.broadcast"] = "Дохід від трансляцій ліги",
    ["finance.confirmUpgrade"] = "Разова вартість: {price}. Додаткове тижневе утримання: {upkeep}. Підтвердити витрату бюджету?",
    ["foot.left"] = "Ліва",
    ["foot.right"] = "Права",
    ["format.age"] = "Вік: {age}",
    ["format.contract"] = "Контракт до сезону {season}",
    ["format.cost"] = "Трансфер {fee}; підписний бонус {bonus}; агент {agent}; зарплата за рік {wage}",
    ["format.date"] = "Сезон {season}, день {day}",
    ["format.division"] = "Дивізіон {division}",
    ["format.expiry"] = "Діє до дня {day}",
    ["format.fixture"] = "{home} — {away}",
    ["format.level"] = "Рівень {level}",
    ["format.money"] = "{amount} кр.",
    ["format.players.few"] = "{count} гравці",
    ["format.players.many"] = "{count} гравців",
    ["format.players.one"] = "{count} гравець",
    ["format.players.other"] = "{count} гравців",
    ["format.score"] = "{home} {goalsHome}:{goalsAway} {away}",
    ["format.season"] = "Сезон {season}",
    ["goal.claimed"] = "Нагороду отримано",
    ["goal.finance.description"] = "Завершіть сезон без боргів, із грошима не менше початкового балансу та без технічних поразок. Нагорода: 20 косметичних жетонів.",
    ["goal.league.description"] = "Завершіть сезон у першій вісімці, не більше двох технічних поразок. Нагорода: 20 косметичних жетонів.",
    ["goal.unclaimed"] = "Нагорода доступна — натисніть «Отримати»",
    ["goal.youth.description"] = "Підвищте двох вихованців за сезон, не більше двох технічних поразок. Нагорода: 20 косметичних жетонів.",
    ["language.de"] = "Deutsch",
    ["language.en"] = "English",
    ["language.es"] = "Español",
    ["language.fr"] = "Français",
    ["language.ja"] = "日本語",
    ["language.ko"] = "한국어",
    ["language.pl"] = "Polski",
    ["language.pt-br"] = "Português (Brasil)",
    ["language.qps-ploc"] = "Псевдопереклад (+50%)",
    ["language.ru"] = "Русский",
    ["language.tr"] = "Türkçe",
    ["language.uk"] = "Українська",
    ["loan.confirm"] = "{name}: оренда до кінця поточного сезону. Ваш клуб сплачує половину зарплати й отримує 12% вартості гравця. Дострокового відкликання немає. Потрібна згода клубу NPC.",
    ["loan.outStatus"] = "В оренді в {club} до кінця сезону {season}; матчів: {played}",
    ["market.filter.affordable"] = "Доступна ціна",
    ["market.filter.all"] = "Усі гравці",
    ["market.filter.contract"] = "Контракт: до двох сезонів",
    ["market.filter.favorite"] = "Обране",
    ["market.filter.free"] = "Вільні агенти",
    ["market.filter.strong"] = "Рейтинг 60+",
    ["market.filter.wage"] = "Невисока зарплата",
    ["market.filter.young"] = "Вік до 21",
    ["market.filterHelp"] = "Фільтри: вік ≤21, рейтинг ≥60, ціна ≤половини бюджету, зарплата нижча за середню, вільні агенти, обране.",
    ["market.impact"] = "Очікуваний приріст сили складу: {gain}. Результат не гарантовано.",
    ["match.away"] = "У гостях",
    ["match.corner"] = "Кутовий",
    ["match.ended"] = "Матч завершено",
    ["match.extraTime"] = "Додатковий час",
    ["match.forfeit"] = "Технічна поразка 0:3; без доходу та розвитку.",
    ["match.foul"] = "Порушення",
    ["match.freeKick"] = "Штрафний",
    ["match.fulltime"] = "Матч завершено",
    ["match.goal"] = "Гол!",
    ["match.goalKick"] = "Удар від воріт",
    ["match.goalkeeperRequired"] = "Залиш доступного воротаря на полі.",
    ["match.halftime"] = "Перерва: зміни тактику та зроби заміни.",
    ["match.highlights"] = "Ключові моменти",
    ["match.home"] = "Вдома",
    ["match.injury"] = "Травма",
    ["match.interception"] = "Перехоплення",
    ["match.kickoff"] = "Початок матчу",
    ["match.manual"] = "Вручну",
    ["match.offside"] = "Офсайд",
    ["match.opponentGoal"] = "Гол суперника",
    ["match.pauseLimit"] = "Обидві тактичні паузи використано.",
    ["match.penalties"] = "Серія пенальті",
    ["match.penalty"] = "Пенальті",
    ["match.penaltyGoal"] = "Пенальті забито",
    ["match.penaltyMiss"] = "Промах з пенальті",
    ["match.penaltySave"] = "Пенальті відбито",
    ["match.penaltySaved"] = "Пенальті відбито",
    ["match.playerUnavailable"] = "Цей гравець недоступний.",
    ["match.red"] = "Червона картка — гравця вилучено",
    ["match.redCard"] = "Червона картка — гравця вилучено",
    ["match.save"] = "Сейв воротаря",
    ["match.simulate"] = "Симуляція",
    ["match.substitution"] = "Заміна",
    ["match.substitutionUnavailable"] = "Зараз заміна недоступна.",
    ["match.technicalDefeat"] = "Забагато вилучень: технічна поразка.",
    ["match.throwIn"] = "Аут",
    ["match.yellow"] = "Жовта картка",
    ["match.yellowCard"] = "Жовта картка",
    ["mentality.attack"] = "Атака",
    ["mentality.balanced"] = "Баланс",
    ["mentality.defend"] = "Оборона",
    ["player.details"] = "Країна: {country}. Нога: {foot}. Риси: {traits}.",
    ["player.formMorale"] = "Форма: {form}; мораль: {morale}.",
    ["player.historyRow"] = "Сезон {season}: вік {age}, рейтинг {rating}, голи {goals}, передачі {assists}",
    ["position.DEF"] = "Захисник",
    ["position.FWD"] = "Нападник",
    ["position.GK"] = "Воротар",
    ["position.MID"] = "Півзахисник",
    ["records.rules"] = "3 очки за перемогу, 1 за нічию. Окремі категорії режиму й складності. Оновлення не частіше разу за 120 секунд.",
    ["records.title"] = "Глобальні рекорди кар’єри",
    ["report.away"] = "Перевага домашнього поля була в суперника.",
    ["report.back"] = "Назад до звіту",
    ["report.dismissal"] = "Ваша команда грала з вилученням.",
    ["report.factors"] = "Чинники матчу",
    ["report.fewerShots"] = "У суперника більше ударів у площину.",
    ["report.home"] = "Враховано перевагу домашнього поля.",
    ["report.moreShots"] = "У вашої команди не менше ударів у площину.",
    ["report.neutral"] = "Нейтральне поле: домашньої переваги немає; квитки діляться порівну.",
    ["report.onTarget"] = "Удари у площину",
    ["report.passAccuracy"] = "Точність пасів %",
    ["report.possessionPercent"] = "Володіння %",
    ["report.ratings"] = "Оцінки гравців",
    ["report.red"] = "Червоні картки",
    ["report.shootout"] = "Пенальті: {home}:{away}.",
    ["report.shots"] = "Удари",
    ["report.technical"] = "Адміністративний рахунок 3:0; індивідуальні голи й асисти не нараховуються.",
    ["report.yellow"] = "Жовті картки",
    ["scout.report"] = "Скаутський звіт: {country}, ігровий день {day}, вартість {fee}.",
    ["scout.specialism"] = "Оберіть регіон один раз за сезон. Звіти там дешевші на 25% і звужують потенціал до ±1 замість ±2.",
    ["shop.badge_desc"] = "Косметичний значок підтримки розробки.",
    ["shop.broadcast"] = "Broadcast Studio",
    ["shop.broadcast.classic"] = "Класична трансляція",
    ["shop.broadcastStudio"] = "Broadcast Studio",
    ["shop.broadcast_cosmetic"] = "Змінює акцентний колір табло матчу. Лише оформлення.",
    ["shop.broadcast_desc"] = "Кольори трансляції й оформлення табло. Керування залишається незмінним.",
    ["shop.broadcast_pro"] = "Синя трансляція",
    ["shop.classic"] = "Класична клубна форма",
    ["shop.clean"] = "Лаконічна трансляція",
    ["shop.clubIdentity"] = "Club Identity",
    ["shop.crest.shield"] = "Герб-щит",
    ["shop.crest_desc"] = "Безпечний оригінальний елемент герба клубу.",
    ["shop.crest_star"] = "Зоряний герб",
    ["shop.customization"] = "Оформлення",
    ["shop.designer"] = "Дизайнерські прожектори",
    ["shop.donation_desc"] = "Добровільна повторювана підтримка. Без ігрових нагород і переваг.",
    ["shop.donation_l"] = "Великий внесок",
    ["shop.donation_m"] = "Середній внесок",
    ["shop.donation_s"] = "Невеликий внесок",
    ["shop.hoops"] = "Небесні кільця",
    ["shop.identity"] = "Club Identity",
    ["shop.identity_desc"] = "Додаткові візерунки форми, палітри й елементи герба. Лише оформлення.",
    ["shop.kit.classic"] = "Класична форма",
    ["shop.kit.lime"] = "Лаймова форма",
    ["shop.kit.navy"] = "Темно-синя форма",
    ["shop.kit_desc"] = "Переглянь кольори й візерунок, потім застосуй їх до команди.",
    ["shop.lime"] = "Лаймові смуги",
    ["shop.night"] = "Нічна атмосфера",
    ["shop.passDescription"] = "Постійний доступ до оформлення. Футбольний розвиток залишається безкоштовним.",
    ["shop.passes"] = "Перепустки",
    ["shop.prompt"] = "Підтвердьте або скасуйте покупку у вікні Roblox. Видача відбудеться лише після перевірки квитанції.",
    ["shop.requires"] = "Потрібен {pass}",
    ["shop.stadium"] = "Stadium Designer",
    ["shop.stadium.classic"] = "Класичні трибуни",
    ["shop.stadiumDesigner"] = "Stadium Designer",
    ["shop.stadium_cosmetic"] = "Змінює видиму атмосферу поля в матчі. Лише оформлення.",
    ["shop.stadium_desc"] = "Оформлення поля та освітлення. Без збільшення домашньої переваги.",
    ["shop.sunset"] = "Західна перев'язь",
    ["shop.support"] = "Підтримати розробку",
    ["shop.supportDescription"] = "Добровільний внесок. Не дає переваг у футболі.",
    ["shop.supporter"] = "Supporter",
    ["shop.supporter_badge"] = "Значок прихильника",
    ["shop.supporter_desc"] = "Значок прихильника й колекція оформлення. Без футбольних переваг.",
    ["shop.tokens"] = "Жетони",
    ["shop.tokensDescription"] = "Жетони потрібні лише для оформлення. Їх не можна обміняти на гравців, бюджет чи результати.",
    ["shop.tokensLarge"] = "800 косметичних жетонів",
    ["shop.tokensMedium"] = "300 косметичних жетонів",
    ["shop.tokensSmall"] = "100 косметичних жетонів",
    ["shop.tokens_l"] = "800 косметичних жетонів",
    ["shop.tokens_m"] = "300 косметичних жетонів",
    ["shop.tokens_only"] = "Лише на оформлення клубу. Не можна купити гравців чи результати матчів.",
    ["shop.tokens_s"] = "100 косметичних жетонів",
    ["sponsor.performance.description"] = "3 000 за завершений матч ліги та ще 11 000 за перемогу. За технічну поразку виплат немає.",
    ["sponsor.stable.description"] = "8 000 за завершений матч ліги незалежно від рахунку. За технічну поразку виплат немає.",
    ["staff.coach"] = "Тренер",
    ["staff.doctor"] = "Лікар",
    ["staff.scout"] = "Скаут",
    ["status.LOAN_UNAVAILABLE"] = "Цього гравця зараз не можна віддати в оренду.",
    ["status.loaded"] = "Кар'єру завантажено",
    ["status.saved"] = "Збережено",
    ["status.saving"] = "Збереження…",
    ["status.studio"] = "Тестове середовище Studio: дані відокремлені від основної гри.",
    ["status.success"] = "Виконано",
    ["status.updated"] = "Оновлено",
    ["style.balanced"] = "Збалансований",
    ["style.counter"] = "Контратака",
    ["style.counter.desc"] = "Швидкі забігання після відбору; менше контролю проти глибокої оборони.",
    ["style.counter.description"] = "Швидкі забігання після відбору; менше контролю проти глибокої оборони.",
    ["style.lowblock"] = "Низький блок",
    ["style.lowblock.desc"] = "Компактна оборона; менше підключень та ударів.",
    ["style.lowblock.description"] = "Компактна оборона; менше підключень та ударів.",
    ["style.possession"] = "Володіння",
    ["style.possession.desc"] = "Підтримка й точні паси; вразливість до пресингу та швидких контратак.",
    ["style.possession.description"] = "Підтримка й точні паси; вразливість до пресингу та швидких контратак.",
    ["style.press"] = "Пресинг",
    ["style.press.description"] = "Відбір на чужій половині; витрати витривалості та простір за спиною.",
    ["style.pressing"] = "Пресинг",
    ["style.pressing.desc"] = "Відбір на чужій половині; витрати витривалості та простір за спиною.",
    ["style.wings"] = "Гра флангами",
    ["style.wings.desc"] = "Широкі відкривання й подачі; менше варіантів пасу в центрі.",
    ["style.wings.description"] = "Широкі відкривання й подачі; менше варіантів пасу в центрі.",
    ["team.auto"] = "Підібрати найсильніших доступних 11",
    ["team.autoHelp"] = "Враховує характеристики ролі, доступність позиції й витривалість. Перевіряйте склад перед трансферами.",
    ["team.preset"] = "Безкоштовний пресет тактики {index}",
    ["team.presetHelp"] = "1: 4-3-3 володіння; 2: 4-4-2 контратака; 3: 5-3-2 низький блок. Після зміни схеми перевірте позиції гравців.",
    ["team.roles"] = "Призначте ролі вибраному слоту складу. Вилученого або заміненого виконавця замінить доступний партнер.",
    ["team.technicalForfeit"] = "Поразка 0:3 просуне календар і строк дискваліфікацій. Доходу, голів, асистів і досвіду немає; звичайні зарплати зберігаються.",
    ["training.ended"] = "Тренування завершено",
    ["training.finishing"] = "Випробування: 3 удари у площину",
    ["training.fixed"] = "Фіксований склад, звичайна складність, 90 секунд. Перший успіх: 25 косметичних жетонів. Повторної нагороди немає.",
    ["training.passing"] = "Випробування: 6 точних пасів",
    ["training.pause"] = "Дві тактичні паузи за матч, до 30 секунд кожна. Заміни доступні під час зупинки.",
    ["training.practice"] = "Вільне тренування",
    ["training.recovery"] = "Безкоштовне відновлення: {rate} витривалості за ігровий день. Процедура за {price} додає 20 та скорочує травму на одну зустріч. Досвіду немає; раз за ігрову дату.",
    ["training.safe"] = "Тренування не змінює дати кар’єри, гроші, витривалість і досвід. Можна вийти будь-коли.",
    ["training.step1"] = "Перемістіть футболіста за допомогою керування рухом.",
    ["training.step2"] = "Виконайте точний пас партнеру.",
    ["training.step3"] = "Утримуйте та відпустіть кнопку удару.",
    ["training.success"] = "Завдання виконано",
    ["training.tutorial"] = "Інтерактивне навчання",
    ["trait.calm"] = "Спокійний",
    ["trait.leader"] = "Лідер",
    ["trait.runner"] = "Бігун",
    ["trait.technician"] = "Технічний",
    ["ui.academy"] = "Академія",
    ["ui.achievements"] = "Досягнення",
    ["ui.age"] = "Вік",
    ["ui.all"] = "Усі",
    ["ui.annualCost"] = "Річні витрати на зарплату",
    ["ui.appearance"] = "Оформлення",
    ["ui.apply"] = "Застосувати",
    ["ui.assign"] = "Призначити",
    ["ui.auto"] = "Автоматично",
    ["ui.back"] = "Назад",
    ["ui.business"] = "Управління клубом",
    ["ui.buy"] = "Підписати",
    ["ui.buyout"] = "Викупити",
    ["ui.calendar"] = "Календар",
    ["ui.cancel"] = "Скасувати",
    ["ui.captain"] = "Капітан",
    ["ui.cards"] = "Картки",
    ["ui.career"] = "Кар'єра",
    ["ui.challenge"] = "Випробування",
    ["ui.claim"] = "Отримати нагороду",
    ["ui.close"] = "Закрити",
    ["ui.club"] = "Клуб",
    ["ui.clubBudget"] = "Бюджет клубу",
    ["ui.colorblind"] = "Розрізнювані кольори команд",
    ["ui.compare"] = "Порівняти",
    ["ui.confirm"] = "Підтвердити",
    ["ui.confirmForfeit"] = "Здатися з рахунком 0:3? Дохід, голи, передачі й розвиток за матч не нараховуються.",
    ["ui.confirmJob"] = "Очолити цей клуб? Його бюджет і склад замінять поточний клуб; особисті трофеї тренера збережуться.",
    ["ui.confirmSell"] = "Продати гравця? Перевір склад і бюджет перед підтвердженням.",
    ["ui.continue"] = "Продовжити",
    ["ui.contract"] = "Контракт",
    ["ui.controls"] = "Керування",
    ["ui.corner"] = "Кутові",
    ["ui.cosmeticOnly"] = "Лише оформлення. Жетони не купують гравців, рейтинг чи футбольні гроші.",
    ["ui.crowd"] = "Гучність трибун",
    ["ui.cup"] = "Кубок",
    ["ui.date"] = "Ігрова дата",
    ["ui.debt"] = "Борг",
    ["ui.design"] = "Оформити",
    ["ui.details"] = "Подробиці",
    ["ui.development"] = "Розвиток",
    ["ui.difficulty"] = "Складність",
    ["ui.difficultyHelp"] = "З підтримкою: характеристики CPU ×0,93. Стандарт: ×1. Експерт: ×1,07. Без прихованої зміни рахунку; рекорди окремі.",
    ["ui.division"] = "Дивізіон",
    ["ui.empty"] = "Поки нічого немає.",
    ["ui.expenses"] = "Витрати",
    ["ui.favorite"] = "До обраного",
    ["ui.filter"] = "Фільтр",
    ["ui.finance"] = "Фінансова дисципліна",
    ["ui.financeForecast"] = "Прогноз на сезон",
    ["ui.finances"] = "Фінанси та спонсори",
    ["ui.fitness"] = "Готовність",
    ["ui.football"] = "Футбол",
    ["ui.forfeit"] = "Здатися",
    ["ui.formation"] = "Схема",
    ["ui.formations"] = "Схеми",
    ["ui.freeAgent"] = "Вільний агент",
    ["ui.freeKick"] = "Штрафні",
    ["ui.goalkeeper"] = "Воротар",
    ["ui.goals"] = "Цілі",
    ["ui.goalsPriority"] = "Пріоритет правління",
    ["ui.haptics"] = "Вібрація",
    ["ui.help"] = "Допомога",
    ["ui.highlights"] = "Ключові моменти",
    ["ui.history"] = "Історія та нагороди",
    ["ui.hub"] = "Центр клубу",
    ["ui.identity"] = "Оформлення клубу",
    ["ui.inbox"] = "Вхідні",
    ["ui.income"] = "Доходи",
    ["ui.inventory"] = "Інвентар",
    ["ui.job"] = "Пропозиції клубів",
    ["ui.language"] = "Мова",
    ["ui.league"] = "Ліга",
    ["ui.loading"] = "Завантаження кар'єри…",
    ["ui.loan"] = "Орендувати",
    ["ui.loanOut"] = "Віддати в оренду",
    ["ui.market"] = "Трансфери",
    ["ui.matchStats"] = "Статистика матчу",
    ["ui.mentality"] = "Налаштованість",
    ["ui.mode"] = "Режим матчу",
    ["ui.modeHighlights"] = "Ключові моменти",
    ["ui.modeManual"] = "Ручний матч",
    ["ui.modeSimulate"] = "Швидка симуляція",
    ["ui.music"] = "Гучність музики",
    ["ui.name"] = "Ім'я",
    ["ui.negotiate"] = "Переговори",
    ["ui.net"] = "Чистий грошовий потік",
    ["ui.networkTimeout"] = "Сервер не відповів. Повтори запит, щоб оновити дані.",
    ["ui.nextSeason"] = "Почати наступний сезон",
    ["ui.none"] = "Немає",
    ["ui.off"] = "Вимк.",
    ["ui.on"] = "Увімк.",
    ["ui.onTarget"] = "Удари у площину",
    ["ui.owned"] = "У колекції",
    ["ui.palette"] = "Палітра",
    ["ui.pass"] = "Пас",
    ["ui.passes"] = "Точність пасів",
    ["ui.passing"] = "Пас",
    ["ui.penalty"] = "Пенальті",
    ["ui.performance"] = "Бонуси за результати",
    ["ui.physical"] = "Фізика",
    ["ui.play"] = "Грати матч",
    ["ui.played"] = "Зіграно",
    ["ui.playerOfMatch"] = "Гравець матчу",
    ["ui.points"] = "Очки",
    ["ui.position"] = "Позиція",
    ["ui.possession"] = "Володіння",
    ["ui.potential"] = "Діапазон потенціалу",
    ["ui.practice"] = "Вільне тренування",
    ["ui.pressKey"] = "Натисни клавішу для цієї дії.",
    ["ui.price"] = "Ціна",
    ["ui.priceLoading"] = "Завантаження ціни Roblox…",
    ["ui.promote"] = "Перевести до основи",
    ["ui.purchasesDisabled"] = "Товар не підключено. Покупки вимкнено.",
    ["ui.qualificationRules"] = "Перші два — Champions; третє місце та переможець кубка — Challenge. За збігу місця переходять наступним клубам таблиці.",
    ["ui.rating"] = "Рейтинг",
    ["ui.recruit"] = "Набрати вихованців",
    ["ui.reducedMotion"] = "Зменшити анімації",
    ["ui.remap"] = "Перепризначити клавіші",
    ["ui.rename"] = "Перейменувати",
    ["ui.renew"] = "Продовжити контракт",
    ["ui.replay"] = "Повтор гола",
    ["ui.reputation"] = "Репутація",
    ["ui.rest"] = "Медичне відновлення",
    ["ui.restorePurchases"] = "Відновити перепустки",
    ["ui.result"] = "Звіт про матч",
    ["ui.retry"] = "Повторити",
    ["ui.role"] = "Роль",
    ["ui.save"] = "Зберегти кар'єру",
    ["ui.saveHelp"] = "Критичні зміни зберігаються атомарно. Studio використовує тестове сховище; тимчасові сесії не зберігаються.",
    ["ui.scout"] = "Скаутинг",
    ["ui.scoutPlayer"] = "Дослідити гравця",
    ["ui.search"] = "Пошук",
    ["ui.season"] = "Сезон",
    ["ui.selected"] = "Вибрано",
    ["ui.sell"] = "Продати",
    ["ui.settings"] = "Налаштування",
    ["ui.sfx"] = "Гучність ефектів",
    ["ui.shake"] = "Тремтіння камери",
    ["ui.shape"] = "Форма",
    ["ui.shoot"] = "Удар",
    ["ui.shooting"] = "Удар",
    ["ui.shop"] = "Магазин клубу",
    ["ui.shots"] = "Удари",
    ["ui.simulate"] = "Швидка симуляція",
    ["ui.skip"] = "Пропустити",
    ["ui.sort"] = "Сортування",
    ["ui.sponsor"] = "Спонсор",
    ["ui.sprint"] = "Спринт",
    ["ui.squad"] = "Склад",
    ["ui.stable"] = "Стабільний дохід",
    ["ui.stadium"] = "Стадіон",
    ["ui.staff"] = "Персонал",
    ["ui.style"] = "Стиль команди",
    ["ui.styles"] = "Стилі гри",
    ["ui.substitute"] = "Заміна",
    ["ui.swap"] = "Замінити",
    ["ui.switch"] = "Змінити гравця",
    ["ui.symbol"] = "Мотив",
    ["ui.table"] = "Турнірна таблиця",
    ["ui.tackle"] = "Відбір",
    ["ui.tactics"] = "Тактика",
    ["ui.team"] = "Команда",
    ["ui.textScale"] = "Розмір тексту",
    ["ui.through"] = "Пас на хід",
    ["ui.tokens"] = "Косметичні жетони",
    ["ui.train"] = "Обрати тренування",
    ["ui.training"] = "Тренування й персонал",
    ["ui.trainingHelp"] = "Тренування йдуть за ігровим календарем. Відкриття екрана не дає розвитку.",
    ["ui.transfer"] = "Трансфер",
    ["ui.transferCost"] = "Повна вартість угоди",
    ["ui.trophies"] = "Трофеї",
    ["ui.tutorialDone"] = "Ти готовий до першого матчу. Навчання можна повторити в розділі «Допомога».",
    ["ui.tutorialMove"] = "Перемісти гравця за допомогою керування рухом.",
    ["ui.tutorialPass"] = "Віддай пас партнерові.",
    ["ui.tutorialShoot"] = "Прицілься й пробий по воротах.",
    ["ui.tutorialSkip"] = "Пропустити навчання",
    ["ui.tutorialStart"] = "Пройти навчання",
    ["ui.unavailable"] = "Недоступно",
    ["ui.unknown"] = "Невідомо",
    ["ui.upgrade"] = "Поліпшити",
    ["ui.upkeep"] = "Тижневе утримання зростає з рівнем персоналу та інфраструктури.",
    ["ui.view"] = "Відкрити",
    ["ui.wage"] = "Зарплата",
    ["ui.wages"] = "Зарплати",
    ["ui.windowClosed"] = "Трансферне вікно закрито",
    ["ui.wins"] = "Перемоги",
    ["ui.youth"] = "Розвиток молоді",
  },
}
]========],shared)
put('ModuleScript','Localization',[========[-- Key-based localization. Domain code needs only Locales; Roblox adapter is optional.
-- Names are passed as parameters and never sent through automatic translation.
local dictionaries=require(script.Parent.Locales)
local L={dictionaries=dictionaries,defaultLocale='en'}
local InstanceLocale={}; InstanceLocale.__index=InstanceLocale
local cloud={es=true,['pt-br']=true,pl=true,de=true,fr=true,tr=true,ja=true,ko=true}
local function finite(v) return type(v)=='number' and v==v and v~=math.huge and v~=-math.huge end
local function length(s)
 if utf8 and utf8.len then local ok,n=pcall(utf8.len,s); if ok and n then return n end end
 return #s
end
local function normalized(value)
 if type(value)~='string' then return 'en' end
 value=value:lower():gsub('_','-')
 if value=='qps-ploc' then return value end
 local base=value:match('^([a-z]+)')
 if base=='ua' then return 'uk' end
 if base=='pt' then return 'pt-br' end
 if dictionaries[base] or cloud[base] then return base end
 return 'en'
end
function L.resolve(setting,robloxLocale)
 if setting==nil or setting=='auto' then return normalized(robloxLocale) end
 return normalized(setting)
end
function L.pseudo(text)
 -- Pad by 50% of codepoints, preserving placeholders and readable English text.
 local n=length(text); local pad=math.max(0,math.floor(n*.5+.5)-2)
 return '['..text..string.rep('~',pad)..']'
end
function L.plural(locale,n)
 n=math.floor(math.abs(tonumber(n) or 0))
 if locale=='ja' or locale=='ko' or locale=='tr' then return 'other' end
 if locale=='pl' then
  if n==1 then return 'one' end
  if n%10>=2 and n%10<=4 and (n%100<12 or n%100>14) then return 'few' end
  return 'many'
 end
 if locale=='fr' or locale=='pt-br' then return n<=1 and 'one' or 'other' end
 if locale=='ru' or locale=='uk' then
  if n%10==1 and n%100~=11 then return 'one' end
  if n%10>=2 and n%10<=4 and (n%100<12 or n%100>14) then return 'few' end
  return 'many'
 end
 return n==1 and 'one' or 'other'
end
function L.number(value,locale,decimals)
 if not finite(value) then return '—' end
 decimals=math.max(0,math.min(2,math.floor(tonumber(decimals) or 0)))
 local negative=value<0; value=math.abs(value)
 local raw=string.format('%.'..decimals..'f',value)
 local integer,fraction=raw:match('^(%d+)%.?(%d*)$')
 local sep=(locale=='ru' or locale=='uk' or locale=='fr' or locale=='pl') and '\194\160' or ','
 local groups={}
 repeat table.insert(groups,1,integer:sub(-3)); integer=integer:sub(1,-4) until #integer==0
 local decimal=(locale=='ru' or locale=='uk' or locale=='fr' or locale=='pl' or locale=='de' or locale=='es' or locale=='pt-br' or locale=='tr') and ',' or '.'
 if locale=='de' or locale=='es' or locale=='pt-br' or locale=='tr' then sep='.' end
 return (negative and '−' or '')..table.concat(groups,sep)..(decimals>0 and decimal..fraction or '')
end
local function parameters(text,params,locale)
 return (text:gsub('{([%w_]+)}',function(name)
  local value=params and params[name]
  if value==nil then return '—' end
  if finite(value) then return L.number(value,locale) end
  if type(value)=='string' or type(value)=='boolean' then return tostring(value) end
  return '—'
 end))
end
function L.t(key,params,locale)
 locale=L.resolve(locale or 'en','en')
 if type(key)~='string' then return '' end
 local dictionary=dictionaries[locale] or dictionaries.en
 local selected=key
 if type(params)=='table' and params.count~=nil then
  local pluralKey=key..'.'..L.plural(locale,params.count)
  if dictionary[pluralKey] or dictionaries.en[pluralKey] then selected=pluralKey end
 end
 local text=dictionary[selected] or dictionaries.en[selected]
 if not text then return '['..key..']' end
 if locale=='qps-ploc' then text=L.pseudo(text) end
 return parameters(text,params,locale)
end
function L.new(options)
 options=options or {}
 local obj=setmetatable({setting=options.locale or 'auto',robloxLocale=options.robloxLocale or 'en-us',missing={},generation=0},InstanceLocale)
 obj.locale=L.resolve(obj.setting,obj.robloxLocale)
 return obj
end
function InstanceLocale:t(key,params)
 if type(key)~='string' then return '' end
 local selected=key
 if type(params)=='table' and params.count~=nil then
  local suffix=L.plural(self.locale,params.count)
  if dictionaries.en[key..'.'..suffix] or (dictionaries[self.locale] and dictionaries[self.locale][key..'.'..suffix]) then selected=key..'.'..suffix end
 end
 if not dictionaries.en[selected] then self.missing[selected]=true end
 if self.translator and cloud[self.locale] then
  local ok,text=pcall(function() return self.translator:FormatByKey(selected,params or {}) end)
  if ok and type(text)=='string' and text~='' and text~=selected then return text end
 end
 return L.t(selected,params,self.locale)
end
function InstanceLocale:event(value)
 if type(value)=='string' then
  -- Recognised event codes localize; pre-v2 literal history remains untouched.
  if dictionaries.en[value] then return self:t(value) end
  return value
 end
 if type(value)~='table' then return '' end
 if type(value.key)=='string' then
  if value.key=='event.achievement' and type(value.params)=='table'then local params={};for k,v in pairs(value.params)do params[k]=v end;params.name=self:t('achievement.'..tostring(params.name));return self:t(value.key,params)end
  return self:t(value.key,value.params or {})end
 if type(value.code)=='string' then return self:t(value.code,value.params or {}) end
 return type(value.legacy)=='string' and value.legacy or type(value.text)=='string' and value.text or ''
end
function InstanceLocale:number(n,decimals) return L.number(n,self.locale,decimals) end
function InstanceLocale:money(n) return self:t('format.money',{amount=self:number(n)}) end
function InstanceLocale:date(season,day) return self:t('format.date',{season=season,day=day}) end
function InstanceLocale:setLocale(setting,robloxLocale)
 setting=setting or 'auto'
 if self.setting==setting and (not robloxLocale or self.robloxLocale==robloxLocale) then return self.locale end
 self.setting=setting; if robloxLocale then self.robloxLocale=robloxLocale end
 self.locale=L.resolve(self.setting,self.robloxLocale); self.translator=nil
 if self.service then self:attachRoblox(self.player,self.localTable,self.onReady,self.service) end
 return self.locale
end
function InstanceLocale:attachRoblox(player,localTable,onReady,service)
 -- Starts an asynchronous request; the UI never waits for cloud translations.
 -- A late result from a timed-out request or previous locale is ignored.
 if not task or not task.spawn or not task.delay then return false end
 if not service then
  if not game then return false end
  local ok,result=pcall(function() return game:GetService('LocalizationService') end)
  if not ok then return false end
  service=result
 end
 self.service=service; self.player=player; self.localTable=localTable; self.onReady=onReady
 self.generation=self.generation+1; local generation=self.generation
 local deadline=false; local targetLocale=self.locale
 task.delay(4,function() deadline=true end)
 task.spawn(function()
  local ok,translator
  if cloud[targetLocale] then
   ok,translator=pcall(function()
    if self.setting=='auto' and player then return service:GetTranslatorForPlayerAsync(player) end
    return service:GetTranslatorForLocaleAsync(targetLocale)
   end)
  elseif localTable and targetLocale~='qps-ploc' then
   ok,translator=pcall(function() return localTable:GetTranslator(targetLocale=='en' and 'en-us' or targetLocale) end)
  end
  if ok and translator and not deadline and self.generation==generation then
   self.translator=translator
   if onReady then onReady() end
  end
 end)
 return true
end
function InstanceLocale:destroy()
 self.generation=self.generation+1; self.translator=nil; self.service=nil; self.player=nil; self.localTable=nil; self.onReady=nil
end
function L.entries()
 local keys={}; for key in pairs(dictionaries.en) do keys[#keys+1]=key end; table.sort(keys)
 local rows={}
 for _,key in ipairs(keys) do
  rows[#rows+1]={Key=key,Source=dictionaries.en[key],Context=key,Values={['en-us']=dictionaries.en[key],ru=dictionaries.ru[key],uk=dictionaries.uk[key]}}
 end
 return rows
end
function L.installTable(parent)
 local tableObject=Instance.new('LocalizationTable'); tableObject.Name='TouchlineLocalization'; tableObject.SourceLocaleId='en-us'; tableObject:SetEntries(L.entries()); tableObject.Parent=parent
 return tableObject
end
return L
]========],shared)
put('ModuleScript','Market',[========[-- NPC transfers inside a single career. Opening a menu never consumes random numbers.
local K=require(script.Parent.EconomyConfig)
local E=require(script.Parent.Economy)
local P=require(script.Parent.Players)
local W=require(script.Parent.World)
local B={}
local function absDate(p)return(p.season-1)*K.seasonDays+(p.date or 0)end
local function hash(s)local n=7;for i=1,#s do n=(n*31+s:byte(i))%2147483647 end;return n end
function B.isOpen(p)local d=p.date or 0;return d<=K.windowOneEnd or(d>=K.windowTwoStart and d<=K.windowTwoEnd)end
function B.refresh(p,C)
 local rng=C.rng(p.seed+p.season*7919);p.market={};p.marketConsumed=p.marketConsumed or{};p.favorites=p.favorites or{}
 local clubs={};for _,c in pairs(p.world.clubs)do if c.id~=p.clubId then clubs[#clubs+1]=c end end
 table.sort(clubs,function(a,b)return a.id<b.id end)
 for i=1,24 do
  local seller=clubs[((i*37+p.seed+p.season*11)%#clubs)+1]
  local id=seller.id..':offer:'..p.season..':'..i
  if not p.marketConsumed[id]then
   local base=math.max(35,math.min(86,(seller.rating or 55)+(i%5)-4))
   -- Listings near the manager's level remain useful in lower divisions.
   if i<=16 then base=math.min(base,44+(6-p.division)*6+rng(0,8))end
   local q=P.new(rng,id,base,({'GK','DEF','MID','FWD'})[(i-1)%4+1],seller.country or p.country,p.season)
   q.sellerId=seller.id;q.seller=seller.name;q.free=i%8==0;q.currentSeason=p.season
   if q.free then q.sellerId=nil;q.seller=nil;q.contractEnd=p.season end
   local value=E.value(q,seller.reputation)
   q.price=q.free and 0 or value;q.bonus=math.floor(value*(q.free and K.freeSigningBonus or K.signingBonus))
   q.agentFee=math.floor((q.price+q.bonus)*K.agentRate);q.totalCost=q.price+q.bonus+q.agentFee
   q.expires=K.windowTwoEnd;q.loanFee=math.floor(value*K.loanRate);q.buyout=math.floor(value*K.buyoutRate)
   p.market[#p.market+1]=q
  end
 end
 p.marketVersion=(p.marketVersion or 0)+1
end
function B.find(p,id)for i,q in ipairs(p.market)do if q.id==id then return q,i end end end
function B.quote(p,q)
 if q.loan or q.emergency then return nil,'PLAYER_NOT_OWNED'end
 if absDate(p)-(q.acquiredAbs or -1000)<K.saleHoldDays then return nil,'RESALE_HOLD'end
 -- A real, stable NPC buyer. Interest changes with football dates, not menu refreshes.
 local interest=hash(q.id..':'..p.season..':'..math.floor((p.date or 0)/28))
 if interest%5==0 then return nil,'NO_BUYER'end
 local clubs={};q.currentSeason=p.season
 for _,club in pairs(p.world.clubs)do local amount=math.floor(E.value(q,club.reputation)*(.70+(interest%17)*.01));if club.id~=p.clubId and(club.rating or 50)>=q.rating-15 and(club.cash or 0)>=amount+q.wage*4 and(club.debt or 0)<=(club.cash or 0)then clubs[#clubs+1]=club end end
 table.sort(clubs,function(a,b)return a.id<b.id end);if#clubs==0 then return nil,'NO_BUYER'end
 local buyer=clubs[interest%#clubs+1]
 q.currentSeason=p.season
 return{id=tostring(p.season)..':'..tostring(math.floor((p.date or 0)/28))..':'..tostring(interest)..':'..tostring(math.floor(E.value(q,buyer.reputation)*(.70+(interest%17)*.01))),amount=math.floor(E.value(q,buyer.reputation)*(.70+(interest%17)*.01)),buyerId=buyer.id,buyer=buyer.name,expires=math.min(K.seasonDays,(math.floor((p.date or 0)/28)+1)*28-1)}
end
local function salaryAffordable(p,wage)
 -- Forecast warning is public, while credit cannot silently fund transfers.
 return p.cash>=math.floor(wage*4)
end
function B.buy(p,C,id,loan)
 if not B.isOpen(p)then return false,'TRANSFER_WINDOW_CLOSED'end
 if#p.roster>=K.maxRoster then return false,'ROSTER_FULL'end
 local q,i=B.find(p,id);if not q or p.marketConsumed[id]then return false,'OFFER_UNAVAILABLE'end
 if C.find(p,id)then return false,'DUPLICATE_PLAYER'end
 if(p.date or 0)>q.expires then return false,'OFFER_EXPIRED'end
 if loan and q.free then return false,'LOAN_UNAVAILABLE'end
 local cost=loan and(q.loanFee+q.agentFee)or q.totalCost
 if not salaryAffordable(p,q.wage)then return false,'WAGE_RESERVE_REQUIRED'end
 local ok,err=E.spend(p,cost);if not ok then return false,err end
 local bought=C.copy(q);bought.acquiredAbs=absDate(p);bought.paid=cost;bought.contractEnd=p.season+(loan and 0 or 3);bought.currentSeason=p.season
 if loan then bought.loan={sellerId=q.sellerId,ends=p.season,buyout=q.buyout};bought.loanFee=q.loanFee end
 bought.price=nil;bought.totalCost=nil;bought.bonus=nil;bought.agentFee=nil;bought.expires=nil;bought.free=nil;bought.negotiated=nil
 local seller=q.sellerId and p.world.clubs[q.sellerId];if seller then seller.cash=math.min(100000000,seller.cash+(loan and q.loanFee or q.price))end
 p.roster[#p.roster+1]=bought;p.marketConsumed[id]=true;table.remove(p.market,i)
 p.financeLedger.transfersOut=p.financeLedger.transfersOut+cost
 return true,loan and'PLAYER_LOANED'or'PLAYER_SIGNED',{name=q.name,amount=cost}
end
function B.sell(p,C,id,offerId)
 if not B.isOpen(p)then return false,'TRANSFER_WINDOW_CLOSED'end
 local q,i=C.find(p,id);if not q then return false,'PLAYER_NOT_FOUND'end;if q.loanOut then return false,'LOAN_UNAVAILABLE'end
 for _,v in ipairs(p.lineup)do if v==id then return false,'PLAYER_IN_LINEUP'end end
 if#p.roster<=16 then return false,'SQUAD_DEPTH_REQUIRED'end
 if q.pos=='GK'then local keepers=0;for _,v in ipairs(p.roster)do if v.pos=='GK'then keepers=keepers+1 end end;if keepers<=2 then return false,'KEEPER_REQUIRED'end end
 local offer,err=B.quote(p,q);if not offer then return false,err end
 if offerId and offerId~=offer.id then return false,'OFFER_EXPIRED'end
 p.world.clubs[offer.buyerId].cash=p.world.clubs[offer.buyerId].cash-offer.amount
 E.credit(p,offer.amount);p.financeLedger.transfersIn=p.financeLedger.transfersIn+offer.amount;table.remove(p.roster,i)
 p.sold=p.sold or{};p.sold[id]={buyerId=offer.buyerId,season=p.season,amount=offer.amount}
 return true,'PLAYER_SOLD',{name=q.name,amount=offer.amount,buyer=offer.buyer}
end
function B.buyout(p,C,id)
 if not B.isOpen(p)then return false,'TRANSFER_WINDOW_CLOSED'end
 local q=C.find(p,id);if not q or not q.loan then return false,'LOAN_UNAVAILABLE'end
 local amount=q.loan.buyout;local ok,err=E.spend(p,amount);if not ok then return false,err end
 local seller=q.loan.sellerId and p.world.clubs[q.loan.sellerId];if seller then seller.cash=math.min(100000000,seller.cash+amount)end
 p.financeLedger.transfersOut=p.financeLedger.transfersOut+amount;q.loan=nil;q.emergency=nil;q.contractEnd=p.season+3;q.acquiredAbs=absDate(p);q.paid=(q.paid or 0)+amount
 return true,'PLAYER_SIGNED',{name=q.name,amount=amount}
end
function B.scout(p,id)
 local q=B.find(p,id);if not q then for _,list in ipairs({p.roster,p.academy})do for _,owned in ipairs(list)do if owned.id==id then q=owned;break end end end end;if not q then return false,'PLAYER_NOT_FOUND'end
 if q.scouted then return false,'ALREADY_SCOUTED'end
 local specialist=p.scoutRegion==q.country;local fee=math.floor(K.scoutFee*(specialist and .75 or 1));local ok,err=E.spend(p,fee);if not ok then return false,err end
 q.scoutAccuracy=specialist and 1 or 2;q.scoutReport={date=p.date,country=q.country,specialist=specialist,fee=fee};q.scouted=true;return true,'SCOUT_COMPLETE',{name=q.name}
end
function B.negotiate(p,id)
 if not B.isOpen(p)then return false,'TRANSFER_WINDOW_CLOSED'end
 local q=B.find(p,id);if not q then return false,'OFFER_UNAVAILABLE'end
 if q.negotiated then return false,'ALREADY_NEGOTIATED'end
 -- One deterministic counteroffer; no random reroll or client-provided price.
 local discount=math.min(.12,.025+(p.staff.scout or 1)*.012+p.reputation*.0001)
 q.price=math.floor(q.price*(1-discount));q.bonus=math.floor(q.bonus*(1-discount*.4));q.agentFee=math.floor((q.price+q.bonus)*K.agentRate)
 q.totalCost=q.price+q.bonus+q.agentFee;q.negotiated=true
 return true,'NEGOTIATION_COMPLETE',{amount=q.totalCost}
end
return B
]========],server)
put('ModuleScript','Match',[========[-- Deterministic server-authoritative evolution of the original 11v11 engine.
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
]========],server)
put('ModuleScript','MatchConfig',[========[-- Shared competitive rules. Difficulty is disclosed and separates records.
return {
 step=.05, duration=210, extraTime=70, aiInterval=.20, snapshotInterval=.10,
 halftimePause=2, restartPause=1.15, penaltyTimeout=8, maxSubstitutions=5,
 replayFrames=45, eventLimit=64,
 difficulty={easy=.93,normal=1,hard=1.07},
 styles={
  possession={width=1,depth=1,press=1,passing=1.08,speed=.96,stamina=1},
  counter={width=.92,depth=.85,press=.8,passing=.98,speed=1.07,stamina=1.03},
  press={width=.92,depth=1.13,press=1.5,passing=.97,speed=1.02,stamina=1.32},
  lowblock={width=.8,depth=.7,press=.65,passing=.96,speed=.97,stamina=.84},
  wings={width=1.22,depth=1.02,press=.95,passing=1.02,speed=1,stamina=1.1},
 },
}
]========],server)
put('ModuleScript','MatchView',[========[-- One visible 2.5D presentation. Snapshots are visualized, never simulated here.
local UI=require(script.Parent.UI)
local Catalog=require(script.Parent.MonetizationConfig)
local V={}
local C=UI.colors
local function box(parent,x,y,w,h,color)
 local f=UI.frame(parent,'Shape',color); f.Position=UDim2.new(x,0,y,0); f.Size=UDim2.new(w,0,h,0); return f
end
local function circle(parent,x,y,w,h,color)
 local f=box(parent,x,y,w,h,color); UI.round(f,100); return f
end
function V.new(gui,tr,send)
 local self={tr=tr,send=send,buffer={},history={},figures={},visible=false,replay=nil,profile=nil,latest=nil,lastSeq=-1}
 setmetatable(self,{__index=V})
 self.root=UI.frame(gui,'Match',C.bg); self.root.Size=UDim2.fromScale(1,1); self.root.Visible=false; self.root.ZIndex=5
 self.stage=UI.frame(self.root,'Stadium',Color3.fromRGB(29,47,67)); self.stage.ClipsDescendants=true
 self.pitch=UI.frame(self.stage,'Pitch',Color3.fromRGB(35,113,73))
 self.grass={};for i=0,9 do self.grass[#self.grass+1]=box(self.pitch,i/10,0,.1,1,i%2==0 and Color3.fromRGB(38,123,77) or Color3.fromRGB(31,110,69)) end
 local line=Color3.fromRGB(213,231,210)
 for _,y in ipairs({0,1}) do local f=box(self.pitch,0,y,1,0,line); f.Size=UDim2.new(1,0,0,2) end
 for _,x in ipairs({0,.5,1}) do local f=box(self.pitch,x,0,0,1,line); f.Size=UDim2.new(0,2,1,0) end
 local center=UI.make('Frame',{Position=UDim2.fromScale(.5,.5),AnchorPoint=Vector2.new(.5,.5),Size=UDim2.fromScale(.18,.28),BackgroundTransparency=1},self.pitch); UI.round(center,100); UI.make('UIStroke',{Color=line,Thickness=2},center)
 circle(self.pitch,.495,.492,.01,.016,line)
 for _,x in ipairs({0,.84}) do
  local area=box(self.pitch,x,.2,.16,.6,line); area.BackgroundTransparency=1; UI.make('UIStroke',{Color=line,Thickness=2},area)
 end
 for _,x in ipairs({0,.94}) do
  local area=box(self.pitch,x,.34,.06,.32,line); area.BackgroundTransparency=1; UI.make('UIStroke',{Color=line,Thickness=2},area)
 end
 self.crest=UI.label(self.stage,'TD',32,true); self.crest.TextColor3=C.lime
 self.score=UI.label(self.root,'',22,true); self.score.TextXAlignment=Enum.TextXAlignment.Center
 self.clock=UI.label(self.root,'',15,false); self.clock.TextXAlignment=Enum.TextXAlignment.Center; self.clock.TextColor3=C.muted
 self.notice=UI.round(UI.frame(self.root,'Notice',C.panel)); self.noticeText=UI.label(self.notice,'',18,true); self.noticeText.Size=UDim2.new(1,-20,1,0); self.noticeText.Position=UDim2.fromOffset(10,0); self.noticeText.TextXAlignment=Enum.TextXAlignment.Center
 self.ball=UI.round(UI.frame(self.pitch,'Ball',Color3.fromRGB(248,247,230)),100); self.ball.Size=UDim2.fromOffset(9,9); self.ball.AnchorPoint=Vector2.new(.5,.5); self.ball.ZIndex=14
 self.ballShadow=UI.round(UI.frame(self.pitch,'BallShadow',Color3.fromRGB(8,35,22)),100); self.ballShadow.Size=UDim2.fromOffset(12,6); self.ballShadow.AnchorPoint=Vector2.new(.5,.5); self.ballShadow.BackgroundTransparency=.45
 for i=1,22 do
  local f={}; f.root=UI.make('Frame',{Name='Footballer'..i,Size=UDim2.fromOffset(24,31),BackgroundTransparency=1,AnchorPoint=Vector2.new(.5,.65),ZIndex=9},self.pitch)
  f.shadow=circle(f.root,.04,.64,.92,.24,Color3.fromRGB(8,35,22)); f.shadow.BackgroundTransparency=.4
  f.ring=UI.make('Frame',{Position=UDim2.fromScale(.08,.61),Size=UDim2.fromScale(.84,.33),BackgroundTransparency=1,Visible=false},f.root); UI.round(f.ring,100); UI.make('UIStroke',{Color=C.lime,Thickness=2},f.ring)
  f.left=box(f.root,.25,.58,.17,.3,Color3.fromRGB(235,235,229)); f.right=box(f.root,.58,.58,.17,.3,Color3.fromRGB(235,235,229))
  f.arm1=box(f.root,.08,.26,.17,.32,Color3.fromRGB(191,141,105)); f.arm2=box(f.root,.75,.26,.17,.32,Color3.fromRGB(191,141,105))
  f.shirt=UI.round(box(f.root,.24,.23,.52,.39,i<=11 and C.lime or C.blue),3)
  f.patterns={};for n=1,3 do local stripe=box(f.shirt,0,(n-1)/3,1,.13,Color3.fromRGB(20,34,45));stripe.Visible=false;f.patterns[n]=stripe end
  f.head=circle(f.root,.35,.03,.3,.27,Color3.fromRGB(211,166,123))
  f.number=UI.label(f.root,tostring((i-1)%11+1),9,true); f.number.Size=UDim2.fromScale(.6,.3); f.number.Position=UDim2.fromScale(.2,.26); f.number.TextXAlignment=Enum.TextXAlignment.Center; f.number.TextColor3=C.bg
  f.captain=box(f.root,.73,.35,.21,.08,Color3.fromRGB(250,217,83));f.captain.Visible=false
  f.card=box(f.root,.9,.05,.14,.25,C.red); f.card.Visible=false; self.figures[i]=f
 end
 self.replayButton=UI.button(self.root,tr:t('ui.replay'),function() self:startReplay() end)
 self.modeButton=UI.button(self.root,tr:t('ui.modeHighlights'),function() self.send('control',{action='mode',value=self.latest and self.latest.mode=='highlights' and 'manual' or 'highlights'}) end)
 self.pauseButton=UI.button(self.root,tr:t('ui.tactics'),function() if self.onTactics then self.onTactics() end end)
 self.exit=UI.button(self.root,tr:t('ui.forfeit'),function() if self.onForfeit then self.onForfeit() end end)
 self.penalty=UI.round(UI.frame(self.root,'Penalty',C.panel)); self.penalty.Visible=false; self.penaltyTitle=UI.label(self.penalty,'',16,true); self.penaltyTitle.Position=UDim2.fromOffset(8,4); self.penaltyTitle.Size=UDim2.new(1,-16,0,28)
 self.penButtons={}
 for i,aim in ipairs({-1,0,1}) do
  local b=UI.button(self.penalty,({'←','●','→'})[i],function() self.send('control',{action='penalty',aim=aim*.8,power=.82,dive=aim*.8}) end,true)
  b.Position=UDim2.new((i-1)/3,5,0,38); b.Size=UDim2.new(1/3,-10,0,50); self.penButtons[i]=b
 end
 self:resize(); return self
end
function V:resize()
 local size=workspace.CurrentCamera.ViewportSize; local portrait=size.Y>size.X; local w=math.min(size.X-36,(size.Y-(portrait and 300 or 172))*100/64)
 w=math.max(180,w); local h=w*64/100; local x=(size.X-w)/2; local y=portrait and 100 or 92
 self.stage.Position=UDim2.fromOffset(x-12,y-12); self.stage.Size=UDim2.fromOffset(w+24,h+24)
 self.pitch.Position=UDim2.fromOffset(12,12); self.pitch.Size=UDim2.fromOffset(w,h)
 self.crest.Position=UDim2.fromOffset(10,0); self.crest.Size=UDim2.fromOffset(90,45)
 self.score.Position=UDim2.fromOffset(10,8); self.score.Size=UDim2.new(1,-20,0,40)
 self.clock.Position=UDim2.fromOffset(10,49); self.clock.Size=UDim2.new(1,-20,0,28)
 self.notice.Position=UDim2.new(.5,-math.min(220,(size.X-30)/2),0,y+h*.42); self.notice.Size=UDim2.fromOffset(math.min(440,size.X-30),54)
 local buttons={self.replayButton,self.modeButton,self.pauseButton,self.exit}
 for i,b in ipairs(buttons) do b.Position=UDim2.new((i-1)/4,5,1,-54); b.Size=UDim2.new(.25,-10,0,46); b.TextSize=size.X<700 and 11 or 14 end
 self.penalty.Position=UDim2.new(.5,-math.min(180,(size.X-24)/2),1,-160); self.penalty.Size=UDim2.fromOffset(math.min(360,size.X-24),96)
end
function V:show(profile,snapshot)
 self.replayButton.Text=self.tr:t('ui.replay');self.modeButton.Text=self.tr:t('ui.modeHighlights');self.pauseButton.Text=self.tr:t('ui.tactics');self.exit.Text=self.tr:t('ui.forfeit')
 self.profile=profile; self.root.Visible=true; self.visible=true; self.buffer={}; self.history={}; self.lastSeq=-1; self.replay=nil;self.lastReplayId=0;self.goalFrames=nil;self.shakeUntil=0
 local equipped=profile and profile.cosmetics and profile.cosmetics.equipped or {}; local kit=equipped.kit or 'classic'
 local teamColor=kit=='sunset' and Color3.fromRGB(249,150,98) or kit=='lime' and C.lime or Color3.fromRGB(235,239,228)
 if profile and profile.settings and profile.settings.colorblind then teamColor=Color3.fromRGB(255,202,66) end
 for i,f in ipairs(self.figures) do f.shirt.BackgroundColor3=i<=11 and teamColor or C.blue end
 for _,item in ipairs(Catalog.items)do
  if item.id==kit then for i,f in ipairs(self.figures)do if i<=11 then f.shirt.BackgroundColor3=profile.settings and profile.settings.colorblind and Color3.fromRGB(255,202,66) or Color3.fromRGB(item.colors[1],item.colors[2],item.colors[3]);for n,stripe in ipairs(f.patterns)do stripe.Visible=item.pattern~='solid';stripe.Rotation=item.pattern=='sash' and 30 or 0;stripe.Size=item.pattern=='stripe' and UDim2.fromScale(.15,1) or UDim2.fromScale(1,.13);stripe.Position=item.pattern=='stripe' and UDim2.fromScale((n-1)/3,0) or UDim2.fromScale(0,(n-1)/3) end end end end
  if item.id==equipped.stadium and item.pitchColors then for i,stripe in ipairs(self.grass)do local c=item.pitchColors;stripe.BackgroundColor3=Color3.fromRGB(c[1]+i%2*5,c[2]+i%2*8,c[3]+i%2*5)end end
  if item.id==equipped.broadcast and item.accent then local c=item.accent;self.clock.TextColor3=Color3.fromRGB(c[1],c[2],c[3]) end
 end
 local design=profile and profile.cosmetics and profile.cosmetics.design
 if design and design.color then for i=1,11 do if not(profile.settings and profile.settings.colorblind)then self.figures[i].shirt.BackgroundColor3=Color3.fromRGB(design.color[1],design.color[2],design.color[3])end end end
 self.crest.Text=design and (({shield='▰',round='●',diamond='◆',star='★'})[design.shape]..tostring(design.symbol))or(equipped.crest=='crest_star' and '★ TD' or 'TD')..(equipped.badge=='supporter_badge' and ' ♦' or '')
 self.stage.BackgroundColor3=equipped.stadium=='night' and Color3.fromRGB(8,17,38) or Color3.fromRGB(29,47,67)
 self.score.TextColor3=equipped.broadcast=='clean' and C.text or C.lime
 self:resize(); if snapshot then self:push(snapshot) end
end
function V:push(snapshot)
 if type(snapshot)~='table' or type(snapshot.players)~='table' then return false end
 local seq=snapshot.seq or 0; if seq<=self.lastSeq then return false end; self.lastSeq=seq
 local goalReplay=(snapshot.replayId or 0)>(self.lastReplayId or 0)
 if (snapshot.replayId or 0)>(self.lastReplayId or 0) then self.lastReplayId=snapshot.replayId;if self.profile and self.profile.settings and self.profile.settings.shake and not self.profile.settings.reducedMotion then self.shakeUntil=os.clock()+.2 end end
 snapshot.received=os.clock(); self.latest=snapshot; self.buffer[#self.buffer+1]=snapshot; self.history[#self.history+1]=snapshot
 while #self.buffer>8 do table.remove(self.buffer,1) end
 while #self.history>48 do table.remove(self.history,1) end
 if goalReplay then self.goalFrames={};for i=math.max(1,#self.history-35),#self.history do self.goalFrames[#self.goalFrames+1]=self.history[i]end end
 return true
end
function V:startReplay()
 if self.replay then self.replay=nil;return end
 local source=self.goalFrames or self.history;if #source<4 then return end
 self.replay={frames={},started=os.clock()};for i=math.max(1,#source-35),#source do self.replay.frames[#self.replay.frames+1]=source[i]end
end
function V:render()
 if not self.visible or not self.latest then return end
 local shake=os.clock()<(self.shakeUntil or 0)and 2 or 0;self.pitch.Position=UDim2.fromOffset(12+math.sin(os.clock()*67)*shake,12+math.cos(os.clock()*71)*shake)
 local latest=self.latest; local a,b,t=latest,latest,0; local now=os.clock()
 if self.replay then
  local elapsed=now-self.replay.started; local frames=self.replay.frames; local index=math.floor(elapsed*10)+1
  if index>=#frames then self.replay=nil else a=frames[index]; b=frames[index+1]; t=elapsed*10-math.floor(elapsed*10) end
 else
  local target=(latest.time or 0)+math.min(.1,now-latest.received)-.12
  for i=1,#self.buffer-1 do local p,q=self.buffer[i],self.buffer[i+1]
   if (p.time or 0)<=target and (q.time or 0)>=target then a,b=p,q; t=math.max(0,math.min(1,(target-(p.time or 0))/math.max(.001,(q.time or 0)-(p.time or 0)))); break end
  end
 end
 for i,f in ipairs(self.figures) do
  local p,q=a.players[i],b.players[i]; f.root.Visible=p~=nil and p.active~=false
  if p and q then
   local x=p.x+(q.x-p.x)*t; local y=p.y+(q.y-p.y)*t; f.root.Position=UDim2.fromScale(x/100,y/64)
   local moving=not(self.profile and self.profile.settings and self.profile.settings.reducedMotion)and math.abs(q.x-p.x)+math.abs(q.y-p.y)>.05; local stride=moving and math.sin(now*15+i)*18 or 0
   f.left.Rotation=stride; f.right.Rotation=-stride; f.arm1.Rotation=-stride*.5; f.arm2.Rotation=stride*.5
   f.head.Position=UDim2.fromScale(.35+math.cos(p.angle or 0)*.03,.03+math.sin(p.angle or 0)*.03)
   f.captain.Visible=i==latest.captain;f.ring.Visible=i==latest.controlled; f.card.Visible=(p.card or 0)>0; f.card.BackgroundColor3=(p.card or 0)>=2 and C.red or Color3.fromRGB(255,215,61)
  end
 end
 local bx=a.ball.x+(b.ball.x-a.ball.x)*t; local by=a.ball.y+(b.ball.y-a.ball.y)*t
 self.ball.Position=UDim2.fromScale(bx/100,by/64); self.ballShadow.Position=UDim2.new(bx/100,1,by/64,4)
 local club=self.profile and self.profile.club or 'Touchline'; local op=latest.op or ''
 self.score.Text=latest.userHome==false and (op..'  '..latest.away..' : '..latest.home..'  '..club) or (club..'  '..latest.home..' : '..latest.away..'  '..op)
 self.clock.Text=tostring(latest.minute or 0).."′  ·  "..self.tr:t('ui.mode'..(latest.mode=='highlights' and 'Highlights' or latest.mode=='simulate' and 'Simulate' or 'Manual'))
 local tutorial=latest.training
 if tutorial then self.clock.Text=self.tr:t('training.'..tutorial.kind)..' · '..tostring(tutorial.progress)..' / '..tostring(tutorial.target>0 and tutorial.target or 3)..' · '..tostring(tutorial.remaining or 0)..'s' end
 self.notice.Visible=self.replay~=nil or (latest.notice~=nil and latest.notice~=''); self.noticeText.Text=self.replay and self.tr:t('ui.replay') or self.tr:t(latest.notice or '')
 if tutorial and tutorial.kind=='tutorial' then self.notice.Visible=true;self.noticeText.Text=self.tr:t('training.step'..math.min(3,tutorial.step)) end
 self.penalty.Visible=latest.phase=='penalties';pcall(function()local g=game:GetService('GuiService');if self.penalty.Visible then if not g.SelectedObject or g.SelectedObject.Parent~=self.penalty then g.SelectedObject=self.penButtons[2]end elseif g.SelectedObject and g.SelectedObject.Parent==self.penalty then g.SelectedObject=nil end end); self.penaltyTitle.Text=self.tr:t(latest.penalties and latest.penalties.turn==2 and 'ui.goalkeeper' or 'ui.penalty')
end
function V:hide() self.visible=false; self.root.Visible=false; self.buffer={}; self.history={}; self.latest=nil; self.replay=nil end
return V
]========],shared)
put('ModuleScript','Monetization',[========[-- One receipt callback; grants and purchase IDs persist in the SAME profile write.
-- Roblox docs checked 2026-10-23:
-- /production/monetization/developer-products and MarketplaceService reference.
local MarketplaceService=game:GetService('MarketplaceService')
local Players=game:GetService('Players')
local RunService=game:GetService('RunService')
local Config=require(script.Parent.MonetizationConfig)
local N={config=Config}
local context=nil
local bound=false
local passCache={}
local function finite(n) return type(n)=='number' and n==n and math.abs(n)<math.huge end
local function init(profile)
 local c=profile.cosmetics
 if type(c)~='table' then c={}; profile.cosmetics=c end
 c.tokens=c.tokens or 0; c.owned=c.owned or {}; c.equipped=c.equipped or {}
 c.passes=c.passes or {}; c.receipts=c.receipts or {}; c.support=c.support or 0
 c.owned.classic=true; c.owned.clean=true
 c.equipped.kit=c.equipped.kit or 'classic'; c.equipped.broadcast=c.equipped.broadcast or 'clean'
 return c
end
local function find(list,id)
 for _,entry in ipairs(list) do if entry.id==id then return entry end end
end
local function configured(entry)
 return entry and finite(entry.robloxId) and entry.robloxId>0 and entry.robloxId%1==0
end
function N.validateConfig()
 for _,kind in ipairs({'passes','products'}) do
  local ids={}; local keys={}
  for _,entry in ipairs(Config[kind]) do
   if type(entry.id)~='string' or keys[entry.id] then return false,'Duplicate catalog key' end
   keys[entry.id]=true
   if configured(entry) then
    if ids[entry.robloxId] then return false,'Duplicate Roblox ID' end
    ids[entry.robloxId]=true
   elseif entry.robloxId~=0 then return false,'Roblox ID must be a positive integer or 0' end
   for _,field in ipairs({'tokens','support'}) do
    if entry[field]~=nil and (not finite(entry[field]) or entry[field]<0 or entry[field]%1~=0) then return false,'Invalid grant amount' end
   end
  end
 end
 return true
end
local function changed(player)
 if context and context.onChanged then context.onChanged(player) end
end
local function transact(player,profile,mutate)
 if not context then return false,'SHOP_UNAVAILABLE' end
 local ok,result,code=context.storage.transaction(player,profile,mutate,context.copy)
 if not ok then return false,(type(result)=='string' and result or code) end
 changed(player); return true,result or 'COSMETIC_UPDATED'
end
function N.public(player,profile)
 local c=profile.cosmetics or {}
 local owned=c.owned or {}; local equipped=c.equipped or {}; local passes=c.passes or {}
 local catalog={}
 for _,item in ipairs(Config.items) do
  local row={id=item.id,kind='item',slot=item.slot,nameKey=item.nameKey,descriptionKey=item.descriptionKey,
   tokenCost=item.tokenCost,pass=item.pass,colors=item.colors,pattern=item.pattern,shape=item.shape,
   pitchColors=item.pitchColors,accent=item.accent,lighting=item.lighting,
   owned=owned[item.id]==true or item.tokenCost==0 or (item.pass and passes[item.pass]==true) or false,
   equipped=equipped[item.slot]==item.id,enabled=true}
  if item.pass and not passes[item.pass] then row.enabled=false end
  catalog[#catalog+1]=row
 end
 for _,kind in ipairs({'passes','products'}) do
  for _,entry in ipairs(Config[kind]) do
   catalog[#catalog+1]={id=entry.id,kind=kind=='passes' and 'pass' or 'product',
    nameKey=entry.nameKey,descriptionKey=entry.descriptionKey,robloxId=entry.robloxId,
    infoType=kind=='passes' and 'GamePass' or 'Product',enabled=configured(entry),
    owned=kind=='passes' and passes[entry.id]==true or false,tokens=entry.tokens,
    priceState=configured(entry) and 'CLIENT_REQUIRED' or 'NOT_CONFIGURED'}
  end
 end
 return {catalog=catalog,tokens=c.tokens or 0,owned=owned,equipped=equipped,passes=passes,support=c.support or 0}
end
function N.refreshPasses(player,profile,force)
 local now=os.clock(); local cached=passCache[player]
 if not force and cached and now-cached.time<60 then return true,'PASSES_CURRENT' end
 local entitlements={}
 for _,entry in ipairs(Config.passes) do
  if configured(entry) then
   local ok,owns=pcall(function() return MarketplaceService:UserOwnsGamePassAsync(player.UserId,entry.robloxId) end)
   if not ok then return false,'PASS_CHECK_FAILED' end
   entitlements[entry.id]=owns==true
  end
 end
 local ok,code=transact(player,profile,function(candidate)
  local c=init(candidate)
  for pass,owns in pairs(entitlements) do
   c.passes[pass]=owns
   local entry=find(Config.passes,pass)
   for _,id in ipairs(entry.items or {}) do
    c.owned[id]=owns or nil
    if not owns then
     local item=find(Config.items,id)
     if item and c.equipped[item.slot]==id then c.equipped[item.slot]=nil end
    end
   end
  end
  return true,'PASSES_CURRENT'
 end)
 if ok then passCache[player]={time=now} end
 return ok,code
end
function N.action(player,profile,action,arg)
 arg=arg or {}; local id=arg.id or arg.key
 if action=='refreshPasses' then return N.refreshPasses(player,profile,true) end
 if type(id)~='string' or #id>64 then return false,'SHOP_ITEM_INVALID' end
 if action=='purchase' then
  local entry=find(Config.products,id); local kind='product'
  if not entry then entry=find(Config.passes,id); kind='pass' end
  if not configured(entry) then return false,'PRODUCT_NOT_CONFIGURED' end
  if RunService:IsStudio() then return false,'STUDIO_PURCHASE_DISABLED' end
  local session=context and context.storage.sessions[player]
  if not session or session.temporary or session.lost then return false,'STORE_UNAVAILABLE' end
  if kind=='pass' then
   local ok,owns=pcall(function() return MarketplaceService:UserOwnsGamePassAsync(player.UserId,entry.robloxId) end)
   if not ok then return false,'PASS_CHECK_FAILED' end
   if owns then N.refreshPasses(player,profile,true); return false,'ALREADY_OWNED' end
  end
  local ok=pcall(function()
   if kind=='pass' then MarketplaceService:PromptGamePassPurchase(player,entry.robloxId)
   else MarketplaceService:PromptProductPurchase(player,entry.robloxId) end
  end)
  return ok,ok and 'PURCHASE_PROMPT' or 'PURCHASE_UNAVAILABLE'
 end
 local item=find(Config.items,id); if not item then return false,'SHOP_ITEM_INVALID' end
 if action=='cosmeticEquip' and item.pass then
  local checked,reason=N.refreshPasses(player,profile,false)
  if not checked then return false,reason end
 end
 if action=='cosmeticBuy' then
  return transact(player,profile,function(candidate)
   local c=init(candidate)
   if c.owned[id] then return false,'ALREADY_OWNED' end
   if item.pass then return false,'PASS_REQUIRED' end
   if not finite(c.tokens) or c.tokens<(item.tokenCost or 0) then return false,'TOKENS_REQUIRED' end
   c.tokens=c.tokens-(item.tokenCost or 0); c.owned[id]=true
   return true,'COSMETIC_OWNED'
  end)
 elseif action=='cosmeticEquip' then
  return transact(player,profile,function(candidate)
   local c=init(candidate)
   if not c.owned[id] and not (item.pass and c.passes[item.pass]) and item.tokenCost~=0 then return false,'COSMETIC_NOT_OWNED' end
   c.equipped[item.slot]=id;if item.slot=='kit'or item.slot=='crest'then c.design=nil end; return true,'COSMETIC_APPLIED'
  end)
 end
 return false,'SHOP_ACTION_INVALID'
end
local function receiptDecision(name) return Enum.ProductPurchaseDecision[name] end
function N.processReceipt(receipt)
 if not context or type(receipt)~='table' then return receiptDecision('NotProcessedYet') end
 local purchaseId=receipt.PurchaseId
 if type(purchaseId)~='string' or #purchaseId<1 or #purchaseId>Config.maxReceiptIdLength then return receiptDecision('NotProcessedYet') end
 local product=nil
 for _,entry in ipairs(Config.products) do
  if configured(entry) and entry.robloxId==receipt.ProductId then product=entry; break end
 end
 if not product or not finite(receipt.PlayerId) then return receiptDecision('NotProcessedYet') end
 local player=Players:GetPlayerByUserId(receipt.PlayerId)
 local profile=player and context.profiles[player]
 local session=player and context.storage.sessions[player]
 if not profile or not session or session.temporary or session.lost then return receiptDecision('NotProcessedYet') end
 local ok=context.storage.transaction(player,profile,function(candidate)
  local c=init(candidate)
  if c.receipts[purchaseId] then
   if c.receipts[purchaseId].productId~=receipt.ProductId then return false,'RECEIPT_CONFLICT' end
   return true,'RECEIPT_ALREADY_APPLIED'
  end
  if not finite(c.tokens) or c.tokens<0 or c.tokens+(product.tokens or 0)>Config.maxTokens then return false,'TOKEN_LIMIT' end
  c.tokens=c.tokens+(product.tokens or 0); c.support=c.support+(product.support or 0)
  -- Ledger is never trimmed: deleting old purchase IDs would re-enable grants.
  c.receipts[purchaseId]={productId=receipt.ProductId,grantedAt=os.time()}
  return true,'RECEIPT_APPLIED'
 end,context.copy)
 if not ok then return receiptDecision('NotProcessedYet') end
 changed(player)
 return receiptDecision('PurchaseGranted')
end
function N.bind(options)
 assert(not bound,'Touchline receipt handler is already installed')
 assert(options and options.storage and options.profiles and options.copy,'Monetization adapters required')
 local valid,reason=N.validateConfig(); assert(valid,reason)
 context=options; bound=true
 MarketplaceService.ProcessReceipt=N.processReceipt
 MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(player,passId,wasPurchased)
  if not wasPurchased then return end
  for _,entry in ipairs(Config.passes) do
   if configured(entry) and entry.robloxId==passId and options.profiles[player] then
    -- Prompt completion only triggers fresh SERVER ownership verification.
    N.refreshPasses(player,options.profiles[player],true); break
   end
  end
 end)
 Players.PlayerRemoving:Connect(function(player) passCache[player]=nil end)
 return N
end
return N
]========],server)
put('ModuleScript','MonetizationConfig',[========[-- Owner configuration. 0 is deliberately DISABLED, never a mock live ID.
-- Prices are fetched by the client using GetProductInfoAsync (personalized).
local K={}
K.passes={
 {id='identity',robloxId=0,nameKey='shop.identity',descriptionKey='shop.identity_desc',items={'hoops','crest_star'}},
 {id='stadium',robloxId=0,nameKey='shop.stadium',descriptionKey='shop.stadium_desc',items={'designer'}},
 {id='broadcast',robloxId=0,nameKey='shop.broadcast',descriptionKey='shop.broadcast_desc',items={'broadcast_pro'}},
 {id='supporter',robloxId=0,nameKey='shop.supporter',descriptionKey='shop.supporter_desc',items={'supporter_badge'}},
}
K.products={
 {id='tokens_s',robloxId=0,nameKey='shop.tokens_s',descriptionKey='shop.tokens_only',tokens=100},
 {id='tokens_m',robloxId=0,nameKey='shop.tokens_m',descriptionKey='shop.tokens_only',tokens=300},
 {id='tokens_l',robloxId=0,nameKey='shop.tokens_l',descriptionKey='shop.tokens_only',tokens=800},
 {id='donation_s',robloxId=0,nameKey='shop.donation_s',descriptionKey='shop.donation_desc',support=1},
 {id='donation_m',robloxId=0,nameKey='shop.donation_m',descriptionKey='shop.donation_desc',support=1},
 {id='donation_l',robloxId=0,nameKey='shop.donation_l',descriptionKey='shop.donation_desc',support=1},
}
K.items={
 {id='classic',slot='kit',tokenCost=0,nameKey='shop.classic',descriptionKey='shop.kit_desc',colors={190,243,103},pattern='solid'},
 {id='lime',slot='kit',tokenCost=30,nameKey='shop.lime',descriptionKey='shop.kit_desc',colors={125,235,151},pattern='stripe'},
 {id='sunset',slot='kit',tokenCost=60,nameKey='shop.sunset',descriptionKey='shop.kit_desc',colors={255,144,91},pattern='sash'},
 {id='hoops',slot='kit',pass='identity',nameKey='shop.hoops',descriptionKey='shop.kit_desc',colors={88,185,246},pattern='hoops'},
 {id='crest_star',slot='crest',pass='identity',nameKey='shop.crest_star',descriptionKey='shop.crest_desc',shape='star'},
 {id='night',slot='stadium',tokenCost=80,nameKey='shop.night',descriptionKey='shop.stadium_cosmetic',pitchColors={20,69,62},lighting='night'},
 {id='designer',slot='stadium',pass='stadium',nameKey='shop.designer',descriptionKey='shop.stadium_cosmetic',pitchColors={34,104,76},lighting='floodlights'},
 {id='clean',slot='broadcast',tokenCost=0,nameKey='shop.clean',descriptionKey='shop.broadcast_cosmetic',accent={190,243,103}},
 {id='broadcast_pro',slot='broadcast',pass='broadcast',nameKey='shop.broadcast_pro',descriptionKey='shop.broadcast_cosmetic',accent={97,190,255}},
 {id='supporter_badge',slot='badge',pass='supporter',nameKey='shop.supporter_badge',descriptionKey='shop.badge_desc',colors={237,198,92}},
}
K.editorPalettes={{190,243,103},{87,157,219},{255,144,91},{164,93,183},{47,177,165},{237,198,92},{239,245,247},{22,32,48}}
K.maxTokens=1000000000
K.maxReceiptIdLength=160
return K
]========],shared)
put('ModuleScript','MonetizationConfig',[========[-- Owner configuration. 0 is deliberately DISABLED, never a mock live ID.
-- Prices are fetched by the client using GetProductInfoAsync (personalized).
local K={}
K.passes={
 {id='identity',robloxId=0,nameKey='shop.identity',descriptionKey='shop.identity_desc',items={'hoops','crest_star'}},
 {id='stadium',robloxId=0,nameKey='shop.stadium',descriptionKey='shop.stadium_desc',items={'designer'}},
 {id='broadcast',robloxId=0,nameKey='shop.broadcast',descriptionKey='shop.broadcast_desc',items={'broadcast_pro'}},
 {id='supporter',robloxId=0,nameKey='shop.supporter',descriptionKey='shop.supporter_desc',items={'supporter_badge'}},
}
K.products={
 {id='tokens_s',robloxId=0,nameKey='shop.tokens_s',descriptionKey='shop.tokens_only',tokens=100},
 {id='tokens_m',robloxId=0,nameKey='shop.tokens_m',descriptionKey='shop.tokens_only',tokens=300},
 {id='tokens_l',robloxId=0,nameKey='shop.tokens_l',descriptionKey='shop.tokens_only',tokens=800},
 {id='donation_s',robloxId=0,nameKey='shop.donation_s',descriptionKey='shop.donation_desc',support=1},
 {id='donation_m',robloxId=0,nameKey='shop.donation_m',descriptionKey='shop.donation_desc',support=1},
 {id='donation_l',robloxId=0,nameKey='shop.donation_l',descriptionKey='shop.donation_desc',support=1},
}
K.items={
 {id='classic',slot='kit',tokenCost=0,nameKey='shop.classic',descriptionKey='shop.kit_desc',colors={190,243,103},pattern='solid'},
 {id='lime',slot='kit',tokenCost=30,nameKey='shop.lime',descriptionKey='shop.kit_desc',colors={125,235,151},pattern='stripe'},
 {id='sunset',slot='kit',tokenCost=60,nameKey='shop.sunset',descriptionKey='shop.kit_desc',colors={255,144,91},pattern='sash'},
 {id='hoops',slot='kit',pass='identity',nameKey='shop.hoops',descriptionKey='shop.kit_desc',colors={88,185,246},pattern='hoops'},
 {id='crest_star',slot='crest',pass='identity',nameKey='shop.crest_star',descriptionKey='shop.crest_desc',shape='star'},
 {id='night',slot='stadium',tokenCost=80,nameKey='shop.night',descriptionKey='shop.stadium_cosmetic',pitchColors={20,69,62},lighting='night'},
 {id='designer',slot='stadium',pass='stadium',nameKey='shop.designer',descriptionKey='shop.stadium_cosmetic',pitchColors={34,104,76},lighting='floodlights'},
 {id='clean',slot='broadcast',tokenCost=0,nameKey='shop.clean',descriptionKey='shop.broadcast_cosmetic',accent={190,243,103}},
 {id='broadcast_pro',slot='broadcast',pass='broadcast',nameKey='shop.broadcast_pro',descriptionKey='shop.broadcast_cosmetic',accent={97,190,255}},
 {id='supporter_badge',slot='badge',pass='supporter',nameKey='shop.supporter_badge',descriptionKey='shop.badge_desc',colors={237,198,92}},
}
K.editorPalettes={{190,243,103},{87,157,219},{255,144,91},{164,93,183},{47,177,165},{237,198,92},{239,245,247},{22,32,48}}
K.maxTokens=1000000000
K.maxReceiptIdLength=160
return K
]========],server)
put('ModuleScript','Players',[========[-- Pure footballer model. OVR is a role summary; matches also consume individual attributes.
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
]========],server)
put('ModuleScript','Records',[========[-- Categories never mix difficulty or control modes. Optional global adapter.
local R={}
local modes={manual=true,highlights=true,simulate=true}
local difficulty={easy=true,normal=true,hard=true}
function R.category(mode,level)
 if not modes[mode] or not difficulty[level] then return nil end
 return mode..'_'..level
end
function R.record(p,result)
 if result.training or result.forfeit then return end
 local key=R.category(result.mode,p.difficulty);if not key then return end
 p.records.categories=p.records.categories or {};local row=p.records.categories[key] or {played=0,wins=0,points=0};p.records.categories[key]=row
 row.played=row.played+1
 local win=result.home>result.away or result.penWin==true
 if win then row.wins=row.wins+1;row.points=row.points+3 elseif result.home==result.away then row.points=row.points+1 end
end
function R.adapter(service,isStudio,clock)
 clock=clock or os.clock
 local lastWrite,lastRead,cache={},{},{}
 local prefix=isStudio and 'TD_TEST_records_v2_' or 'TD_records_v2_'
 local adapter={}
 function adapter.publish(userId,key,points)
  if type(key)~='string' then return false,'INVALID_RECORD' end
  if not R.category(key:match('^(.*)_'),key:match('_([^_]+)$')) or type(userId)~='number' or userId%1~=0 or type(points)~='number' or points~=points or points<0 or points>1000000 or points%1~=0 then return false,'INVALID_RECORD' end
  local token=userId..':'..key;if lastWrite[token] and clock()-lastWrite[token]<120 then return false,'RECORD_COOLDOWN' end
  lastWrite[token]=clock()
  local ok=pcall(function() service:GetOrderedDataStore(prefix..key):UpdateAsync(tostring(userId),function(old)return math.max(type(old)=='number' and old or 0,points)end)end)
  if not ok then lastWrite[token]=nil end
  return ok,ok and 'SAVED' or 'STORE_UNAVAILABLE'
 end
 function adapter.read(mode,level)
  local key=R.category(mode,level);if not key then return nil,'INVALID_RECORD' end
  if lastRead[key] and clock()-lastRead[key]<60 then return cache[key] or {},'CACHED' end
  lastRead[key]=clock()
  local ok,rows=pcall(function()return service:GetOrderedDataStore(prefix..key):GetSortedAsync(false,10):GetCurrentPage()end)
  if not ok then lastRead[key]=nil;return nil,'STORE_UNAVAILABLE' end
  local out={};for _,row in ipairs(rows)do if type(row.value)=='number' and row.value>=0 and row.value<=1000000 then out[#out+1]={userId=tostring(row.key),points=row.value}end end
  cache[key]=out;return out,'SAVED'
 end
 function adapter.clear(userId)for key in pairs(lastWrite)do if key:sub(1,#tostring(userId)+1)==tostring(userId)..':'then lastWrite[key]=nil end end end
 return adapter
end
return R
]========],server)
put('ModuleScript','Results',[========[-- Result navigation reuses stored statistics; it never replays a simulation.
local R={}
function R.show(ui,tr,data,profile,onContinue)
 local function open()
  local s=data.stats or {};local teams=s.teams;local body=tostring(data.home)..' : '..tostring(data.away)..'  '..tostring(data.op)..'\n'..tr:t('ui.income')..' '..tr:money(data.income or 0)..' · '..tr:t('ui.expenses')..' '..tr:money(data.costs or 0)..'\n'..tr:t('ui.net')..' '..tr:money(data.net or 0)
  if teams then for _,field in ipairs({'shots','onTarget','passAccuracy','possessionPercent','yellow','red'})do body=body..'\n'..tr:t('report.'..field)..': '..tostring(teams[1][field]or 0)..' : '..tostring(teams[2][field]or 0)end end
  if s.playerOfMatch then body=body..'\n'..tr:t('ui.playerOfMatch')..': '..s.playerOfMatch.name..' ('..s.playerOfMatch.rating..')'end
  if data.training then body=body..'\n'..tr:t(data.training.success and 'training.success' or 'training.ended')..' · '..tr:t('ui.tokens')..' +'..tostring(data.cosmeticReward or 0)end
  if s.shootout then body=body..'\n'..tr:t('report.shootout',{home=s.shootout.scores[1],away=s.shootout.scores[2]})end
  if data.technical then body=body..'\n'..tr:t('report.technical')elseif data.forfeit then body=body..'\n'..tr:t('match.forfeit')end
  local actions={{label=tr:t('ui.continue'),callback=onContinue}}
  if teams then
   actions[#actions+1]={label=tr:t('report.ratings'),callback=function()
    local lines={};for _,q in ipairs(profile and profile.roster or {})do if s.ratings and s.ratings[q.id]then lines[#lines+1]=q.name..' · '..tostring(s.ratings[q.id])end end
    ui:modal(tr:t('report.ratings'),table.concat(lines,'\n'),{{label=tr:t('report.back'),callback=open}})
   end}
   actions[#actions+1]={label=tr:t('report.factors'),callback=function()
    local lines={tr:t(data.neutral and 'report.neutral'or data.venueHome and 'report.home' or 'report.away'),tr:t('difficulty.'..((profile or {}).difficulty or 'normal')),tr:t('style.'..((profile or {}).style or 'counter'))}
    if teams[1].red>0 then lines[#lines+1]=tr:t('report.dismissal')end
    lines[#lines+1]=tr:t(teams[1].onTarget>=teams[2].onTarget and 'report.moreShots' or 'report.fewerShots')
    ui:modal(tr:t('report.factors'),table.concat(lines,'\n'),{{label=tr:t('report.back'),callback=open}})
   end}
  end
  ui:modal(tr:t('ui.result'),body,actions)
 end
 open()
end
return R
]========],shared)
put('Script','Main',[========[local Players=game:GetService('Players')
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
]========],server)
put('ModuleScript','Storage',[========[-- Authoritative profile store. Saves, finalization and receipts share one queue.
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
]========],server)
put('ModuleScript','StudioQA',[========[-- Owner-operated server diagnostics. Never runs automatically or in a live server.
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
]========],server)
put('ModuleScript','Tournaments',[========[local W=require(script.Parent.World)
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
]========],server)
put('ModuleScript','Training',[========[-- Isolated practice: no league calendar, wages, XP or club money mutations.
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
]========],server)
put('ModuleScript','UI',[========[-- Retained responsive shell and virtual list. No domain calculations run per frame.
local UI={}
UI.colors={bg=Color3.fromRGB(10,17,28),panel=Color3.fromRGB(19,30,45),card=Color3.fromRGB(28,43,60),text=Color3.fromRGB(239,245,247),muted=Color3.fromRGB(164,183,200),lime=Color3.fromRGB(194,242,102),red=Color3.fromRGB(255,133,139),blue=Color3.fromRGB(104,190,242)}
function UI.make(class,props,parent)
 local obj=Instance.new(class);if class=='TextLabel'or class=='TextButton'or class=='TextBox'then obj.AutoLocalize=false end; for key,value in pairs(props or {}) do obj[key]=value end; obj.Parent=parent; return obj
end
function UI.round(obj,r) UI.make('UICorner',{CornerRadius=UDim.new(0,r or 10)},obj); return obj end
function UI.frame(parent,name,bg)
 return UI.make('Frame',{Name=name,BackgroundColor3=bg or UI.colors.panel,BorderSizePixel=0},parent)
end
function UI.label(parent,text,size,bold)
 return UI.make('TextLabel',{Text=text or '',BackgroundTransparency=1,TextColor3=UI.colors.text,TextSize=size or 16,Font=bold and Enum.Font.GothamBold or Enum.Font.Gotham,TextWrapped=true,TextXAlignment=Enum.TextXAlignment.Left,TextYAlignment=Enum.TextYAlignment.Center},parent)
end
function UI.button(parent,text,callback,primary)
 local b=UI.round(UI.make('TextButton',{Text=text or '',BackgroundColor3=primary and UI.colors.lime or UI.colors.card,TextColor3=primary and UI.colors.bg or UI.colors.text,BorderSizePixel=0,Font=Enum.Font.GothamBold,TextSize=14,TextWrapped=true,AutoButtonColor=true,Selectable=true},parent))
 local state={callback=callback,enabled=true,nextAllowed=0}; b.Activated:Connect(function() if state.enabled and state.callback and os.clock()>=state.nextAllowed then state.nextAllowed=os.clock()+.3;state.callback() end end)
 return b,state
end
local groups={
 {id='club',pages={'hub','inbox','calendar'}},{id='team',pages={'squad','tactics','academy','training'}},
 {id='football',pages={'table','cup'}},{id='business',pages={'market','scout','stadium','finances'}},
 {id='career',pages={'history','goals'}},{id='identity',pages={'shop','inventory','settings','help'}}
}
UI.groups=groups
function UI.new(player,tr,handlers)
 local self={tr=tr,handlers=handlers,pages={},current='hub',group='club',mobile=false,textScale=1,profile=nil,filters={},connections={},nav={},tabs={},dead=false}
 setmetatable(self,{__index=UI})
 self.gui=UI.make('ScreenGui',{Name='TouchlineDynasty',ResetOnSpawn=false,IgnoreGuiInset=false,ZIndexBehavior=Enum.ZIndexBehavior.Sibling},player:WaitForChild('PlayerGui'))
 pcall(function() self.gui.ClipToDeviceSafeArea=true end)
 self.root=UI.frame(self.gui,'Shell',UI.colors.bg); self.root.Size=UDim2.fromScale(1,1)
 self.header=UI.frame(self.root,'Header',UI.colors.panel); self.brand=UI.label(self.header,'TOUCHLINE DYNASTY',19,true)
 self.club=UI.label(self.header,'',14,false); self.budget=UI.label(self.header,'',14,true)
 self.sidebar=UI.frame(self.root,'Navigation',UI.colors.panel)
 self.tabbar=UI.make('ScrollingFrame',{Name='Sections',BackgroundTransparency=1,BorderSizePixel=0,ScrollBarThickness=0,ScrollingDirection=Enum.ScrollingDirection.X,CanvasSize=UDim2.fromOffset(900,0)},self.root)
 self.title=UI.label(self.root,'',24,true)
 self.search=UI.make('TextBox',{Name='Search',PlaceholderText=tr:t('ui.search'),Text='',ClearTextOnFocus=false,TextColor3=UI.colors.text,PlaceholderColor3=UI.colors.muted,TextSize=16,Font=Enum.Font.Gotham,BackgroundColor3=UI.colors.card,BorderSizePixel=0},self.root); UI.round(self.search)
 self.filter,self.filterState=UI.button(self.root,'',function() self:cycleFilter() end)
 self.sort,self.sortState=UI.button(self.root,'',function() self:cycleSort() end)
 self.toast=UI.round(UI.frame(self.root,'Notification',UI.colors.card)); self.toast.Visible=false; self.toast.ZIndex=30
 self.toastText=UI.label(self.toast,'',16,false); self.toastText.Size=UDim2.new(1,-24,1,0); self.toastText.Position=UDim2.fromOffset(12,0); self.toastText.ZIndex=31
 for i,g in ipairs(groups) do
  local id=g.id; local b,state=UI.button(self.sidebar,tr:t('ui.'..id),function() self:open(g.pages[1]) end)
  self.nav[i]={button=b,state=state,id=id}
 end
 self.search:GetPropertyChangedSignal('Text'):Connect(function()
  local f=self.filters[self.current] or {position=1,sort=1}; self.filters[self.current]=f; f.query=self.search.Text; self:refresh(false)
 end)
 self.connections[#self.connections+1]=workspace.CurrentCamera:GetPropertyChangedSignal('ViewportSize'):Connect(function() self:resize() end)
 self:resize(); self:open('hub'); return self
end
function UI:resize()
 local viewport=workspace.CurrentCamera.ViewportSize; self.width,self.height=viewport.X,viewport.Y; self.mobile=viewport.X<850
 local side=self.mobile and 0 or 184; local pad=self.mobile and 12 or 24; local navH=self.mobile and 64 or 0
 self.contentX=side+pad; self.contentW=math.max(220,viewport.X-side-pad*2)
 self.header.Position=UDim2.fromOffset(side,0); self.header.Size=UDim2.new(1,-side,0,76)
 self.brand.Position=UDim2.fromOffset(pad,10); self.brand.Size=UDim2.new(.58,-pad,0,26)
 self.club.Position=UDim2.fromOffset(pad,39); self.club.Size=UDim2.new(.62,-pad,0,26)
 self.budget.Position=UDim2.new(.62,0,0,22); self.budget.Size=UDim2.new(.38,-pad,0,40)
 self.sidebar.Position=self.mobile and UDim2.new(0,0,1,-64) or UDim2.fromOffset(0,0)
 self.sidebar.Size=self.mobile and UDim2.new(1,0,0,64) or UDim2.new(0,184,1,0)
 for i,n in ipairs(self.nav) do
  n.button.Position=self.mobile and UDim2.new((i-1)/6,2,0,5) or UDim2.fromOffset(12,84+(i-1)*60)
  n.button.Size=self.mobile and UDim2.new(1/6,-4,0,54) or UDim2.fromOffset(160,48); n.button.TextSize=self.mobile and 11 or 15
 end
 self.tabbar.Position=UDim2.fromOffset(self.contentX,80); self.tabbar.Size=UDim2.fromOffset(self.contentW,48)
 self.title.Position=UDim2.fromOffset(self.contentX,136); self.title.Size=UDim2.fromOffset(self.contentW,34)
 self.search.Position=UDim2.fromOffset(self.contentX,178); self.search.Size=UDim2.new(0,math.max(100,self.contentW-206),0,46)
 self.filter.Position=UDim2.fromOffset(self.contentX+self.contentW-198,178); self.filter.Size=UDim2.fromOffset(94,46)
 self.sort.Position=UDim2.fromOffset(self.contentX+self.contentW-98,178); self.sort.Size=UDim2.fromOffset(98,46)
 self.listY=234; self.listH=math.max(80,viewport.Y-self.listY-navH-12)
 for _,page in pairs(self.pages) do page.frame.Position=UDim2.fromOffset(self.contentX,self.listY); page.frame.Size=UDim2.fromOffset(self.contentW,self.listH) end
 self.toast.Position=UDim2.new(.5,-math.min(260,(viewport.X-24)/2),1,-navH-84); self.toast.Size=UDim2.fromOffset(math.min(520,viewport.X-24),64)
 self:refresh(false)
end
function UI:clearSelection()
 pcall(function()game:GetService('GuiService').SelectedObject=nil end)
end
function UI:selectDefault()
 if self.matchActive then return end
 local page=self.pages[self.current];local row=page and page.rows[1];local action=row and row.actions[1]
 local button=action and action.button.Visible and action.state.enabled and action.button or self.nav[1].button
 pcall(function()local service=game:GetService('GuiService');service.AutoSelectGuiEnabled=true;service.SelectedObject=button end)
end
function UI:open(page)
 self.current=page
 for _,g in ipairs(groups) do for _,id in ipairs(g.pages) do if id==page then self.group=g.id end end end
 for id,p in pairs(self.pages) do p.frame.Visible=id==page end
 if not self.pages[page] then
  local f=UI.make('ScrollingFrame',{Name=page,BackgroundTransparency=1,BorderSizePixel=0,ScrollBarThickness=4,ScrollBarImageColor3=UI.colors.muted,CanvasSize=UDim2.fromOffset(0,0),Position=UDim2.fromOffset(self.contentX,self.listY),Size=UDim2.fromOffset(self.contentW,self.listH)},self.root)
  local p={frame=f,rows={},items={}}; self.pages[page]=p
  f:GetPropertyChangedSignal('CanvasPosition'):Connect(function() if self.current==page then self:paint() end end)
 end
 self.pages[page].frame.Visible=true
 for _,tab in ipairs(self.tabs) do tab.button.Visible=false end
 local chosen
 for _,g in ipairs(groups) do if g.id==self.group then chosen=g end end
 if chosen then
  for i,id in ipairs(chosen.pages) do
   if not self.tabs[i] then local b,s=UI.button(self.tabbar,'',nil); self.tabs[i]={button=b,state=s} end
   local tab=self.tabs[i]; tab.button.Visible=true; tab.button.Text=self.tr:t('ui.'..id); tab.button.Position=UDim2.fromOffset((i-1)*132,0); tab.button.Size=UDim2.fromOffset(124,46)
   tab.button.BackgroundColor3=id==page and UI.colors.lime or UI.colors.card; tab.button.TextColor3=id==page and UI.colors.bg or UI.colors.text
   tab.state.callback=function() self:open(id) end
  end
  self.tabbar.CanvasSize=UDim2.fromOffset(#chosen.pages*132,0)
 end
 for _,n in ipairs(self.nav) do n.button.BackgroundColor3=n.id==self.group and UI.colors.card or UI.colors.panel end
 local filter=self.filters[page] or {position=1,sort=1,query=''}; self.filters[page]=filter; self.search.Text=filter.query or ''
 self:refresh(false);self:selectDefault()
end
function UI:cycleFilter()
 local f=self.filters[self.current]; f.position=((f.position or 1)%5)+1; self:refresh(false)
end
function UI:cycleSort()
 local f=self.filters[self.current]; f.sort=((f.sort or 1)%6)+1; self:refresh(false)
end
function UI:refresh(reset)
 if not self.pages[self.current] then return end
 local p=self.profile; self.brand.Text='TOUCHLINE DYNASTY'
 self.club.Text=p and (p.club..'  ·  '..self.tr:t('ui.season')..' '..tostring(p.season)..' / '..tostring(p.division)) or self.tr:t('ui.loading')
 self.budget.Text=p and self.tr:money(p.cash or 0) or ''
 self.title.Text=self.tr:t('ui.'..self.current)
 local f=self.filters[self.current] or {position=1,sort=1,query=''}; local positions={'all','GK','DEF','MID','FWD'}
 self.filter.Text=self.tr:t(positions[f.position or 1]=='all' and 'ui.all' or ('position.'..positions[f.position or 1]))
 self.sort.Text=self.tr:t('ui.'..({'name','rating','age','price','wage','contract'})[f.sort or 1])
 local searchable=self.current=='market' or self.current=='squad' or self.current=='scout'
 self.search.Visible=searchable; self.filter.Visible=searchable; self.sort.Visible=searchable
 local listY=searchable and 234 or 180; self.listY=listY; self.listH=math.max(80,self.height-listY-(self.mobile and 76 or 12))
 local page=self.pages[self.current]; page.frame.Position=UDim2.fromOffset(self.contentX,listY); page.frame.Size=UDim2.fromOffset(self.contentW,self.listH)
 local items=self.handlers.items(self.current,p,f,self) or {}; page.items=items
 self.rowH=self.mobile and math.floor(214*self.textScale) or math.floor(156*self.textScale)
 page.frame.CanvasSize=UDim2.fromOffset(0,#items*self.rowH+12)
 if reset then page.frame.CanvasPosition=Vector2.new(0,0) end
 self:paint()
end
function UI:paint()
 local page=self.pages[self.current]; if not page then return end
 local offset=page.frame.CanvasPosition and page.frame.CanvasPosition.Y or 0; local first=math.max(1,math.floor(offset/self.rowH)+1)
 local visible=math.min(24,math.ceil(self.listH/self.rowH)+2)
 for i=1,visible do
  local row=page.rows[i]
  if not row then
   row={}; row.frame=UI.round(UI.frame(page.frame,'Row'..i,UI.colors.panel)); row.title=UI.label(row.frame,'',18,true); row.body=UI.label(row.frame,'',14,false); row.body.TextColor3=UI.colors.muted; row.actions={}
   row.title.Position=UDim2.fromOffset(14,8); row.title.Size=UDim2.new(1,-28,0,38)
   row.body.Position=UDim2.fromOffset(14,48); row.body.Size=UDim2.new(1,-28,1,-110)
   for a=1,4 do local b,s=UI.button(row.frame,'',nil); row.actions[a]={button=b,state=s} end
   page.rows[i]=row
  end
  local index=first+i-1; local entry=page.items[index]; row.frame.Visible=entry~=nil
  if entry then
   row.frame.Position=UDim2.fromOffset(0,(index-1)*self.rowH); row.frame.Size=UDim2.new(1,-8,0,self.rowH-10)
   row.title.Text=entry.title or ''; row.title.TextSize=math.floor(18*self.textScale); row.body.Text=entry.body or ''; row.body.TextSize=math.floor(14*self.textScale)
   row.frame.BackgroundColor3=entry.highlight and UI.colors.card or UI.colors.panel
   local actions=entry.actions or {}; local n=math.max(1,math.min(4,#actions))
   for a,slot in ipairs(row.actions) do
    local action=actions[a]; slot.button.Visible=action~=nil
    if action then
     slot.button.Text=action.label; slot.button.Position=UDim2.new((a-1)/n,7,1,-53); slot.button.Size=UDim2.new(1/n,-14,0,46)
     slot.button.TextSize=math.floor((self.mobile and 12 or 14)*self.textScale); slot.button.BackgroundColor3=action.primary and UI.colors.lime or UI.colors.card
     slot.button.TextColor3=action.primary and UI.colors.bg or (action.danger and UI.colors.red or UI.colors.text)
     slot.state.enabled=action.enabled~=false; slot.button.AutoButtonColor=slot.state.enabled; slot.button.TextTransparency=slot.state.enabled and 0 or .5
     slot.state.callback=action.callback
    end
   end
  end
 end
 for i=visible+1,#page.rows do page.rows[i].frame.Visible=false end
end
function UI:update(profile)
 self.profile=profile;for _,n in ipairs(self.nav)do n.button.Text=self.tr:t('ui.'..n.id)end;self.search.PlaceholderText=self.tr:t('ui.search'); self.textScale=math.max(.9,math.min(1.35,profile.settings and profile.settings.textScale or 1)); self:open(self.current)
end
function UI:message(text)
 self.toastText.Text=text; self.toast.Visible=true; self.toastToken=(self.toastToken or 0)+1; local token=self.toastToken
 task.delay(5,function() if not self.dead and self.toastToken==token then self.toast.Visible=false end end)
end
function UI:modal(title,body,actions)
 if self.modalFrame then self.modalFrame:Destroy() end
 local veil=UI.make('Frame',{Name='Dialog',Size=UDim2.fromScale(1,1),BackgroundColor3=UI.colors.bg,BackgroundTransparency=.15,Active=true,ZIndex=50},self.gui); self.modalFrame=veil
 local width=math.min(610,self.width-24); local panel=UI.round(UI.frame(veil,'Panel',UI.colors.panel)); panel.AnchorPoint=Vector2.new(.5,.5); panel.Position=UDim2.fromScale(.5,.5); panel.Size=UDim2.fromOffset(width,math.min(520,self.height-30)); panel.ZIndex=51
 local heading=UI.label(panel,title,23,true); heading.Position=UDim2.fromOffset(20,12); heading.Size=UDim2.new(1,-40,0,56); heading.ZIndex=52
 local bodyFrame=UI.make('ScrollingFrame',{Name='DialogBody',Position=UDim2.fromOffset(20,76),Size=UDim2.new(1,-40,1,-210),BackgroundTransparency=1,BorderSizePixel=0,ScrollBarThickness=4,CanvasSize=UDim2.fromOffset(0,0),AutomaticCanvasSize=Enum.AutomaticSize.Y,ZIndex=52},panel)
 local text=UI.label(bodyFrame,body,16,false);text.Size=UDim2.new(1,-8,0,0);text.AutomaticSize=Enum.AutomaticSize.Y;text.TextYAlignment=Enum.TextYAlignment.Top;text.ZIndex=52
 local count=math.min(4,#actions)
 for i=1,count do
  local action=actions[i]; local b=UI.button(panel,action.label,function() veil:Destroy(); self.modalFrame=nil;self:clearSelection(); if action.callback then action.callback() end;if not self.modalFrame then self:selectDefault()end end,action.primary)
  local col=(i-1)%2; local row=math.floor((i-1)/2); b.Position=UDim2.new(col/2,12,1,-122+row*58); b.Size=UDim2.new(.5,-24,0,50); b.ZIndex=53;if i==1 then pcall(function()game:GetService('GuiService').SelectedObject=b end)end
 end
 return veil
end
function UI:destroy()
 self.dead=true; for _,c in ipairs(self.connections) do c:Disconnect() end; self.gui:Destroy()
end
return UI
]========],shared)
put('ModuleScript','World',[========[local Config=require(script.Parent.WorldConfig)
local P=require(script.Parent.Players)
local W={START_COUNTRY=Config.START_COUNTRY,START_CLUB=Config.START_CLUB,config=Config}
local function copy(v) if type(v)~='table' then return v end local o={} for k,x in pairs(v) do o[k]=copy(x) end return o end
local function clamp(x,a,b) return math.max(a,math.min(b,x)) end
function W.rng(seed)
 local n=math.max(1,math.floor(seed or 1)%2147483647)
 return function(a,b) n=n*48271%2147483647; local x=n/2147483647; if a then return math.floor(a+x*(b-a+1)) end return x end
end
function W.hash(s)
 local n=5381; for i=1,#tostring(s) do n=(n*33+string.byte(tostring(s),i))%2147483647 end return n
end
function W.club(world,id) return world.clubs[id] end
function W.country(id)
 for _,country in ipairs(Config.COUNTRIES) do if country.id==id then return country end end
end
function W.league(world,country,division)
 if type(country)=='number' then country=Config.COUNTRIES[country] and Config.COUNTRIES[country].id end
 local out={}; local divisions=world.leagues[country]; if not divisions then return out end
 for _,id in ipairs(divisions[division] or {}) do out[#out+1]=world.clubs[id] end return out
end
function W.new(seed)
 local world={seed=seed or 1,season=1,clubs={},leagues={},cupWinners={},qualifications={champions={},challenge={}},supercups={},history={},records={seasons=0}}
 local mascots={'Rovers','Athletic','United','Wanderers','City','Olympic'}
 for ci,country in ipairs(Config.COUNTRIES) do
  world.leagues[country.id]={}
  for division=1,country.divisions do
   local ids={}; world.leagues[country.id][division]=ids
   for slot=1,16 do
    local index=(division-1)*16+slot; local id=country.id..'_'..string.format('%03d',index)
    local rng=W.rng((seed or 1)+ci*9701+index*101)
    local rating=clamp(country.base-(division-1)*7+rng(-5,4),36,91)
    world.clubs[id]={id=id,name=country.cities[slot]..' '..mascots[division],country=country.id,division=division,rating=rating,
     style=({development='possession',pressing='press',possession='possession',compact='lowblock',wings='wings',physical='press',counter='counter',technical='possession'})[country.culture],formation=country.culture=='compact'and'5-3-2'or country.culture=='counter'and'4-4-2'or'4-3-3',colors={copy(country.color),{rng(190,245),rng(190,245),rng(190,245)}},crest={shape=({'shield','round','diamond'})[1+(index%3)],symbol=1+(index%8)},
     reputation=clamp(rating*1.05+rng(-5,5),15,99),infrastructure={stadium=math.max(1,7-division),training=math.max(1,6-division),academy=1+(index%4)},
     financialClass=math.max(1,7-division),cash=math.floor(180000*(7-division)^2),squadSeed=rng(1,2147483000),generation=1,averageAge=rng(23,29),
     records={leagueTitles=0,cups=0,wins=0,played=0,bestRating=rating},rival=country.id..'_'..string.format('%03d',(division-1)*16+(slot%16+1))}
    ids[#ids+1]=id
   end
  end
 end
 return world
end
function W.schedule(input)
 local ring={}; for i,v in ipairs(input or {}) do ring[i]=type(v)=='table' and v.id or v end
 assert(#ring>=2 and #ring%2==0,'Even number of clubs required')
 local n=#ring; local rounds={}
 for r=1,n-1 do
  local games={}
  for i=1,n/2 do local a,b=ring[i],ring[n+1-i]; if (r+i)%2==0 then a,b=b,a end games[#games+1]={a,b} end
  rounds[r]=games; table.insert(ring,2,table.remove(ring))
 end
 for r=1,n-1 do local games={}; for _,g in ipairs(rounds[r]) do games[#games+1]={g[2],g[1]} end rounds[r+n-1]=games end
 return rounds
end
local function row(club) return {id=club.id,name=club.name,rating=club.rating,pts=0,gf=0,ga=0,w=0,d=0,l=0,played=0} end
function W.record(a,b,x,y)
 a.played=a.played+1; b.played=b.played+1; a.gf=a.gf+x; a.ga=a.ga+y; b.gf=b.gf+y; b.ga=b.ga+x
 if x>y then a.pts=a.pts+3; a.w=a.w+1; b.l=b.l+1 elseif x<y then b.pts=b.pts+3; b.w=b.w+1; a.l=a.l+1 else a.pts=a.pts+1; b.pts=b.pts+1; a.d=a.d+1; b.d=b.d+1 end
end
function W.sorted(rows)
 local out=copy(rows)
 table.sort(out,function(a,b) if a.pts~=b.pts then return a.pts>b.pts end local ag,bg=a.gf-a.ga,b.gf-b.ga; if ag~=bg then return ag>bg end if a.gf~=b.gf then return a.gf>b.gf end return a.id<b.id end)
 return out
end
-- Score model shared by distant competition scheduling; always uses the actual home side.
function W.simScore(rng,a,b,neutral,fraction)
 local function goals(lambda) local k,p=0,1; local l=math.exp(-lambda); repeat k=k+1; p=p*rng() until p<=l or k>10; return k-1 end
 local scale=fraction or 1
 return goals(clamp((neutral and 1.295 or 1.42)+(a-b)*.043,.2,4.8)*scale),goals(clamp((neutral and 1.295 or 1.17)+(b-a)*.043,.2,4.8)*scale)
end
function W.simulateLeague(world,country,division)
 local clubs=W.league(world,country,division); local rows,byId={},{}
 for _,club in ipairs(clubs) do local r=row(club); rows[#rows+1]=r; byId[club.id]=r end
 local rng=W.rng(world.seed+world.season*7919+W.hash(country)*7+division*101)
 for _,games in ipairs(W.schedule(clubs)) do for _,game in ipairs(games) do
  local a,b=world.clubs[game[1]],world.clubs[game[2]]; local x,y=W.simScore(rng,a.rating,b.rating); W.record(byId[a.id],byId[b.id],x,y)
 end end
 return W.sorted(rows)
end
local function uniqueAdd(out,seen,id) if id and not seen[id] then out[#out+1]=id; seen[id]=true; return true end return false end
function W.qualify(standings,cupWinners)
 local qualifications={champions={},challenge={}}; local supers={}; local seen={}
 for _,country in ipairs(Config.COUNTRIES) do
  local tableRows=assert(standings[country.id] and standings[country.id][1],'Top division standings required')
  for i=1,2 do uniqueAdd(qualifications.champions,seen,tableRows[i].id) end
 end
 for _,country in ipairs(Config.COUNTRIES) do
  local rows=standings[country.id][1]
  uniqueAdd(qualifications.challenge,seen,rows[3].id)
  local cup=cupWinners and cupWinners[country.id]
  if not uniqueAdd(qualifications.challenge,seen,cup) then for i=4,#rows do if uniqueAdd(qualifications.challenge,seen,rows[i].id) then break end end end
  local runner=rows[2].id
  supers[country.id]={rows[1].id,cup and cup~=rows[1].id and cup or runner}
 end
 return qualifications,supers
end
local function validOverride(rows,ids)
 if type(rows)~='table' or #rows~=16 then return false end
 local seen={}; for _,id in ipairs(ids) do seen[id]=true end
 for _,r in ipairs(rows) do if not seen[r.id] or r.played~=30 then return false end seen[r.id]=nil end
 return next(seen)==nil
end
function W.advanceSeason(world,userResults,userClubId)
 local all={}; local userCountry,userDivision,override
 if userResults then userCountry=userResults.country; userDivision=userResults.division; override=userResults.table or userResults.standings end
 local season=world.season
 for _,country in ipairs(Config.COUNTRIES) do
  all[country.id]={}
  for division=1,country.divisions do
   local results
   if country.id==userCountry and division==userDivision then
    assert(validOverride(override,world.leagues[country.id][division]),'Incomplete or invalid user league table')
    results=W.sorted(override)
   else results=W.simulateLeague(world,country.id,division) end
   all[country.id][division]=results
   for _,r in ipairs(results) do local club=world.clubs[r.id]; club.records.played=club.records.played+r.played; club.records.wins=club.records.wins+r.w end
   local champion=world.clubs[results[1].id]; champion.records.leagueTitles=champion.records.leagueTitles+1
  end
 end
 local qualifications,supers=W.qualify(all,world.cupWinners)
 world.qualifications=qualifications; world.supercups=supers
 local history={season=season,champions={},cupWinners=copy(world.cupWinners),internationalWinners=copy(world.internationalWinners or {})}
 for _,country in ipairs(Config.COUNTRIES) do
  history.champions[country.id]=all[country.id][1][1].id
  local nextDivisions={}
  for division=1,country.divisions do
   local kept={}; local rows=all[country.id][division]
   for rank,r in ipairs(rows) do
    local destination=division
    if division>1 and rank<=Config.DIRECT_PROMOTION then destination=division-1 elseif division<country.divisions and rank>16-Config.RELEGATION then destination=division+1 end
    nextDivisions[destination]=nextDivisions[destination] or {}; table.insert(nextDivisions[destination],r.id)
   end
  end
  for division=1,country.divisions do
   local ids=nextDivisions[division]; assert(#ids==16,'Promotion broke league size'); table.sort(ids)
   world.leagues[country.id][division]=ids
   for _,id in ipairs(ids) do
    local club=world.clubs[id]; club.division=division
    local rng=W.rng(world.seed+season*919+W.hash(id)); local target=country.base-(division-1)*7
    -- Clubs retain their rating and history; annual growth, aging and turnover are bounded.
    local ageEffect=club.averageAge>=29 and -1 or club.averageAge<=24 and 1 or 0
    local change=rng(-2,2)+ageEffect+(club.rating<target-5 and 1 or club.rating>target+8 and -1 or 0)
    club.rating=clamp(club.rating+change,36,94); club.reputation=clamp(club.reputation+(change*.4),15,99)
    club.averageAge=club.averageAge+1
    if club.averageAge>=30 then club.averageAge=rng(24,27); club.generation=club.generation+1; club.squadSeed=(club.squadSeed+season*7919)%2147483647 end
    club.records.bestRating=math.max(club.records.bestRating,club.rating)
    local debtPayment=math.min(club.debt or 0,math.floor(target*5000*.25));club.debt=math.max(0,(club.debt or 0)-debtPayment)
    club.cash=clamp(math.floor(club.cash*.95+target*5000-debtPayment),0,100000000)
    for index,q in ipairs(club.retainedSquad or {})do
     local retired=P.endSeason(q,season,rng);if q.loanOut and q.loanOut.ends<=season then q.loanOut=nil end
     if retired or(q.loan and(q.loan.ends or 0)<=season)then local fresh=P.new(rng,club.id..':npc:'..(season+1)..':'..index,club.rating,q.pos,club.country,season+1);club.retainedSquad[index]=fresh
     else q.currentSeason=season+1;q.contractEnd=math.max(q.contractEnd,season+3)end
    end
   end
  end
 end
 world.history[#world.history+1]=history; if #world.history>Config.HISTORY_LIMIT then table.remove(world.history,1) end
 world.records.seasons=world.records.seasons+1; world.season=season+1; world.cupWinners={}; world.internationalWinners={}
 return all, userClubId and world.clubs[userClubId].division or nil
end
function W.transferOpen(date)
 for _,window in ipairs(Config.WINDOWS) do if date>=window.first and date<=window.last then return true end end return false
end
function W.validate(world)
 local seen,count={},0
 for _,country in ipairs(Config.COUNTRIES) do
  for division=1,country.divisions do
   local ids=world.leagues[country.id] and world.leagues[country.id][division]
   if type(ids)~='table' or #ids~=16 then return false,'WORLD_LEAGUE_SIZE' end
   for _,id in ipairs(ids) do local c=world.clubs[id]; if seen[id] or not c or c.country~=country.id or c.division~=division then return false,'WORLD_IDENTITY' end seen[id]=true; count=count+1 end
  end
 end
 if count~=320 then return false,'WORLD_CLUB_COUNT' end return true
end
return W
]========],server)
put('ModuleScript','WorldConfig',[========[-- Fictional original world. IDs and names do not depend on menus, RNG calls or seasons.
local Config={
 START_COUNTRY='asteria', START_CLUB='asteria_081', CLUBS_PER_DIVISION=16,
 DIRECT_PROMOTION=2, RELEGATION=2, HISTORY_LIMIT=40,
 -- Two direct places in each direction, mirrored at each internal boundary.
 QUALIFICATION={championsLeaguePlaces=2,challengeLeaguePlaces=1,challengeCupPlaces=1},
 COUNTRIES={
  {id='asteria',name='Asteria',divisions=6,culture='development',base=84,color={87,157,219},cities={'Larkhaven','Brindle','Eastmere','Ashbrook','Stoneford','Willowbay','Dunvale','Rookhill','Northgate','Cedarwick','Fairwater','Westhaven','Brookstead','Ironmere','Oakridge','Highfield'}},
  {id='brumora',name='Brumora',divisions=2,culture='pressing',base=81,color={164,93,183},cities={'Frostholm','Hearthwick','Grayhaven','Mossford','Alderfell','Cloudmere','Redwick','Winterbay','Longvale','Blackthorn','Duskfield','Hollowford','Rivermoor','Sablehill','Flintgate','Ravenbrook'}},
  {id='solara',name='Solara',divisions=2,culture='possession',base=83,color={240,176,65},cities={'Aurivale','Luminara','Coraluz','Sereno','Bellora','Riodoro','Solviento','Terramar','Arcoluz','Monteluna','Valdela','Clarossa','Olivara','Lucevia','Fiorenza','Estrella'}},
  {id='valdora',name='Valdora',divisions=2,culture='compact',base=80,color={198,82,85},cities={'Valtora','Pietrano','Castelle','Fontara','Verdano','Cortella','Ravello','Ponterra','Ardenza','Lavenza','Portello','Neravalle','Caldero','Miravento','Stradella','Vincera'}},
  {id='maravia',name='Maravia',divisions=2,culture='wings',base=79,color={47,177,165},cities={'Portavela','Marisol','Oceara','Velamar','Caisara','Brisola','Naveira','Rochamar','Santela','Miragua','Salvera','Costela','Varimar','Lumamar','Coraleira','Praiora'}},
  {id='nordvik',name='Nordvik',divisions=2,culture='physical',base=78,color={93,169,205},cities={'Skeldal','Vinterby','Havnesund','Nordfell','Eikholm','Bergstrand','Lindvik','Torsdal','Falksund','Skarheim','Solberg','Isenfjord','Ostervik','Brannby','Hjellstad','Varglund'}},
  {id='karuna',name='Karuna',divisions=2,culture='counter',base=80,color={222,119,69},cities={'Kairava','Suryan','Velapur','Namaru','Talima','Aranya','Devora','Mahana','Nivara','Samira','Paruna','Indara','Rohava','Akasha','Tavira','Lakana'}},
  {id='vestria',name='Vestria',divisions=2,culture='technical',base=82,color={94,179,119},cities={'Vesgrad','Zelenko','Novara','Dravice','Lunovec','Borava','Kralova','Vetrina','Mostara','Ruzdov','Danova','Ostara','Slavena','Belvica','Morava','Dubrina'}},
 },
 -- Sporting dates, not elapsed real-world days. All competition slots are disjoint.
 DATES={friendly=1,supercup=2,national96={10,26,42,58,74,90,110},national32={42,58,74,90,110},international={18,46,78,114}},
 WINDOWS={{first=0,last=36},{first=70,last=92}},
}
return Config
]========],server)
shared.Parent=rs;server.Parent=ss;print('Touchline installed; live checks pending')