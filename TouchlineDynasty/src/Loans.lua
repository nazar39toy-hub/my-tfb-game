-- Outgoing NPC loans use game dates, never wall-clock waiting.
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
