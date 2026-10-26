-- One receipt callback; grants and purchase IDs persist in the SAME profile write.
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
