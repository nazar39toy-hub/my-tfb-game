-- Page models. All economic operations remain server intentions.
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
