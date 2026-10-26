-- One visible 2.5D presentation. Snapshots are visualized, never simulated here.
local UI=require(script.Parent.UI)
local Catalog=require(script.Parent.MonetizationConfig)
local V={}
local C=UI.colors
local function box(parent,x,y,w,h,color)
 local f=UI.frame(parent,'Shape',color); f.Position=UDim2.new(x,0,y,0); f.Size=UDim2.new(w,0,h,0); return f
end
local function circle(parent,x,y,w,h,color)
 local f=box(parent,x,y,w,h,color); UI.round(f,100); return f
end
function V.new(gui,tr,send)
 local self={tr=tr,send=send,buffer={},history={},figures={},visible=false,replay=nil,profile=nil,latest=nil,lastSeq=-1}
 setmetatable(self,{__index=V})
 self.root=UI.frame(gui,'Match',C.bg); self.root.Size=UDim2.fromScale(1,1); self.root.Visible=false; self.root.ZIndex=5
 self.stage=UI.frame(self.root,'Stadium',Color3.fromRGB(29,47,67)); self.stage.ClipsDescendants=true
 self.pitch=UI.frame(self.stage,'Pitch',Color3.fromRGB(35,113,73))
 self.grass={};for i=0,9 do self.grass[#self.grass+1]=box(self.pitch,i/10,0,.1,1,i%2==0 and Color3.fromRGB(38,123,77) or Color3.fromRGB(31,110,69)) end
 local line=Color3.fromRGB(213,231,210)
 for _,y in ipairs({0,1}) do local f=box(self.pitch,0,y,1,0,line); f.Size=UDim2.new(1,0,0,2) end
 for _,x in ipairs({0,.5,1}) do local f=box(self.pitch,x,0,0,1,line); f.Size=UDim2.new(0,2,1,0) end
 local center=UI.make('Frame',{Position=UDim2.fromScale(.5,.5),AnchorPoint=Vector2.new(.5,.5),Size=UDim2.fromScale(.18,.28),BackgroundTransparency=1},self.pitch); UI.round(center,100); UI.make('UIStroke',{Color=line,Thickness=2},center)
 circle(self.pitch,.495,.492,.01,.016,line)
 for _,x in ipairs({0,.84}) do
  local area=box(self.pitch,x,.2,.16,.6,line); area.BackgroundTransparency=1; UI.make('UIStroke',{Color=line,Thickness=2},area)
 end
 for _,x in ipairs({0,.94}) do
  local area=box(self.pitch,x,.34,.06,.32,line); area.BackgroundTransparency=1; UI.make('UIStroke',{Color=line,Thickness=2},area)
 end
 self.crest=UI.label(self.stage,'TD',32,true); self.crest.TextColor3=C.lime
 self.score=UI.label(self.root,'',22,true); self.score.TextXAlignment=Enum.TextXAlignment.Center
 self.clock=UI.label(self.root,'',15,false); self.clock.TextXAlignment=Enum.TextXAlignment.Center; self.clock.TextColor3=C.muted
 self.notice=UI.round(UI.frame(self.root,'Notice',C.panel)); self.noticeText=UI.label(self.notice,'',18,true); self.noticeText.Size=UDim2.new(1,-20,1,0); self.noticeText.Position=UDim2.fromOffset(10,0); self.noticeText.TextXAlignment=Enum.TextXAlignment.Center
 self.ball=UI.round(UI.frame(self.pitch,'Ball',Color3.fromRGB(248,247,230)),100); self.ball.Size=UDim2.fromOffset(9,9); self.ball.AnchorPoint=Vector2.new(.5,.5); self.ball.ZIndex=14
 self.ballShadow=UI.round(UI.frame(self.pitch,'BallShadow',Color3.fromRGB(8,35,22)),100); self.ballShadow.Size=UDim2.fromOffset(12,6); self.ballShadow.AnchorPoint=Vector2.new(.5,.5); self.ballShadow.BackgroundTransparency=.45
 for i=1,22 do
  local f={}; f.root=UI.make('Frame',{Name='Footballer'..i,Size=UDim2.fromOffset(24,31),BackgroundTransparency=1,AnchorPoint=Vector2.new(.5,.65),ZIndex=9},self.pitch)
  f.shadow=circle(f.root,.04,.64,.92,.24,Color3.fromRGB(8,35,22)); f.shadow.BackgroundTransparency=.4
  f.ring=UI.make('Frame',{Position=UDim2.fromScale(.08,.61),Size=UDim2.fromScale(.84,.33),BackgroundTransparency=1,Visible=false},f.root); UI.round(f.ring,100); UI.make('UIStroke',{Color=C.lime,Thickness=2},f.ring)
  f.left=box(f.root,.25,.58,.17,.3,Color3.fromRGB(235,235,229)); f.right=box(f.root,.58,.58,.17,.3,Color3.fromRGB(235,235,229))
  f.arm1=box(f.root,.08,.26,.17,.32,Color3.fromRGB(191,141,105)); f.arm2=box(f.root,.75,.26,.17,.32,Color3.fromRGB(191,141,105))
  f.shirt=UI.round(box(f.root,.24,.23,.52,.39,i<=11 and C.lime or C.blue),3)
  f.patterns={};for n=1,3 do local stripe=box(f.shirt,0,(n-1)/3,1,.13,Color3.fromRGB(20,34,45));stripe.Visible=false;f.patterns[n]=stripe end
  f.head=circle(f.root,.35,.03,.3,.27,Color3.fromRGB(211,166,123))
  f.number=UI.label(f.root,tostring((i-1)%11+1),9,true); f.number.Size=UDim2.fromScale(.6,.3); f.number.Position=UDim2.fromScale(.2,.26); f.number.TextXAlignment=Enum.TextXAlignment.Center; f.number.TextColor3=C.bg
  f.captain=box(f.root,.73,.35,.21,.08,Color3.fromRGB(250,217,83));f.captain.Visible=false
  f.card=box(f.root,.9,.05,.14,.25,C.red); f.card.Visible=false; self.figures[i]=f
 end
 self.replayButton=UI.button(self.root,tr:t('ui.replay'),function() self:startReplay() end)
 self.modeButton=UI.button(self.root,tr:t('ui.modeHighlights'),function() self.send('control',{action='mode',value=self.latest and self.latest.mode=='highlights' and 'manual' or 'highlights'}) end)
 self.pauseButton=UI.button(self.root,tr:t('ui.tactics'),function() if self.onTactics then self.onTactics() end end)
 self.exit=UI.button(self.root,tr:t('ui.forfeit'),function() if self.onForfeit then self.onForfeit() end end)
 self.penalty=UI.round(UI.frame(self.root,'Penalty',C.panel)); self.penalty.Visible=false; self.penaltyTitle=UI.label(self.penalty,'',16,true); self.penaltyTitle.Position=UDim2.fromOffset(8,4); self.penaltyTitle.Size=UDim2.new(1,-16,0,28)
 self.penButtons={}
 for i,aim in ipairs({-1,0,1}) do
  local b=UI.button(self.penalty,({'←','●','→'})[i],function() self.send('control',{action='penalty',aim=aim*.8,power=.82,dive=aim*.8}) end,true)
  b.Position=UDim2.new((i-1)/3,5,0,38); b.Size=UDim2.new(1/3,-10,0,50); self.penButtons[i]=b
 end
 self:resize(); return self
end
function V:resize()
 local size=workspace.CurrentCamera.ViewportSize; local portrait=size.Y>size.X; local w=math.min(size.X-36,(size.Y-(portrait and 300 or 172))*100/64)
 w=math.max(180,w); local h=w*64/100; local x=(size.X-w)/2; local y=portrait and 100 or 92
 self.stage.Position=UDim2.fromOffset(x-12,y-12); self.stage.Size=UDim2.fromOffset(w+24,h+24)
 self.pitch.Position=UDim2.fromOffset(12,12); self.pitch.Size=UDim2.fromOffset(w,h)
 self.crest.Position=UDim2.fromOffset(10,0); self.crest.Size=UDim2.fromOffset(90,45)
 self.score.Position=UDim2.fromOffset(10,8); self.score.Size=UDim2.new(1,-20,0,40)
 self.clock.Position=UDim2.fromOffset(10,49); self.clock.Size=UDim2.new(1,-20,0,28)
 self.notice.Position=UDim2.new(.5,-math.min(220,(size.X-30)/2),0,y+h*.42); self.notice.Size=UDim2.fromOffset(math.min(440,size.X-30),54)
 local buttons={self.replayButton,self.modeButton,self.pauseButton,self.exit}
 for i,b in ipairs(buttons) do b.Position=UDim2.new((i-1)/4,5,1,-54); b.Size=UDim2.new(.25,-10,0,46); b.TextSize=size.X<700 and 11 or 14 end
 self.penalty.Position=UDim2.new(.5,-math.min(180,(size.X-24)/2),1,-160); self.penalty.Size=UDim2.fromOffset(math.min(360,size.X-24),96)
end
function V:show(profile,snapshot)
 self.replayButton.Text=self.tr:t('ui.replay');self.modeButton.Text=self.tr:t('ui.modeHighlights');self.pauseButton.Text=self.tr:t('ui.tactics');self.exit.Text=self.tr:t('ui.forfeit')
 self.profile=profile; self.root.Visible=true; self.visible=true; self.buffer={}; self.history={}; self.lastSeq=-1; self.replay=nil;self.lastReplayId=0;self.goalFrames=nil;self.shakeUntil=0
 local equipped=profile and profile.cosmetics and profile.cosmetics.equipped or {}; local kit=equipped.kit or 'classic'
 local teamColor=kit=='sunset' and Color3.fromRGB(249,150,98) or kit=='lime' and C.lime or Color3.fromRGB(235,239,228)
 if profile and profile.settings and profile.settings.colorblind then teamColor=Color3.fromRGB(255,202,66) end
 for i,f in ipairs(self.figures) do f.shirt.BackgroundColor3=i<=11 and teamColor or C.blue end
 for _,item in ipairs(Catalog.items)do
  if item.id==kit then for i,f in ipairs(self.figures)do if i<=11 then f.shirt.BackgroundColor3=profile.settings and profile.settings.colorblind and Color3.fromRGB(255,202,66) or Color3.fromRGB(item.colors[1],item.colors[2],item.colors[3]);for n,stripe in ipairs(f.patterns)do stripe.Visible=item.pattern~='solid';stripe.Rotation=item.pattern=='sash' and 30 or 0;stripe.Size=item.pattern=='stripe' and UDim2.fromScale(.15,1) or UDim2.fromScale(1,.13);stripe.Position=item.pattern=='stripe' and UDim2.fromScale((n-1)/3,0) or UDim2.fromScale(0,(n-1)/3) end end end end
  if item.id==equipped.stadium and item.pitchColors then for i,stripe in ipairs(self.grass)do local c=item.pitchColors;stripe.BackgroundColor3=Color3.fromRGB(c[1]+i%2*5,c[2]+i%2*8,c[3]+i%2*5)end end
  if item.id==equipped.broadcast and item.accent then local c=item.accent;self.clock.TextColor3=Color3.fromRGB(c[1],c[2],c[3]) end
 end
 local design=profile and profile.cosmetics and profile.cosmetics.design
 if design and design.color then for i=1,11 do if not(profile.settings and profile.settings.colorblind)then self.figures[i].shirt.BackgroundColor3=Color3.fromRGB(design.color[1],design.color[2],design.color[3])end end end
 self.crest.Text=design and (({shield='▰',round='●',diamond='◆',star='★'})[design.shape]..tostring(design.symbol))or(equipped.crest=='crest_star' and '★ TD' or 'TD')..(equipped.badge=='supporter_badge' and ' ♦' or '')
 self.stage.BackgroundColor3=equipped.stadium=='night' and Color3.fromRGB(8,17,38) or Color3.fromRGB(29,47,67)
 self.score.TextColor3=equipped.broadcast=='clean' and C.text or C.lime
 self:resize(); if snapshot then self:push(snapshot) end
end
function V:push(snapshot)
 if type(snapshot)~='table' or type(snapshot.players)~='table' then return false end
 local seq=snapshot.seq or 0; if seq<=self.lastSeq then return false end; self.lastSeq=seq
 local goalReplay=(snapshot.replayId or 0)>(self.lastReplayId or 0)
 if (snapshot.replayId or 0)>(self.lastReplayId or 0) then self.lastReplayId=snapshot.replayId;if self.profile and self.profile.settings and self.profile.settings.shake and not self.profile.settings.reducedMotion then self.shakeUntil=os.clock()+.2 end end
 snapshot.received=os.clock(); self.latest=snapshot; self.buffer[#self.buffer+1]=snapshot; self.history[#self.history+1]=snapshot
 while #self.buffer>8 do table.remove(self.buffer,1) end
 while #self.history>48 do table.remove(self.history,1) end
 if goalReplay then self.goalFrames={};for i=math.max(1,#self.history-35),#self.history do self.goalFrames[#self.goalFrames+1]=self.history[i]end end
 return true
end
function V:startReplay()
 if self.replay then self.replay=nil;return end
 local source=self.goalFrames or self.history;if #source<4 then return end
 self.replay={frames={},started=os.clock()};for i=math.max(1,#source-35),#source do self.replay.frames[#self.replay.frames+1]=source[i]end
end
function V:render()
 if not self.visible or not self.latest then return end
 local shake=os.clock()<(self.shakeUntil or 0)and 2 or 0;self.pitch.Position=UDim2.fromOffset(12+math.sin(os.clock()*67)*shake,12+math.cos(os.clock()*71)*shake)
 local latest=self.latest; local a,b,t=latest,latest,0; local now=os.clock()
 if self.replay then
  local elapsed=now-self.replay.started; local frames=self.replay.frames; local index=math.floor(elapsed*10)+1
  if index>=#frames then self.replay=nil else a=frames[index]; b=frames[index+1]; t=elapsed*10-math.floor(elapsed*10) end
 else
  local target=(latest.time or 0)+math.min(.1,now-latest.received)-.12
  for i=1,#self.buffer-1 do local p,q=self.buffer[i],self.buffer[i+1]
   if (p.time or 0)<=target and (q.time or 0)>=target then a,b=p,q; t=math.max(0,math.min(1,(target-(p.time or 0))/math.max(.001,(q.time or 0)-(p.time or 0)))); break end
  end
 end
 for i,f in ipairs(self.figures) do
  local p,q=a.players[i],b.players[i]; f.root.Visible=p~=nil and p.active~=false
  if p and q then
   local x=p.x+(q.x-p.x)*t; local y=p.y+(q.y-p.y)*t; f.root.Position=UDim2.fromScale(x/100,y/64)
   local moving=not(self.profile and self.profile.settings and self.profile.settings.reducedMotion)and math.abs(q.x-p.x)+math.abs(q.y-p.y)>.05; local stride=moving and math.sin(now*15+i)*18 or 0
   f.left.Rotation=stride; f.right.Rotation=-stride; f.arm1.Rotation=-stride*.5; f.arm2.Rotation=stride*.5
   f.head.Position=UDim2.fromScale(.35+math.cos(p.angle or 0)*.03,.03+math.sin(p.angle or 0)*.03)
   f.captain.Visible=i==latest.captain;f.ring.Visible=i==latest.controlled; f.card.Visible=(p.card or 0)>0; f.card.BackgroundColor3=(p.card or 0)>=2 and C.red or Color3.fromRGB(255,215,61)
  end
 end
 local bx=a.ball.x+(b.ball.x-a.ball.x)*t; local by=a.ball.y+(b.ball.y-a.ball.y)*t
 self.ball.Position=UDim2.fromScale(bx/100,by/64); self.ballShadow.Position=UDim2.new(bx/100,1,by/64,4)
 local club=self.profile and self.profile.club or 'Touchline'; local op=latest.op or ''
 self.score.Text=latest.userHome==false and (op..'  '..latest.away..' : '..latest.home..'  '..club) or (club..'  '..latest.home..' : '..latest.away..'  '..op)
 self.clock.Text=tostring(latest.minute or 0).."′  ·  "..self.tr:t('ui.mode'..(latest.mode=='highlights' and 'Highlights' or latest.mode=='simulate' and 'Simulate' or 'Manual'))
 local tutorial=latest.training
 if tutorial then self.clock.Text=self.tr:t('training.'..tutorial.kind)..' · '..tostring(tutorial.progress)..' / '..tostring(tutorial.target>0 and tutorial.target or 3)..' · '..tostring(tutorial.remaining or 0)..'s' end
 self.notice.Visible=self.replay~=nil or (latest.notice~=nil and latest.notice~=''); self.noticeText.Text=self.replay and self.tr:t('ui.replay') or self.tr:t(latest.notice or '')
 if tutorial and tutorial.kind=='tutorial' then self.notice.Visible=true;self.noticeText.Text=self.tr:t('training.step'..math.min(3,tutorial.step)) end
 self.penalty.Visible=latest.phase=='penalties';pcall(function()local g=game:GetService('GuiService');if self.penalty.Visible then if not g.SelectedObject or g.SelectedObject.Parent~=self.penalty then g.SelectedObject=self.penButtons[2]end elseif g.SelectedObject and g.SelectedObject.Parent==self.penalty then g.SelectedObject=nil end end); self.penaltyTitle.Text=self.tr:t(latest.penalties and latest.penalties.turn==2 and 'ui.goalkeeper' or 'ui.penalty')
end
function V:hide() self.visible=false; self.root.Visible=false; self.buffer={}; self.history={}; self.latest=nil; self.replay=nil end
return V
