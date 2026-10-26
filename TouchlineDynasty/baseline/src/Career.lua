-- Pure Lua domain model. No client-provided money, scores or ratings are accepted.
local C = {}
C.VERSION = 1
C.formations = {'4-3-3','4-4-2','3-5-2'}
C.names = {'Тернополь Атлетик','Днепровские Волки','Полесье Юнайтед','Карпатские Соколы','Одесский Маяк','Киев Аврора','Подолье Сити','Сумские Лисы','Львов Роверс','Днепр Искра','Буковина Стар','Черкассы ФК','Волынь Юнайтед','Ужгород Виста','Ровно Вектор','Хмельницкий Альянс','Лондон Норт','Мадрид Сол','Милан Стелла','Париж Люмьер','Берлин Юнион','Лиссабон Мар','Амстердам Оранж','Прага Корона'}
local first = {'Макс','Артём','Данило','Алекс','Лука','Нико','Марк','Илья','Том','Лев','Эрик','Оскар','Роман','Тео','Матео','Ян'}
local last = {'Коваленко','Мороз','Шевчук','Силва','Мартин','Новак','Коста','Бондарь','Рейес','Мюллер','Бруно','Кларк','Соколов','Росс','Вега','Волков'}
function C.copy(x)
 if type(x) ~= 'table' then return x end
 local y = {}; for k,v in pairs(x) do y[k] = C.copy(v) end; return y
end
function C.rng(seed)
 local state = math.max(1, math.floor(seed or 1) % 2147483647)
 return function(a,b)
  state = (state * 48271) % 2147483647
  local n = state / 2147483647
  if a then return math.floor(a+n*(b-a+1)) end
  return n
 end
end
function C.value(p) return math.floor((p.rating-25)^2 * 110 * (p.age < 23 and 1.4 or (p.age > 30 and .65 or 1))) end
function C.player(rng, id, rating, pos)
 local p = {id=id,name=first[rng(1,#first)]..' '..last[rng(1,#last)],age=rng(17,31),rating=rating,pos=pos,fitness=100,xp=0,goals=0,assists=0}
 p.potential=math.min(94, rating+rng(3,18)); return p
end
function C.roles(formation)
 local roles={'GK'}; local counts=formation=='4-4-2' and {4,4,2} or formation=='3-5-2' and {3,5,2} or {4,3,3}
 for g,n in ipairs(counts) do for _=1,n do roles[#roles+1]=({'DEF','MID','FWD'})[g] end end
 return roles
end
function C.schedule()
 local ring={1,2,3,4,5,6,7,8}; local rounds={}
 for r=1,7 do
  local games={}; for i=1,4 do
   local a,b=ring[i],ring[9-i]; if r%2==0 then a,b=b,a end
   games[#games+1]={a,b}
  end
  rounds[r]=games; table.insert(ring,2,table.remove(ring))
 end
 for r=1,7 do rounds[r+7]={}; for _,g in ipairs(rounds[r]) do table.insert(rounds[r+7],{g[2],g[1]}) end end
 return rounds
end
function C.buildLeague(p)
 p.league={}; local base=43+(4-p.division)*10
 for i=1,8 do
  local name=C.names[(3-p.division)*8+i]
  if i==1 then name=p.club elseif name==p.club then name='Восток Атлетик' end
  p.league[i]={name=name,rating=base+((i*7+p.season*3)%13),pts=0,gf=0,ga=0,w=0,d=0,l=0,played=0}
 end
 p.round=1; p.cupStage=1; p.cupAlive=true; p.cupDone=false; p.schedule=C.schedule()
end
function C.market(p)
 local rng=C.rng(p.seed+p.season*7919+p.round*113+p.marketVersion*13)
 p.market={}; local base=48+(3-p.division)*10
 for i=1,18 do
  local pos=({'GK','DEF','MID','FWD'})[(i-1)%4+1]
  local q=C.player(rng,'m'..p.season..'_'..p.round..'_'..p.marketVersion..'_'..i,rng(base-6,base+17),pos)
  q.price=C.value(q); q.free=(i==18); if q.free then q.price=math.floor(q.price*.18) end
  table.insert(p.market,q)
 end
end
function C.new(seed)
 local p={version=C.VERSION,seed=seed,club='Тернополь Атлетик',season=1,division=3,cash=650000,reputation=0,formation='4-3-3',mentality='balanced',roster={},lineup={},upgrades={training=1,academy=1,stadium=1},history={},trophies=0,wins=0,marketVersion=1,lastResult='',tutorial=true,academyYear=0}
 local rng=C.rng(seed); local roles=C.roles(p.formation)
 for i=1,18 do
  local q=C.player(rng,'p'..i,rng(48,62),roles[i] or ({'GK','DEF','MID','FWD'})[(i-12)%4+1])
  table.insert(p.roster,q); if i<=11 then p.lineup[i]=q.id end
 end
 C.buildLeague(p); C.market(p); return p
end
function C.find(p,id) for i,q in ipairs(p.roster) do if q.id==id then return q,i end end end
function C.strength(p)
 local sum=0; local roles=C.roles(p.formation)
 for i,id in ipairs(p.lineup) do
  local q=C.find(p,id)
  if q then sum=sum+q.rating*(.7+.3*q.fitness/100)*(q.pos==roles[i] and 1 or .84) end
 end
 return sum/11
end
function C.sorted(p)
 local t=C.copy(p.league)
 table.sort(t,function(a,b) if a.pts~=b.pts then return a.pts>b.pts elseif a.gf-a.ga~=b.gf-b.ga then return a.gf-a.ga>b.gf-b.ga elseif a.gf~=b.gf then return a.gf>b.gf else return a.name<b.name end end)
 return t
end
function C.next(p,kind)
 if kind=='cup' then
  if not p.cupAlive or p.cupDone then return nil,'Кубок уже завершён' end
  return {name=({'Львов Роверс','Киев Аврора','Мадрид Сол'})[p.cupStage],rating=49+(3-p.division)*8+p.cupStage*5,home=true,kind='cup'}
 end
 if p.round>14 then return nil,'Сезон завершён — начни следующий' end
 for _,g in ipairs(p.schedule[p.round]) do
  if g[1]==1 or g[2]==1 then local i=g[1]==1 and g[2] or g[1]; return {name=p.league[i].name,rating=p.league[i].rating,index=i,home=g[1]==1,kind='league'} end
 end
end
function C.poisson(rng,lambda)
 local k,p=0,1; local lim=math.exp(-lambda)
 repeat k=k+1; p=p*rng() until p<=lim or k>10
 return k-1
end
function C.sim(rng,a,b)
 return C.poisson(rng,math.max(.2,1.35+(a-b)*.045)),C.poisson(rng,math.max(.2,1.15+(b-a)*.045))
end
local function record(a,b,x,y)
 a.played=a.played+1; b.played=b.played+1; a.gf=a.gf+x; a.ga=a.ga+y; b.gf=b.gf+y; b.ga=b.ga+x
 if x>y then a.pts=a.pts+3; a.w=a.w+1; b.l=b.l+1 elseif x<y then b.pts=b.pts+3; b.w=b.w+1; a.l=a.l+1 else a.pts=a.pts+1; b.pts=b.pts+1; a.d=a.d+1; b.d=b.d+1 end
end
function C.finish(p,op,x,y,scorers,assists,penWin)
 local rng=C.rng(p.seed+p.season*10000+p.round*37+p.cupStage*41)
 local won=x>y or (x==y and penWin==true)
 local income=25000+p.upgrades.stadium*8000+(won and 20000 or x==y and 8000 or 0)
 p.cash=p.cash+income; if won then p.wins=p.wins+1; p.reputation=p.reputation+2 end
 p.lastResult=p.club..' '..x..' : '..y..' '..op.name..(x==y and op.kind=='cup' and (won and ' • победа по пенальти' or ' • поражение по пенальти') or '')
 for _,q in ipairs(p.roster) do
  local active=false; for _,id in ipairs(p.lineup) do if id==q.id then active=true end end
  q.fitness=math.max(0,math.min(100,q.fitness+(active and -rng(3,8) or 14)))
  if active then
   q.xp=q.xp+12+p.upgrades.training*4
   if q.xp>=100 and q.rating<q.potential then q.rating=q.rating+1; q.xp=q.xp-100 end
  end
  q.goals=q.goals+((scorers or {})[q.id] or 0); q.assists=q.assists+((assists or {})[q.id] or 0)
 end
 if op.kind=='cup' then
  if won and p.cupStage==3 then p.trophies=p.trophies+1; p.cash=p.cash+250000; p.cupDone=true; p.reputation=p.reputation+15
  elseif won then p.cupStage=p.cupStage+1 else p.cupAlive=false end
 else
  for _,g in ipairs(p.schedule[p.round]) do
   local a,b=g[1],g[2]; local gx,gy
   if a==1 then gx,gy=x,y elseif b==1 then gx,gy=y,x else gx,gy=C.sim(rng,p.league[a].rating,p.league[b].rating) end
   record(p.league[a],p.league[b],gx,gy)
  end
  p.round=p.round+1; C.market(p)
 end
 p.history[#p.history+1]=p.lastResult; if #p.history>40 then table.remove(p.history,1) end
 return income
end
function C.action(p,action,arg)
 arg=arg or {}; local id=arg.id
 if action=='buy' then
  if #p.roster>=25 then return false,'В составе максимум 25 игроков' end
  for i,q in ipairs(p.market) do if q.id==id then
   if p.cash<q.price then return false,'Не хватает бюджета' end
   p.cash=p.cash-q.price; local bought=C.copy(q); bought.price=nil; bought.free=nil; table.insert(p.roster,bought); table.remove(p.market,i); return true,'Игрок подписан'
  end end
  return false,'Игрок уже недоступен'
 elseif action=='sell' then
  local q,i=C.find(p,id); if not q then return false,'Игрок не найден' end
  for _,v in ipairs(p.lineup) do if v==id then return false,'Сначала переведи игрока в запас' end end
  if #p.roster<=11 then return false,'Нужны минимум 11 игроков' end
  p.cash=p.cash+math.floor(C.value(q)*.75); table.remove(p.roster,i); return true,'Игрок продан'
 elseif action=='swap' then
  local q=C.find(p,id); local slot=tonumber(arg.slot)
  if not q or not slot or slot%1~=0 or slot<1 or slot>11 then return false,'Выбери позицию и футболиста' end
  local old=p.lineup[slot]; for i,v in ipairs(p.lineup) do if v==id then p.lineup[i]=old; break end end
  p.lineup[slot]=id; return true,'Состав обновлён'
 elseif action=='formation' then
  for _,f in ipairs(C.formations) do if f==arg.value then p.formation=f; return true,'Схема изменена' end end
 elseif action=='mentality' then
  if arg.value=='attack' or arg.value=='balanced' or arg.value=='defend' then p.mentality=arg.value; return true,'Тактика изменена' end
 elseif action=='upgrade' then
  local key=arg.key; local n=p.upgrades[key]
  if not n or n>=10 then return false,'Максимальный уровень' end
  local price=n*n*80000; if p.cash<price then return false,'Нужно '..price end
  p.cash=p.cash-price; p.upgrades[key]=n+1; return true,'Инфраструктура улучшена'
 elseif action=='rest' then
  if p.cash<30000 then return false,'Нужно 30 000' end
  p.cash=p.cash-30000; for _,q in ipairs(p.roster) do q.fitness=math.min(100,q.fitness+25) end; return true,'Команда восстановилась'
 elseif action=='academy' then
  if p.academyYear==p.season then return false,'Набор уже проведён в этом сезоне' end
  if #p.roster>=25 then return false,'Освободи место в составе' end
  if p.cash<40000 then return false,'Нужно 40 000' end
  p.cash=p.cash-40000; p.academyYear=p.season
  local rng=C.rng(p.seed+p.season*919); local q=C.player(rng,'y'..p.season,43+p.upgrades.academy*3+rng(0,7),({'GK','DEF','MID','FWD'})[rng(1,4)])
  q.age=16; q.potential=math.min(98,q.rating+rng(15,25)); table.insert(p.roster,q); return true,'Выпускник: '..q.name
 elseif action=='season' then
  if p.round<=14 then return false,'Сначала закончи 14 туров лиги' end
  if p.cupAlive and not p.cupDone then return false,'Сначала закончи кубок' end
  local place=8; for i,t in ipairs(C.sorted(p)) do if t.name==p.club then place=i end end
  local reward=(9-place)*45000; p.cash=p.cash+reward
  if place==1 then p.trophies=p.trophies+1; p.reputation=p.reputation+20 end
  if place<=2 then p.division=math.max(1,p.division-1) elseif place>=7 then p.division=math.min(3,p.division+1) end
  p.season=p.season+1
  local rng=C.rng(p.seed+p.season)
  for i,q in ipairs(p.roster) do
   q.age=q.age+1; q.fitness=100; q.goals=0; q.assists=0
   if q.age>31 then q.rating=math.max(35,q.rating-2) end
   if q.age>=36 then
    local fresh=C.player(rng,'r'..p.season..'_'..i,46+p.upgrades.academy*2,q.pos); fresh.age=17
    for j,v in ipairs(p.lineup) do if v==q.id then p.lineup[j]=fresh.id end end
    p.roster[i]=fresh
   end
  end
  C.buildLeague(p); C.market(p); return true,'Новый сезон! Призовые: '..reward
 elseif action=='job' then
  if p.round~=1 or p.season<2 then return false,'Смена клуба — в начале нового сезона' end
  if p.reputation<30 then return false,'Нужно 30 репутации' end
  local idx=tonumber(arg.index); if not idx or idx%1~=0 or idx<1 or idx>3 then return false,'Нет такого предложения' end
  p.club=({'Одесский Маяк','Киев Аврора','Львов Роверс'})[idx]; p.reputation=p.reputation-30
  -- A new club is a genuinely new squad/facilities, while manager honours survive.
  local fresh=C.new(p.seed+p.season*101+idx); p.roster=fresh.roster; p.lineup=fresh.lineup; p.cash=800000; p.upgrades=fresh.upgrades; p.formation=fresh.formation
  C.buildLeague(p); C.market(p); return true,'Ты возглавил '..p.club
 end
 return false,'Действие недоступно'
end
return C
