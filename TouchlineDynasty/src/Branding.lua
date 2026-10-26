-- Filtering adapter is injected; profile transforms below never yield or call services.
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
