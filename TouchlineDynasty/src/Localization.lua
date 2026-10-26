-- Key-based localization. Domain code needs only Locales; Roblox adapter is optional.
-- Names are passed as parameters and never sent through automatic translation.
local dictionaries=require(script.Parent.Locales)
local L={dictionaries=dictionaries,defaultLocale='en'}
local InstanceLocale={}; InstanceLocale.__index=InstanceLocale
local cloud={es=true,['pt-br']=true,pl=true,de=true,fr=true,tr=true,ja=true,ko=true}
local function finite(v) return type(v)=='number' and v==v and v~=math.huge and v~=-math.huge end
local function length(s)
 if utf8 and utf8.len then local ok,n=pcall(utf8.len,s); if ok and n then return n end end
 return #s
end
local function normalized(value)
 if type(value)~='string' then return 'en' end
 value=value:lower():gsub('_','-')
 if value=='qps-ploc' then return value end
 local base=value:match('^([a-z]+)')
 if base=='ua' then return 'uk' end
 if base=='pt' then return 'pt-br' end
 if dictionaries[base] or cloud[base] then return base end
 return 'en'
end
function L.resolve(setting,robloxLocale)
 if setting==nil or setting=='auto' then return normalized(robloxLocale) end
 return normalized(setting)
end
function L.pseudo(text)
 -- Pad by 50% of codepoints, preserving placeholders and readable English text.
 local n=length(text); local pad=math.max(0,math.floor(n*.5+.5)-2)
 return '['..text..string.rep('~',pad)..']'
end
function L.plural(locale,n)
 n=math.floor(math.abs(tonumber(n) or 0))
 if locale=='ja' or locale=='ko' or locale=='tr' then return 'other' end
 if locale=='pl' then
  if n==1 then return 'one' end
  if n%10>=2 and n%10<=4 and (n%100<12 or n%100>14) then return 'few' end
  return 'many'
 end
 if locale=='fr' or locale=='pt-br' then return n<=1 and 'one' or 'other' end
 if locale=='ru' or locale=='uk' then
  if n%10==1 and n%100~=11 then return 'one' end
  if n%10>=2 and n%10<=4 and (n%100<12 or n%100>14) then return 'few' end
  return 'many'
 end
 return n==1 and 'one' or 'other'
end
function L.number(value,locale,decimals)
 if not finite(value) then return '—' end
 decimals=math.max(0,math.min(2,math.floor(tonumber(decimals) or 0)))
 local negative=value<0; value=math.abs(value)
 local raw=string.format('%.'..decimals..'f',value)
 local integer,fraction=raw:match('^(%d+)%.?(%d*)$')
 local sep=(locale=='ru' or locale=='uk' or locale=='fr' or locale=='pl') and '\194\160' or ','
 local groups={}
 repeat table.insert(groups,1,integer:sub(-3)); integer=integer:sub(1,-4) until #integer==0
 local decimal=(locale=='ru' or locale=='uk' or locale=='fr' or locale=='pl' or locale=='de' or locale=='es' or locale=='pt-br' or locale=='tr') and ',' or '.'
 if locale=='de' or locale=='es' or locale=='pt-br' or locale=='tr' then sep='.' end
 return (negative and '−' or '')..table.concat(groups,sep)..(decimals>0 and decimal..fraction or '')
end
local function parameters(text,params,locale)
 return (text:gsub('{([%w_]+)}',function(name)
  local value=params and params[name]
  if value==nil then return '—' end
  if finite(value) then return L.number(value,locale) end
  if type(value)=='string' or type(value)=='boolean' then return tostring(value) end
  return '—'
 end))
end
function L.t(key,params,locale)
 locale=L.resolve(locale or 'en','en')
 if type(key)~='string' then return '' end
 local dictionary=dictionaries[locale] or dictionaries.en
 local selected=key
 if type(params)=='table' and params.count~=nil then
  local pluralKey=key..'.'..L.plural(locale,params.count)
  if dictionary[pluralKey] or dictionaries.en[pluralKey] then selected=pluralKey end
 end
 local text=dictionary[selected] or dictionaries.en[selected]
 if not text then return '['..key..']' end
 if locale=='qps-ploc' then text=L.pseudo(text) end
 return parameters(text,params,locale)
end
function L.new(options)
 options=options or {}
 local obj=setmetatable({setting=options.locale or 'auto',robloxLocale=options.robloxLocale or 'en-us',missing={},generation=0},InstanceLocale)
 obj.locale=L.resolve(obj.setting,obj.robloxLocale)
 return obj
end
function InstanceLocale:t(key,params)
 if type(key)~='string' then return '' end
 local selected=key
 if type(params)=='table' and params.count~=nil then
  local suffix=L.plural(self.locale,params.count)
  if dictionaries.en[key..'.'..suffix] or (dictionaries[self.locale] and dictionaries[self.locale][key..'.'..suffix]) then selected=key..'.'..suffix end
 end
 if not dictionaries.en[selected] then self.missing[selected]=true end
 if self.translator and cloud[self.locale] then
  local ok,text=pcall(function() return self.translator:FormatByKey(selected,params or {}) end)
  if ok and type(text)=='string' and text~='' and text~=selected then return text end
 end
 return L.t(selected,params,self.locale)
end
function InstanceLocale:event(value)
 if type(value)=='string' then
  -- Recognised event codes localize; pre-v2 literal history remains untouched.
  if dictionaries.en[value] then return self:t(value) end
  return value
 end
 if type(value)~='table' then return '' end
 if type(value.key)=='string' then
  if value.key=='event.achievement' and type(value.params)=='table'then local params={};for k,v in pairs(value.params)do params[k]=v end;params.name=self:t('achievement.'..tostring(params.name));return self:t(value.key,params)end
  return self:t(value.key,value.params or {})end
 if type(value.code)=='string' then return self:t(value.code,value.params or {}) end
 return type(value.legacy)=='string' and value.legacy or type(value.text)=='string' and value.text or ''
end
function InstanceLocale:number(n,decimals) return L.number(n,self.locale,decimals) end
function InstanceLocale:money(n) return self:t('format.money',{amount=self:number(n)}) end
function InstanceLocale:date(season,day) return self:t('format.date',{season=season,day=day}) end
function InstanceLocale:setLocale(setting,robloxLocale)
 setting=setting or 'auto'
 if self.setting==setting and (not robloxLocale or self.robloxLocale==robloxLocale) then return self.locale end
 self.setting=setting; if robloxLocale then self.robloxLocale=robloxLocale end
 self.locale=L.resolve(self.setting,self.robloxLocale); self.translator=nil
 if self.service then self:attachRoblox(self.player,self.localTable,self.onReady,self.service) end
 return self.locale
end
function InstanceLocale:attachRoblox(player,localTable,onReady,service)
 -- Starts an asynchronous request; the UI never waits for cloud translations.
 -- A late result from a timed-out request or previous locale is ignored.
 if not task or not task.spawn or not task.delay then return false end
 if not service then
  if not game then return false end
  local ok,result=pcall(function() return game:GetService('LocalizationService') end)
  if not ok then return false end
  service=result
 end
 self.service=service; self.player=player; self.localTable=localTable; self.onReady=onReady
 self.generation=self.generation+1; local generation=self.generation
 local deadline=false; local targetLocale=self.locale
 task.delay(4,function() deadline=true end)
 task.spawn(function()
  local ok,translator
  if cloud[targetLocale] then
   ok,translator=pcall(function()
    if self.setting=='auto' and player then return service:GetTranslatorForPlayerAsync(player) end
    return service:GetTranslatorForLocaleAsync(targetLocale)
   end)
  elseif localTable and targetLocale~='qps-ploc' then
   ok,translator=pcall(function() return localTable:GetTranslator(targetLocale=='en' and 'en-us' or targetLocale) end)
  end
  if ok and translator and not deadline and self.generation==generation then
   self.translator=translator
   if onReady then onReady() end
  end
 end)
 return true
end
function InstanceLocale:destroy()
 self.generation=self.generation+1; self.translator=nil; self.service=nil; self.player=nil; self.localTable=nil; self.onReady=nil
end
function L.entries()
 local keys={}; for key in pairs(dictionaries.en) do keys[#keys+1]=key end; table.sort(keys)
 local rows={}
 for _,key in ipairs(keys) do
  rows[#rows+1]={Key=key,Source=dictionaries.en[key],Context=key,Values={['en-us']=dictionaries.en[key],ru=dictionaries.ru[key],uk=dictionaries.uk[key]}}
 end
 return rows
end
function L.installTable(parent)
 local tableObject=Instance.new('LocalizationTable'); tableObject.Name='TouchlineLocalization'; tableObject.SourceLocaleId='en-us'; tableObject:SetEntries(L.entries()); tableObject.Parent=parent
 return tableObject
end
return L
