local K=require(script.Parent.EconomyConfig)
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
