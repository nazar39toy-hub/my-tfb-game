from pathlib import Path
import time
ROOT=Path(__file__).resolve().parents[1]
exec((ROOT/'tests/native_check.py').read_text().split('results=[]')[0])
started=time.perf_counter()
run(r'''
C=require('Career');local E=require('Economy');local T=require('Tournaments')
local names={'novice','frugal','trader','academy','facilities','simulation','forfeit'}
local rows={}
for seed=1,1000 do
 local strategy=names[(seed-1)%7+1];local p=C.new(seed+70000);local rng=C.rng(seed+4101);local firstTop=0;local insolvent=0;local wageRatio=0;local cashStart=p.cash;local ratioSum=0;local transferNet=0;local firstPromotion=0;local EConfig=require('EconomyConfig')
 for season=1,30 do
  if strategy=='academy' then C.action(p,'academy',{});local ids={};for _,q in ipairs(p.academy)do ids[#ids+1]=q.id end;for _,id in ipairs(ids)do C.action(p,'promote',{id=id})end end
  if strategy=='facilities' or strategy=='novice' and season%3==0 then for _,key in ipairs({'training','academy','stadium','medical'})do C.action(p,'upgrade',{key=key})end end
  if strategy~='forfeit' then
   for _,q in ipairs(p.roster)do if q.contractEnd<=p.season+1 then C.action(p,'renew',{id=q.id})end end
   if strategy~='frugal' then
    for signing=1,(strategy=='trader' and 2 or 1)do
    C.action(p,'autoLineup',{})
    local active={};for _,id in ipairs(p.lineup)do active[id]=true end
    local reserves={};for _,q in ipairs(p.roster)do if not active[q.id]then reserves[#reserves+1]=q end end;table.sort(reserves,function(a,b)return a.rating<b.rating end)
    if #p.roster>=22 then for _,q in ipairs(reserves)do if C.action(p,'sell',{id=q.id})then break end end end
    local offers={};for _,q in ipairs(p.market)do if C.transferImpact(p,q)>.05 then offers[#offers+1]=q end end;table.sort(offers,function(a,b)local x,y=C.transferImpact(p,a),C.transferImpact(p,b);if x==y then return a.id<b.id end;return x>y end)
    for _,q in ipairs(offers)do if q.totalCost and q.totalCost<p.cash*.6 then C.action(p,'buy',{id=q.id});C.repairLineup(p);break end end
    end
   end
  end
  if strategy~='forfeit' then assert(C.action(p,'autoLineup',{}))end
  local op=C.next(p)
  while op do
   if strategy=='trader' and p.marketOpen~=false then
    for _,q in ipairs(p.market)do if q.totalCost and q.totalCost<p.cash*.12 then C.action(p,'buy',{id=q.id});break end end
    if #p.roster>19 then C.action(p,'sell',{id=p.roster[#p.roster].id})end
   end
   local costs,reason=C.prepare(p,op);assert(costs~=nil,reason)
   if strategy~='forfeit' then assert(C.action(p,'autoLineup',{}))end
   local x,y=C.sim(rng,C.strength(p),op.rating,op.home,op.neutral);local pen
   if op.knockout and x==y then pen=T.penalties(rng,C.strength(p),op.rating)end
   local income,code=C.finish(p,op,x,y,{},{},pen,{forfeit=strategy=='forfeit',mode='aggregate'});assert(income~=nil,code)
   op=C.next(p)
  end
  local ledger=p.financeLedger;local tailWeeks=math.floor(p.season*EConfig.seasonDays/7)-math.floor(((p.season-1)*EConfig.seasonDays+p.date)/7)
  local annualWages=ledger.wages+tailWeeks*E.wages(p);local revenue=ledger.tickets+ledger.sponsors+(ledger.broadcast or 0)+ledger.transfersIn
  transferNet=transferNet+ledger.transfersIn-ledger.transfersOut
  local f=E.forecast(p);wageRatio=wageRatio+(f.wages or 0)
  if p.debt>p.cash then insolvent=insolvent+1 end
  local oldDivision=p.division;assert(C.action(p,'season',{}));assert(C.validate(p))
  revenue=revenue+p.seasonHistory[#p.seasonHistory].prize;ratioSum=ratioSum+annualWages/math.max(1,revenue)
  if p.division<oldDivision and firstPromotion==0 then firstPromotion=season end
  if p.division==1 and firstTop==0 then firstTop=season end
 end
 local sum,age=0,0;for _,q in ipairs(p.roster)do sum=sum+q.rating;age=age+q.age end
 rows[#rows+1]={seed,strategy,p.cash,p.debt,firstTop,insolvent,sum/#p.roster,wageRatio/30,ratioSum/30,transferNet,firstPromotion}
 if seed%100==0 then print('BALANCE careers completed',seed);io.flush()end
end
local f=assert(io.open('BALANCE_RAW.csv','w'));f:write('seed,strategy,cash,debt,first_top,insolvent_seasons,mean_rating,mean_weekly_wages,wage_income_ratio,net_transfer_cash,first_promotion\n')
for _,row in ipairs(rows)do local s={};for _,v in ipairs(row)do s[#s+1]=tostring(v)end;f:write(table.concat(s,',')..'\n')end;f:close()
''')
print('Elapsed seconds',round(time.perf_counter()-started,3))
