local Players=game:GetService('Players')
local RS=game:GetService('ReplicatedStorage')
local Run=game:GetService('RunService')
local shared=RS:WaitForChild('TouchlineShared')
local L=require(shared.Localization)
local UI=require(shared.UI)
local Screens=require(shared.CareerScreens)
local View=require(shared.MatchView)
local Input=require(shared.Input)
local Results=require(shared.Results)
local Audio=require(shared.Audio)
local player=Players.LocalPlayer
task.spawn(function()pcall(function()local module=player:WaitForChild('PlayerScripts'):WaitForChild('PlayerModule');require(module):GetControls():Disable()end)end)
local camera=workspace.CurrentCamera
if not camera then camera=Instance.new('Camera');camera.Parent=workspace;workspace.CurrentCamera=camera end
camera.CameraType=Enum.CameraType.Scriptable;camera.CFrame=CFrame.new(0,40,50)
local net=RS:WaitForChild('TouchlineNet')
local command=net:WaitForChild('Command')
local event=net:WaitForChild('Event')
local tr=L.new({robloxLocale=player.LocaleId})
local profile,revision=nil,0
local audio=Audio.new(game:GetService('SoundService'))
local pending,requestCounter=nil,0
local function send(action,arg)
 local interactive=action=='input' or action=='control' or action=='ready'
 if not interactive then if pending then return end;audio:play('ui');requestCounter=requestCounter+1;local id=requestCounter;pending=id;task.delay(8,function()if pending==id then pending=nil;command:FireServer('ready',{})end end)end
 command:FireServer(action,arg or {})
end
local screens=Screens.new(tr,send)
local ui=UI.new(player,tr,{items=function(...) return screens:items(...) end})
screens.ui=ui
local view=View.new(ui.gui,tr,send)
local input=Input.new(ui.gui,view,tr,send)
view.onForfeit=function()
 input:setBlocked(true)
 ui:modal(tr:t('ui.forfeit'),tr:t('ui.confirmForfeit'),{{label=tr:t('ui.confirm'),callback=function() send('forfeit');input:setBlocked(false) end},{label=tr:t('ui.cancel'),callback=function() input:setBlocked(false) end}})
end
local function choose(title,items,onChoose,index)
 index=index or 1;local actions={}
 for n=index,math.min(#items,index+1)do local item=items[n];actions[#actions+1]={label=item.name,callback=function()onChoose(item)end}end
 if index+2<=#items then actions[#actions+1]={label=tr:t('ui.continue'),callback=function()choose(title,items,onChoose,index+2)end}end
 actions[#actions+1]={label=tr:t('ui.cancel'),callback=function()input:setBlocked(false)end}
 ui:modal(title,'',actions)
end
view.onTactics=function()
 input:setBlocked(true);send('control',{action='teamTalk'})
 ui:modal(tr:t('ui.tactics'),tr:t('training.pause'),{
 {label=tr:t('ui.style'),callback=function()local items={};for _,id in ipairs({'possession','counter','press','lowblock','wings'})do items[#items+1]={name=tr:t('style.'..id),id=id}end;choose(tr:t('ui.style'),items,function(item)send('control',{action='style',value=item.id});send('control',{action='continue'});input:setBlocked(false)end)end},
 {label=tr:t('ui.substitute'),callback=function()
  local active,items={},{};for _,q in ipairs(view.latest and view.latest.players or {})do if q.team==1 then active[q.id]=true;if q.active then items[#items+1]={id=q.id,name=tostring(q.number)..' · '..q.id}end end end
  choose(tr:t('ui.substitute'),items,function(out)
   local eligible={};for _,entry in ipairs(view.latest.bench or {})do eligible[entry.id]=true end
   local bench={};for _,q in ipairs(profile.roster)do if eligible[q.id] then bench[#bench+1]={id=q.id,name=q.name..' · '..q.pos}end end
   choose(tr:t('ui.substitute'),bench,function(incoming)send('control',{action='substitute',out=out.id,inId=incoming.id});input:setBlocked(false)end)
  end)
 end},
 {label=tr:t('ui.continue'),callback=function()send('control',{action='continue'});input:setBlocked(false)end},
 {label=tr:t('ui.cancel'),callback=function()input:setBlocked(false)end}})
end
local function refresh()
 if not profile then return end
 tr:setLocale((profile.settings or {}).locale or 'auto',player.LocaleId)
 for _,item in ipairs((profile.shop or {}).catalog or {}) do
  if item.enabled and item.robloxId and item.robloxId>0 and not screens.prices[item.id] and not screens.priceBusy[item.id] then
   screens.priceBusy[item.id]=true
   task.spawn(function()
    local ok,info=pcall(function() return game:GetService('MarketplaceService'):GetProductInfoAsync(item.robloxId,Enum.InfoType[item.infoType]) end)
    if ok and info and info.IsForSale~=false then screens.prices[item.id]=info.PriceInRobux end
    screens.priceBusy[item.id]=nil;ui:refresh(false)
   end)
  end
 end
 audio:settingsChanged(profile.settings or {});input:setSettings(profile.settings or {}); screens.profile=profile; ui:update(profile)
end
screens.onRename=function()
 local box;ui:modal(tr:t('club.rename'),tr:t('club.renameHelp'),{{label=tr:t('ui.confirm'),callback=function()send('rename',{name=box.Text})end},{label=tr:t('ui.cancel'),callback=function()end}})
 box=UI.make('TextBox',{Text=profile.club,ClearTextOnFocus=false,TextSize=18,Font=Enum.Font.Gotham,TextColor3=UI.colors.text,BackgroundColor3=UI.colors.card,Position=UDim2.fromOffset(20,150),Size=UDim2.new(1,-40,0,48),ZIndex=54},ui.modalFrame:FindFirstChild('Panel'))
end
screens.onRemap=function(action)
 input:remap(function(key) local bindings={}; for k,v in pairs((profile.settings or {}).bindings or {}) do bindings[k]=v end; bindings[action]=key; send('settings',{key='bindings',value=bindings}) end)
end
screens.onTutorial=function() send('practice',{kind='tutorial'}) end
tr:attachRoblox(player,nil,function()if profile then ui:update(profile)end end)
event.OnClientEvent:Connect(function(kind,data)
 if kind~='snapshot' then pending=nil end
 if kind=='profile' then profile=data; revision=data.revision or 0; refresh()
 elseif kind=='patch' then
  if not profile or data.base~=revision then send('ready'); return end
  for k,v in pairs(data.fields) do profile[k]=v end
  for _,k in ipairs(data.removed or {}) do profile[k]=nil end
  revision=data.revision; profile.revision=revision; refresh()
 elseif kind=='records' then
  local lines={};for i,row in ipairs(data.rows)do lines[#lines+1]=i..'. '..row.userId..' · '..row.points end
  ui:modal(tr:t('records.title')..' · '..tr:t(data.mode=='simulate' and 'ui.modeSimulate' or data.mode=='highlights' and 'ui.modeHighlights' or 'ui.modeManual')..' / '..tr:t('difficulty.'..data.difficulty),#lines>0 and table.concat(lines,'\n')or tr:t('ui.empty'),{{label=tr:t('ui.continue'),callback=function()end}})
 elseif kind=='playerHistory' then
  local lines={};for _,row in ipairs(data.rows or {})do lines[#lines+1]=tr:t('player.historyRow',{season=row.season,age=row.age or "—",rating=row.rating or "—",goals=row.goals or 0,assists=row.assists or 0})end
  ui:modal(data.name,#lines>0 and table.concat(lines,'\n')or tr:t('ui.empty'),{{label=tr:t('ui.close'),callback=function()end}})
 elseif kind=='toast' then ui:message(tr:event(data))
 elseif kind=='matchStart' then ui.matchActive=true;ui:clearSelection();audio:match(true);audio:snapshot(data);view:show(profile,data); input:setActive(true)
 elseif kind=='snapshot' then audio:snapshot(data);view:push(data)
 elseif kind=='result' then
  ui.matchActive=false;audio:match(false);input:setActive(false); view:hide()
  Results.show(ui,tr,data,profile,function()ui:open('hub')end)
 end
end)
Run.RenderStepped:Connect(function() view:render(); input:step() end)
send('ready')
