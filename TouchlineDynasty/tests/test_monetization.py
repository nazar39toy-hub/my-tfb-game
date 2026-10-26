"""Receipt and entitlement adapter tests. Roblox payment service is mocked."""
from test_storage import ROOT, runtime, load_storage


def main():
 lua=runtime(); load_storage(lua)
 lua.execute(r'''
 function signal()
  local s={listeners={}}
  function s:Connect(fn) self.listeners[#self.listeners+1]=fn; return {Disconnect=function() end} end
  function s:Fire(...) for _,fn in ipairs(self.listeners) do fn(...) end end
  return s
 end
 player={UserId=101}; local active=player
 players={PlayerRemoving=signal(),GetPlayerByUserId=function(_,id) if active and id==active.UserId then return active end end}
 function presence(value) active=value and player or nil end
 purchases=0; ownedPass=false; passError=false
 marketplace={PromptGamePassPurchaseFinished=signal(),
  UserOwnsGamePassAsync=function() if passError then error('service outage') end; return ownedPass end,
  PromptGamePassPurchase=function(_,p,id) purchases=purchases+1; lastPurchase=id end,
  PromptProductPurchase=function(_,p,id) purchases=purchases+1; lastPurchase=id end}
 addService('Players',players); addService('MarketplaceService',marketplace)
 p=S.load(player,function() return {version=2,cash=123,cosmetics={tokens=100}} end)
 profiles={[player]=p}; changes=0
 ''')
 lua.globals().Config=lua.execute((ROOT/'src/MonetizationConfig.lua').read_text())
 lua.execute('script={Parent={MonetizationConfig="config"}}; require=function(target) assert(target=="config"); return Config end')
 lua.globals().N=lua.execute((ROOT/'src/Monetization.lua').read_text())
 lua.execute(r'''
 N.bind({profiles=profiles,storage=S,copy=copy,onChanged=function() changes=changes+1 end})
 assert(marketplace.ProcessReceipt==N.processReceipt)
 -- Catalog is honest while owner IDs are missing.
 local shop=N.public(player,p)
 for _,entry in ipairs(shop.catalog) do
  if entry.kind~='item' then assert(not entry.enabled and entry.robloxId==0 and entry.robuxPrice==nil) end
 end
 assert(not N.action(player,p,'purchase',{id='tokens_s'})); assert(purchases==0)
 -- Currency has no relation to club budget.
 local cash=p.cash
 assert(N.action(player,p,'cosmeticBuy',{id='lime'}))
 assert(p.cosmetics.tokens==70 and p.cash==cash and p.cosmetics.owned.lime)
 assert(not N.action(player,p,'cosmeticBuy',{id='lime'}))
 assert(N.action(player,p,'cosmeticEquip',{id='lime'}))
 assert(p.cosmetics.equipped.kit=='lime')
 assert(not N.action(player,p,'cosmeticBuy',{id='night'}))
 assert(not N.action(player,p,'cosmeticEquip',{id='hoops'}))
 assert(p.cosmetics.tokens==70 and p.cash==cash)
 -- IDs configured only in this private test runtime, never in build config.
 Config.products[1].robloxId=201; Config.products[4].robloxId=204; Config.passes[1].robloxId=301
 assert(N.action(player,p,'purchase',{id='tokens_s'}))
 assert(purchases==1 and lastPurchase==201 and p.cosmetics.tokens==70)
 -- Prompt cancellation / completion is not a grant.
 assert(N.processReceipt({PlayerId=101,ProductId=999,PurchaseId='unknown'})=='RETRY')
 assert(N.processReceipt({PlayerId=101,ProductId=201,PurchaseId=''})=='RETRY')
 presence(false)
 assert(N.processReceipt({PlayerId=101,ProductId=201,PurchaseId='absent'})=='RETRY')
 presence(true)
 local receipt={PlayerId=101,ProductId=201,PurchaseId='purchase-A'}
 assert(N.processReceipt(receipt)=='GRANTED')
 assert(p.cosmetics.tokens==170 and records.u101.profile.cosmetics.tokens==170)
 assert(p.cosmetics.receipts['purchase-A'].productId==201 and p.cash==cash)
 assert(N.processReceipt(receipt)=='GRANTED' and p.cosmetics.tokens==170)
 -- A successful commit with lost response remains one grant.
 responseLoss=1
 assert(N.processReceipt({PlayerId=101,ProductId=201,PurchaseId='purchase-B'})=='GRANTED')
 assert(p.cosmetics.tokens==270)
 -- Failed writes don't change either currency or ledger.
 fail=true
 local outageReceipt={PlayerId=101,ProductId=201,PurchaseId='purchase-C'}
 assert(N.processReceipt(outageReceipt)=='RETRY')
 assert(p.cosmetics.tokens==270 and p.cosmetics.receipts['purchase-C']==nil)
 fail=false
 assert(N.processReceipt(outageReceipt)=='GRANTED' and p.cosmetics.tokens==370)
 -- A later save never restores a wallet from an older autosave.
 assert(S.save(player,p,copy,false))
 assert(records.u101.profile.cosmetics.tokens==370)
 assert(N.processReceipt({PlayerId=101,ProductId=204,PurchaseId='donation-A'})=='GRANTED')
 assert(p.cosmetics.support==1 and p.cosmetics.tokens==370 and p.cash==cash)
 -- Only verified server ownership produces pass entitlements.
 marketplace.PromptGamePassPurchaseFinished:Fire(player,301,false)
 assert(not p.cosmetics.passes.identity)
 ownedPass=true
 marketplace.PromptGamePassPurchaseFinished:Fire(player,301,true)
 assert(p.cosmetics.passes.identity and p.cosmetics.owned.hoops)
 assert(N.action(player,p,'cosmeticEquip',{id='hoops'}))
 passError=true
 assert(not N.refreshPasses(player,p,true)); assert(p.cosmetics.passes.identity)
 passError=false; ownedPass=false
 assert(N.refreshPasses(player,p,true))
 assert(not p.cosmetics.passes.identity and not p.cosmetics.owned.hoops and p.cosmetics.equipped.kit~='hoops')
 -- Profile lock loss prevents false acknowledgement.
 records.u101.lock='another-server'
 assert(N.processReceipt({PlayerId=101,ProductId=201,PurchaseId='lost-lock'})=='RETRY')
 assert(p.cosmetics.tokens==370)
 ''')
 print('PASS monetization: disabled IDs, cosmetic purchase/equip, exact-once receipts, outages, response loss, donations, pass ownership/revocation')
 print('PASS monetization: mocked adapter only; real Roblox purchases/receipts NOT RUN')

if __name__=='__main__': main()
