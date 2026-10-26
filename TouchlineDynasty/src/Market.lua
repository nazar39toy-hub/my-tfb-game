-- NPC transfers inside a single career. Opening a menu never consumes random numbers.
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
