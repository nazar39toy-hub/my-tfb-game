local Players=game:GetService('Players')
local ReplicatedStorage=game:GetService('ReplicatedStorage')
local UIS=game:GetService('UserInputService')
local RunService=game:GetService('RunService')
local TweenService=game:GetService('TweenService')
local player=Players.LocalPlayer
local net=ReplicatedStorage:WaitForChild('TouchlineNet',45)
local gui=Instance.new('ScreenGui'); gui.Name='TouchlineDynasty'; gui.IgnoreGuiInset=true; gui.ResetOnSpawn=false; gui.ZIndexBehavior=Enum.ZIndexBehavior.Sibling; gui.Parent=player:WaitForChild('PlayerGui')
local color={bg=Color3.fromRGB(10,16,24),panel=Color3.fromRGB(19,28,40),card=Color3.fromRGB(26,38,52),muted=Color3.fromRGB(151,169,187),text=Color3.fromRGB(238,244,250),lime=Color3.fromRGB(190,243,103),red=Color3.fromRGB(255,122,125),blue=Color3.fromRGB(99,184,255)}
local function make(class,props,parent)
 local obj=Instance.new(class); for k,v in pairs(props or {}) do obj[k]=v end; obj.Parent=parent; return obj
end
local function corner(obj,r) make('UICorner',{CornerRadius=UDim.new(0,r or 12)},obj) end
local function frame(parent,x,y,w,h,bg)
 return make('Frame',{Position=UDim2.fromOffset(x,y),Size=UDim2.fromOffset(w,h),BackgroundColor3=bg or color.panel,BorderSizePixel=0},parent)
end
local function label(parent,text,x,y,w,h,size,ink,bold)
 return make('TextLabel',{Text=text,Position=UDim2.fromOffset(x,y),Size=UDim2.fromOffset(w,h),BackgroundTransparency=1,TextColor3=ink or color.text,TextSize=size or 18,Font=bold and Enum.Font.GothamBold or Enum.Font.Gotham,TextXAlignment=Enum.TextXAlignment.Left,TextYAlignment=Enum.TextYAlignment.Center,TextTruncate=Enum.TextTruncate.AtEnd},parent)
end
local function button(parent,text,x,y,w,h,callback,style)
 local bright=style=='primary'; local b=make('TextButton',{Text=text,Position=UDim2.fromOffset(x,y),Size=UDim2.fromOffset(w,h),BackgroundColor3=bright and color.lime or color.card,BorderSizePixel=0,TextColor3=bright and color.bg or style=='danger' and color.red or color.text,Font=Enum.Font.GothamBold,TextSize=16,AutoButtonColor=true},parent)
 corner(b,10); b.Activated:Connect(callback); return b
end
local function card(parent,x,y,w,h) local f=frame(parent,x,y,w,h,color.card); corner(f,14); return f end
local bg=make('Frame',{Size=UDim2.fromScale(1,1),BackgroundColor3=color.bg,BorderSizePixel=0},gui)
local root=frame(gui,0,0,1280,800,color.bg); root.AnchorPoint=Vector2.new(.5,.5); root.Position=UDim2.fromScale(.5,.5)
local scaler=make('UIScale',{},root)
local function resize()
 local camera=workspace.CurrentCamera; if camera then local v=camera.ViewportSize; scaler.Scale=math.min(v.X/1280,v.Y/800) end
end
resize(); workspace.CurrentCamera:GetPropertyChangedSignal('ViewportSize'):Connect(resize)
local shell=frame(root,0,0,1280,800,color.bg)
local side=frame(shell,0,0,220,800,color.panel)
label(side,'TOUCHLINE',22,26,180,30,24,color.lime,true); label(side,'D Y N A S T Y',24,58,180,24,14,color.muted)
label(side,'ТВОЯ КЛУБНАЯ ИСТОРИЯ',24,106,184,20,11,color.muted)
local header=frame(shell,244,18,1012,80,color.bg)
local content=make('ScrollingFrame',{Position=UDim2.fromOffset(244,116),Size=UDim2.fromOffset(1012,660),BackgroundTransparency=1,BorderSizePixel=0,ScrollBarThickness=5,ScrollBarImageColor3=color.muted,CanvasSize=UDim2.fromOffset(0,680)},shell)
local profile=nil; local currentTab='Клуб'; local selectedSlot=nil; local match=nil; local snapshot=nil; local drawPositions={}; local tabButtons={}; local draw
local command=net and net:WaitForChild('Command'); local event=net and net:WaitForChild('Event')
local function send(action,arg) if command then command:FireServer(action,arg or {}) end end
local function cash(n)
 if n>=1000000 then return string.format('€ %.2f млн',n/1000000) end
 return '€ '..tostring(math.floor(n/1000))..' тыс'
end
local toast=label(root,'',270,738,740,48,18,color.lime,true); toast.BackgroundColor3=color.panel; toast.BackgroundTransparency=.04; toast.ZIndex=50; toast.Visible=false; corner(toast,12)
local toastId=0
local function notify(text)
 toastId=toastId+1; local id=toastId; toast.Text='   '..tostring(text); toast.Visible=true
 task.delay(3.5,function() if id==toastId then toast.Visible=false end end)
end
local overlay=nil
local function modal(title,body,yes,callback)
 if overlay then overlay:Destroy() end
 overlay=frame(root,0,0,1280,800,Color3.new(0,0,0)); overlay.BackgroundTransparency=.25; overlay.ZIndex=30
 local box=card(overlay,360,230,560,310); box.ZIndex=31
 local t=label(box,title,28,24,504,50,25,color.text,true); t.ZIndex=32
 local b=label(box,body,28,85,504,106,18,color.muted); b.TextWrapped=true; b.TextTruncate=Enum.TextTruncate.None; b.ZIndex=32
 local function close() if overlay then overlay:Destroy(); overlay=nil end end
 local ok=button(box,yes or 'Продолжить',28,230,245,52,function() close(); if callback then callback() end end,'primary'); ok.ZIndex=32
 if callback then local no=button(box,'Отмена',288,230,245,52,close); no.ZIndex=32 end
end
local function find(id) if profile then for _,q in ipairs(profile.roster) do if q.id==id then return q end end end end
local function section(text,y) label(content,text,0,y,1000,35,22,color.text,true) end
local function explain(text,y) label(content,text,0,y,990,30,16,color.muted) end
local function headerDraw()
 header:ClearAllChildren()
 label(header,profile.club,0,0,650,40,28,color.text,true)
 label(header,'СЕЗОН '..profile.season..'   /   ДИВИЗИОН '..profile.division..'   /   ТУР '..math.min(14,profile.round)..' ИЗ 14',0,45,650,24,13,color.muted)
 label(header,cash(profile.cash),720,5,290,36,25,color.lime,true)
 label(header,'Сила '..profile.strength..'   •   Репутация '..profile.reputation,720,44,290,25,14,color.muted)
end
local function dashboard()
 local hero=card(content,0,0,995,238)
 label(hero,'СЛЕДУЮЩАЯ ГЛАВА',25,18,600,22,12,color.lime,true)
 label(hero,profile.next and profile.next.name or 'Сезон завершён',25,53,930,50,32,color.text,true)
 label(hero,profile.next and ((profile.next.home and 'Домашний матч' or 'Выездной матч')..'   •   Сила соперника '..profile.next.rating..'   •   2 минуты') or 'Забери награду и переходи в новый сезон',25,110,930,30,17,color.muted)
 if profile.next then
  button(hero,'ИГРАТЬ МАТЧ',25,167,265,48,function() send('play',{kind='league'}) end,'primary')
  button(hero,'Симулировать',305,167,230,48,function() send('simulate',{kind='league'}) end)
 else button(hero,'НОВЫЙ СЕЗОН',25,167,300,48,function() send('season') end,'primary') end
 local a=card(content,0,256,320,114); label(a,'ТРОФЕИ',20,15,270,24,12,color.muted); label(a,tostring(profile.trophies),20,45,270,48,34,color.lime,true)
 local b=card(content,337,256,320,114); label(b,'ПОБЕДЫ В КАРЬЕРЕ',20,15,270,24,12,color.muted); label(b,tostring(profile.wins),20,45,270,48,34,color.text,true)
 local c=card(content,674,256,321,114); label(c,'ТВОЯ КОМАНДА',20,15,270,24,12,color.muted); label(c,#profile.roster..' игроков',20,45,280,48,26,color.text,true)
 local cup=card(content,0,390,995,142)
 label(cup,'КУБОК СОЗВЕЗДИЙ',22,15,450,30,20,color.text,true)
 label(cup,profile.cupDone and 'Трофей твой. Отличный сезон!' or not profile.cupAlive and 'Команда выбыла. Новый шанс в следующем сезоне.' or ({'Четвертьфинал','Полуфинал','Финал'})[profile.cupStage],22,55,550,30,17,color.muted)
 if profile.cupAlive and not profile.cupDone then
  button(cup,'Играть кубок',620,20,350,45,function() send('play',{kind='cup'}) end,'primary')
  button(cup,'Симуляция кубка',620,78,350,43,function() send('simulate',{kind='cup'}) end)
 end
 section('Последний результат',553); explain(profile.lastResult~='' and profile.lastResult or 'Первый свисток ещё впереди. Твоя история начинается здесь.',595)
 label(content,profile.saveStatus or '',0,633,995,24,13,color.muted)
end
local function squad()
 section('Тактика и стартовый состав',0)
 for i,f in ipairs({'4-3-3','4-4-2','3-5-2'}) do button(content,f, (i-1)*130,45,120,40,function() send('formation',{value=f}) end,profile.formation==f and 'primary' or nil) end
 for i,t in ipairs({{'defend','Защита'},{'balanced','Баланс'},{'attack','Атака'}}) do button(content,t[2],410+(i-1)*130,45,120,40,function() send('mentality',{value=t[1]}) end,profile.mentality==t[1] and 'primary' or nil) end
 button(content,'Отдых · 30 тыс',810,45,180,40,function() send('rest') end)
 explain(selectedSlot and ('Замена позиции №'..selectedSlot..': выбери футболиста ниже') or 'Нажми «Заменить», затем выбери игрока. Чужая позиция снижает силу.',98)
 local roles={'GK'}; local groups=profile.formation=='4-4-2' and {4,4,2} or profile.formation=='3-5-2' and {3,5,2} or {4,3,3}
 for g,n in ipairs(groups) do for _=1,n do roles[#roles+1]=({'DEF','MID','FWD'})[g] end end
 local lineup={}; for slot,id in ipairs(profile.lineup) do lineup[id]=slot end
 local sorted={}; for _,id in ipairs(profile.lineup) do table.insert(sorted,find(id)) end
 for _,q in ipairs(profile.roster) do if not lineup[q.id] then table.insert(sorted,q) end end
 local y=145
 for _,q in ipairs(sorted) do
  local slot=lineup[q.id]; local row=card(content,0,y,995,60)
  label(row,slot and ('#'..slot..'  '..roles[slot]) or 'ЗАПАС',15,8,100,44,14,slot and color.lime or color.muted,true)
  label(row,q.name,125,4,260,29,17,color.text,true)
  label(row,q.pos..'  •  '..q.age..' лет   •   потенциал '..q.potential,125,31,290,22,12,color.muted)
  label(row,tostring(q.rating),420,8,55,44,26,color.lime,true)
  label(row,'Форма '..q.fitness..'%',490,6,140,25,14,q.fitness<65 and color.red or color.muted)
  label(row,q.goals..' гол.  '..q.assists..' пас.',490,32,140,20,12,color.muted)
  if selectedSlot then
   button(row,'Поставить',675,10,145,40,function() send('swap',{slot=selectedSlot,id=q.id}); selectedSlot=nil end,'primary')
  elseif slot then button(row,'Заменить',675,10,145,40,function() selectedSlot=slot; draw() end)
  else button(row,'В состав',675,10,145,40,function() notify('Сначала нажми «Заменить» у игрока основы') end) end
  if not slot then button(row,'Продать',835,10,145,40,function()
   modal('Продать игрока?',q.name..' покинет клуб. Цена продажи — 75% оценочной стоимости.','Продать',function() send('sell',{id=q.id}) end)
  end,'danger') end
  y=y+70
 end
 content.CanvasSize=UDim2.fromOffset(0,y+20)
end
local function market()
 section('Трансферный рынок',0); explain('Новые предложения после тура лиги. Лимит состава: 25 игроков.',43)
 local y=94
 for _,q in ipairs(profile.market) do
  local row=card(content,0,y,995,78)
  label(row,tostring(q.rating),18,16,70,45,30,color.lime,true)
  label(row,q.name,105,9,360,30,20,color.text,true)
  label(row,q.pos..'   •   '..q.age..' лет   •   потенциал '..q.potential..(q.free and '   •   свободный агент' or ''),105,43,550,25,14,color.muted)
  button(row,cash(q.price)..'  /  Купить',705,17,270,44,function() send('buy',{id=q.id}) end,'primary'); y=y+90
 end
 content.CanvasSize=UDim2.fromOffset(0,y)
end
local function academy()
 section('Построй будущее клуба',0); explain('Тренировки растят рейтинг после матчей. Академия выпускает молодёжь раз в сезон.',44)
 local defs={{'training','Тренировочная база','Больше опыта за каждый сыгранный матч.'},{'academy','Академия','Выше стартовый рейтинг новых талантов.'},{'stadium','Стадион','Больше дохода за каждый матч.'}}
 for i,d in ipairs(defs) do
  local y=100+(i-1)*138; local n=profile.upgrades[d[1]]; local box=card(content,0,y,995,120)
  label(box,d[2],22,14,620,32,22,color.text,true); label(box,'Уровень '..n..'/10  •  '..d[3],22,60,670,35,15,color.muted)
  button(box,n<10 and ('Улучшить · '..cash(n*n*80000)) or 'Максимум',702,36,270,48,function() send('upgrade',{key=d[1]}) end,n<10 and 'primary' or nil)
 end
 button(content,'Набор в академию · € 40 тыс',0,530,450,54,function() send('academy') end,'primary')
 explain(profile.academyYear==profile.season and 'Выпускник этого сезона уже в твоём составе.' or 'Выпускнику 16 лет. Найди место будущему капитану.',604)
end
local function league()
 section('Дивизион '..profile.division,0); explain('14 туров • топ-2 повышаются • последние 2 вылетают • разница мячей решает равенство очков',44)
 local columns={{'КЛУБ',64,370},{'И',470,60},{'В',550,60},{'Н',630,60},{'П',710,60},{'МЯЧИ',790,110},{'О',920,60}}
 for _,c in ipairs(columns) do label(content,c[1],c[2],100,c[3],25,13,color.muted,true) end
 for i,t in ipairs(profile.table) do
  local row=card(content,0,140+(i-1)*59,995,51)
  if t.name==profile.club then row.BackgroundColor3=Color3.fromRGB(40,61,42) end
  label(row,tostring(i),18,4,40,43,18,color.lime,true); label(row,t.name,64,4,370,43,17,color.text,true)
  for k,v in ipairs({t.played,t.w,t.d,t.l,t.gf..':'..t.ga,t.pts}) do label(row,tostring(v),({470,550,630,710,790,920})[k],4,k==5 and 110 or 60,43,18,k==6 and color.lime or color.text,k==6) end
 end
end
local function history()
 section('Карьера менеджера',0); explain('Репутация '..profile.reputation..'   •   Трофеи '..profile.trophies..'   •   Победы '..profile.wins,43)
 for i,name in ipairs({'Одесский Маяк','Киев Аврора','Львов Роверс'}) do
  button(content,name,(i-1)*335,94,320,46,function()
   modal('Сменить клуб?',name..': новый состав, бюджет и инфраструктура. Трофеи менеджера сохраняются. Цена: 30 репутации.','Принять',function() send('job',{index=i}) end)
  end)
 end
 explain('Предложения доступны с сезона 2, до первого тура. Требуется 30 репутации.',151)
 section('Лента результатов',204)
 local y=250
 for i=#profile.history,1,-1 do local r=card(content,0,y,995,50); label(r,profile.history[i],18,4,960,42,16,color.text); y=y+59 end
 content.CanvasSize=UDim2.fromOffset(0,math.max(650,y))
end
local function help()
 section('Твоя команда. Твои решения.',0)
 local text='МАТЧ НА КОМПЬЮТЕРЕ\nWASD / стрелки — движение. E — пас. Пробел — удар.\nQ — выбрать ближайшего к мячу игрока. F — отбор.\nКлик по полю — бежать в точку. Мышь задаёт высоту удара по воротам.\n\nНА ТЕЛЕФОНЕ\nЛевый стик — движение. Справа — удар, пас, отбор и смена игрока.\nЛучше играть в горизонтальном положении.\n\nКАРЬЕРА\nПроведи 14 туров и закончи кубок, затем начни новый сезон.\nРейтинг, позиция и усталость влияют на силу команды.\nИгроки получают опыт, стареют и в 36 лет уступают место молодёжи.\nУ каждой карьеры свой состав и потенциал игроков.\n\nСОХРАНЕНИЯ\nАвтосохранение каждую минуту, после матча и при выходе.\nВыход из незавершённого матча считается поражением 0:3.\nВ неопубликованном Studio доступна временная тестовая карьера.'
 local t=label(content,text,0,55,995,500,18,color.muted); t.TextWrapped=true; t.TextTruncate=Enum.TextTruncate.None; t.TextYAlignment=Enum.TextYAlignment.Top
 button(content,'Сохранить сейчас',0,585,330,54,function() send('save') end,'primary')
end
local pages={['Клуб']=dashboard,['Состав']=squad,['Трансферы']=market,['Развитие']=academy,['Лига']=league,['Карьера']=history,['Помощь']=help}
draw=function()
 if not profile then return end
 headerDraw(); content:ClearAllChildren(); content.CanvasPosition=Vector2.new(0,0); content.CanvasSize=UDim2.fromOffset(0,660)
 for name,b in pairs(tabButtons) do b.BackgroundColor3=name==currentTab and color.lime or color.panel; b.TextColor3=name==currentTab and color.bg or color.muted end
 pages[currentTab]()
end
for i,name in ipairs({'Клуб','Состав','Трансферы','Развитие','Лига','Карьера','Помощь'}) do
 tabButtons[name]=button(side,name,16,153+(i-1)*67,188,52,function() currentTab=name; selectedSlot=nil; draw() end)
end
label(side,'11 НА 11. ОДНА ДИНАСТИЯ.',20,716,190,30,10,color.muted)
label(side,'ORIGINAL ROBLOX EDITION',20,750,190,22,10,color.lime)
label(content,'Загружаем твою карьеру…',0,180,995,60,28,color.text,true)
-- A top-down stadium, rendered from server snapshots with interpolation.
local matchRoot=frame(root,0,0,1280,800,color.bg); matchRoot.Visible=false
local scoreLabel=label(matchRoot,'0 : 0',480,10,320,55,36,color.text,true); scoreLabel.TextXAlignment=Enum.TextXAlignment.Center
local minuteLabel=label(matchRoot,"0′",590,67,100,30,19,color.lime,true); minuteLabel.TextXAlignment=Enum.TextXAlignment.Center
local homeName=label(matchRoot,'',30,20,440,40,21,color.lime,true)
local awayName=label(matchRoot,'',810,20,440,40,21,color.red,true); awayName.TextXAlignment=Enum.TextXAlignment.Right
local field=frame(matchRoot,65,110,1150,610,Color3.fromRGB(31,104,66)); corner(field,8)
for i=0,9 do local stripe=frame(field,i*115,0,115,610,i%2==0 and Color3.fromRGB(33,115,72) or Color3.fromRGB(29,105,65)); stripe.ZIndex=1 end
local lines=Color3.fromRGB(155,200,165)
local function pitchLine(x,y,w,h) local f=frame(field,x,y,w,h,lines); f.BackgroundTransparency=.2; f.ZIndex=2; return f end
pitchLine(0,0,1150,3); pitchLine(0,607,1150,3); pitchLine(0,0,3,610); pitchLine(1147,0,3,610); pitchLine(574,0,3,610)
local circle=frame(field,475,205,200,200,lines); circle.BackgroundTransparency=1; circle.ZIndex=2; corner(circle,100)
make('UIStroke',{Color=lines,Thickness=2,Transparency=.2},circle)
for _,x in ipairs({0,966}) do
 pitchLine(x,133,184,2); pitchLine(x,475,184,2); pitchLine(x==0 and 184 or 966,133,2,344)
 pitchLine(x==0 and 0 or 1081,219,69,2); pitchLine(x==0 and 0 or 1081,390,69,2); pitchLine(x==0 and 69 or 1081,219,2,173)
end
local leftGoal=frame(field,-20,219,20,172,Color3.fromRGB(185,200,215)); leftGoal.BackgroundTransparency=.3; leftGoal.ZIndex=2
local rightGoal=frame(field,1150,219,20,172,Color3.fromRGB(185,200,215)); rightGoal.BackgroundTransparency=.3; rightGoal.ZIndex=2
local dots={}
for i=1,22 do
 local d=frame(field,0,0,30,30,i<=11 and color.lime or color.red); d.AnchorPoint=Vector2.new(.5,.5); corner(d,15); d.ZIndex=5
 local stroke=make('UIStroke',{Color=Color3.fromRGB(12,26,24),Thickness=2},d)
 local n=label(d,tostring((i-1)%11+1),0,0,30,30,13,color.bg,true); n.TextXAlignment=Enum.TextXAlignment.Center; n.ZIndex=6
 dots[i]={frame=d,stroke=stroke}
end
local ball=frame(field,0,0,13,13,Color3.new(1,1,1)); ball.AnchorPoint=Vector2.new(.5,.5); corner(ball,7); ball.ZIndex=8
make('UIStroke',{Color=Color3.fromRGB(15,25,25),Thickness=2},ball)
local notice=label(matchRoot,'',210,347,860,65,29,color.text,true); notice.TextXAlignment=Enum.TextXAlignment.Center; notice.ZIndex=12
local controlHelp=label(matchRoot,'WASD — движение   E — пас   ПРОБЕЛ — удар   Q — смена   F — отбор',65,741,1000,34,16,color.muted)
button(matchRoot,'Выйти',1120,743,95,38,function() modal('Покинуть матч?','Будет записано техническое поражение 0:3.','Выйти',function() send('forfeit') end) end,'danger')
local function fieldPoint(screen)
 local pos,size=field.AbsolutePosition,field.AbsoluteSize
 return (screen.X-pos.X)/size.X*100,(screen.Y-pos.Y)/size.Y*64
end
field.InputBegan:Connect(function(input)
 if input.UserInputType==Enum.UserInputType.MouseButton1 or input.UserInputType==Enum.UserInputType.Touch then
  local x,y=fieldPoint(input.Position); send('control',{action='target',x=x,y=y})
 end
end)
local keys={}; local joystick=Vector2.new(0,0); local stickTouch=nil
local mobile=make('Frame',{Size=UDim2.fromScale(1,1),BackgroundTransparency=1,Visible=false},gui)
local stick=make('Frame',{Position=UDim2.new(0,22,1,-130),Size=UDim2.fromOffset(104,104),BackgroundColor3=color.panel,BackgroundTransparency=.15,Active=true,BorderSizePixel=0},mobile); corner(stick,52)
local thumb=frame(stick,32,32,40,40,color.lime); corner(thumb,20)
local function stickMove(pos)
 local centre=stick.AbsolutePosition+stick.AbsoluteSize/2; local delta=Vector2.new(pos.X,pos.Y)-centre
 if delta.Magnitude>36 then delta=delta.Unit*36 end
 joystick=delta/36; thumb.Position=UDim2.fromOffset(32+delta.X,32+delta.Y)
end
stick.InputBegan:Connect(function(input) if input.UserInputType==Enum.UserInputType.Touch then stickTouch=input; stickMove(input.Position) end end)
UIS.InputChanged:Connect(function(input) if input==stickTouch then stickMove(input.Position) end end)
UIS.InputEnded:Connect(function(input)
 if input==stickTouch then stickTouch=nil; joystick=Vector2.new(0,0); thumb.Position=UDim2.fromOffset(32,32) end
 keys[input.KeyCode]=nil
end)
local function action(a)
 local y=32
 if not UIS.TouchEnabled then local _,fy=fieldPoint(UIS:GetMouseLocation()); y=math.clamp(fy,24,40) end
 send('control',{action=a,y=y})
end
for i,d in ipairs({{'shoot','УДАР'},{'pass','ПАС'},{'tackle','ОТБОР'},{'switch','СМЕНА'}}) do
 local b=button(mobile,d[2],0,0,68,52,function() action(d[1]) end,i==1 and 'primary' or nil)
 b.Position=UDim2.new(1,-(i<=2 and 170 or 90),1,-(i%2==1 and 132 or 70)); b.TextSize=12
end
UIS.InputBegan:Connect(function(input,processed)
 if processed or not match then return end
 keys[input.KeyCode]=true
 local k=input.KeyCode
 if k==Enum.KeyCode.Space then action('shoot') elseif k==Enum.KeyCode.E then action('pass') elseif k==Enum.KeyCode.Q then action('switch') elseif k==Enum.KeyCode.F then action('tackle') end
end)
local function matchStart(s)
 match=true; snapshot=s; drawPositions={}; keys={}; joystick=Vector2.new(0,0)
 shell.Visible=false; matchRoot.Visible=true; mobile.Visible=UIS.TouchEnabled; homeName.Text=profile and profile.club or 'Твой клуб'; awayName.Text=s.op
 if overlay then overlay:Destroy(); overlay=nil end
end
local inputAccum=0
RunService.RenderStepped:Connect(function(dt)
 local camera=workspace.CurrentCamera
 if camera then camera.CameraType=Enum.CameraType.Scriptable; camera.CFrame=CFrame.new(Vector3.new(0,160,80),Vector3.new(0,0,0)) end
 if not match or not snapshot then return end
 scoreLabel.Text=snapshot.home..' : '..snapshot.away; minuteLabel.Text=tostring(snapshot.minute)..'′'; notice.Text=snapshot.notice or ''
 for i,p in ipairs(snapshot.players) do
  local target=Vector2.new(p.x*11.5,p.y*610/64); local current=drawPositions[i] or target
  current=current:Lerp(target,math.min(1,dt*18)); drawPositions[i]=current
  dots[i].frame.Position=UDim2.fromOffset(current.X,current.Y)
  dots[i].frame.BackgroundColor3=p.gk and (i<=11 and color.blue or Color3.fromRGB(255,191,94)) or i<=11 and color.lime or color.red
  dots[i].stroke.Color=i==snapshot.controlled and Color3.new(1,1,1) or color.bg; dots[i].stroke.Thickness=i==snapshot.controlled and 4 or 2
 end
 local target=Vector2.new(snapshot.ball.x*11.5,snapshot.ball.y*610/64); local b=drawPositions[23] or target; b=b:Lerp(target,math.min(1,dt*23)); drawPositions[23]=b; ball.Position=UDim2.fromOffset(b.X,b.Y)
 inputAccum=inputAccum+dt
 if inputAccum>=.08 then
  inputAccum=0
  local x=(keys[Enum.KeyCode.D] or keys[Enum.KeyCode.Right]) and 1 or 0; x=x-((keys[Enum.KeyCode.A] or keys[Enum.KeyCode.Left]) and 1 or 0)
  local y=(keys[Enum.KeyCode.S] or keys[Enum.KeyCode.Down]) and 1 or 0; y=y-((keys[Enum.KeyCode.W] or keys[Enum.KeyCode.Up]) and 1 or 0)
  if joystick.Magnitude>.05 then x=joystick.X; y=joystick.Y end
  send('input',{x=x,y=y})
 end
end)
if event then
 event.OnClientEvent:Connect(function(kind,data)
  if kind=='profile' then profile=data; if not match then draw() end
  elseif kind=='toast' then notify(data)
  elseif kind=='matchStart' then matchStart(data)
  elseif kind=='snapshot' then snapshot=data
  elseif kind=='result' then
   match=nil; snapshot=nil; shell.Visible=true; matchRoot.Visible=false; mobile.Visible=false; keys={}; currentTab='Клуб'
   local text=tostring(data.home)..' : '..tostring(data.away)..'   '..data.op..'\nДоход: '..cash(data.income)
   if data.penalties then text=text..'\n'..(data.penWin and 'Победа в серии пенальти!' or 'Поражение в серии пенальти') end
   modal('Матч завершён',text,'Дальше'); if profile then draw() end
  end
 end)
 send('ready')
 task.spawn(function() for _=1,30 do if profile then return end; task.wait(2); send('ready') end; notify('Загрузка затянулась. Проверь Output в Studio.') end)
else notify('Сервер не запустился. Открой Output в Roblox Studio.') end
pcall(function() require(player.PlayerScripts:WaitForChild('PlayerModule')):GetControls():Disable() end)
