local Config=require(script.Parent.WorldConfig)
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
