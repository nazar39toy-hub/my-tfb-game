-- Retained responsive shell and virtual list. No domain calculations run per frame.
local UI={}
UI.colors={bg=Color3.fromRGB(10,17,28),panel=Color3.fromRGB(19,30,45),card=Color3.fromRGB(28,43,60),text=Color3.fromRGB(239,245,247),muted=Color3.fromRGB(164,183,200),lime=Color3.fromRGB(194,242,102),red=Color3.fromRGB(255,133,139),blue=Color3.fromRGB(104,190,242)}
function UI.make(class,props,parent)
 local obj=Instance.new(class);if class=='TextLabel'or class=='TextButton'or class=='TextBox'then obj.AutoLocalize=false end; for key,value in pairs(props or {}) do obj[key]=value end; obj.Parent=parent; return obj
end
function UI.round(obj,r) UI.make('UICorner',{CornerRadius=UDim.new(0,r or 10)},obj); return obj end
function UI.frame(parent,name,bg)
 return UI.make('Frame',{Name=name,BackgroundColor3=bg or UI.colors.panel,BorderSizePixel=0},parent)
end
function UI.label(parent,text,size,bold)
 return UI.make('TextLabel',{Text=text or '',BackgroundTransparency=1,TextColor3=UI.colors.text,TextSize=size or 16,Font=bold and Enum.Font.GothamBold or Enum.Font.Gotham,TextWrapped=true,TextXAlignment=Enum.TextXAlignment.Left,TextYAlignment=Enum.TextYAlignment.Center},parent)
end
function UI.button(parent,text,callback,primary)
 local b=UI.round(UI.make('TextButton',{Text=text or '',BackgroundColor3=primary and UI.colors.lime or UI.colors.card,TextColor3=primary and UI.colors.bg or UI.colors.text,BorderSizePixel=0,Font=Enum.Font.GothamBold,TextSize=14,TextWrapped=true,AutoButtonColor=true,Selectable=true},parent))
 local state={callback=callback,enabled=true,nextAllowed=0}; b.Activated:Connect(function() if state.enabled and state.callback and os.clock()>=state.nextAllowed then state.nextAllowed=os.clock()+.3;state.callback() end end)
 return b,state
end
local groups={
 {id='club',pages={'hub','inbox','calendar'}},{id='team',pages={'squad','tactics','academy','training'}},
 {id='football',pages={'table','cup'}},{id='business',pages={'market','scout','stadium','finances'}},
 {id='career',pages={'history','goals'}},{id='identity',pages={'shop','inventory','settings','help'}}
}
UI.groups=groups
function UI.new(player,tr,handlers)
 local self={tr=tr,handlers=handlers,pages={},current='hub',group='club',mobile=false,textScale=1,profile=nil,filters={},connections={},nav={},tabs={},dead=false}
 setmetatable(self,{__index=UI})
 self.gui=UI.make('ScreenGui',{Name='TouchlineDynasty',ResetOnSpawn=false,IgnoreGuiInset=false,ZIndexBehavior=Enum.ZIndexBehavior.Sibling},player:WaitForChild('PlayerGui'))
 pcall(function() self.gui.ClipToDeviceSafeArea=true end)
 self.root=UI.frame(self.gui,'Shell',UI.colors.bg); self.root.Size=UDim2.fromScale(1,1)
 self.header=UI.frame(self.root,'Header',UI.colors.panel); self.brand=UI.label(self.header,'TOUCHLINE DYNASTY',19,true)
 self.club=UI.label(self.header,'',14,false); self.budget=UI.label(self.header,'',14,true)
 self.sidebar=UI.frame(self.root,'Navigation',UI.colors.panel)
 self.tabbar=UI.make('ScrollingFrame',{Name='Sections',BackgroundTransparency=1,BorderSizePixel=0,ScrollBarThickness=0,ScrollingDirection=Enum.ScrollingDirection.X,CanvasSize=UDim2.fromOffset(900,0)},self.root)
 self.title=UI.label(self.root,'',24,true)
 self.search=UI.make('TextBox',{Name='Search',PlaceholderText=tr:t('ui.search'),Text='',ClearTextOnFocus=false,TextColor3=UI.colors.text,PlaceholderColor3=UI.colors.muted,TextSize=16,Font=Enum.Font.Gotham,BackgroundColor3=UI.colors.card,BorderSizePixel=0},self.root); UI.round(self.search)
 self.filter,self.filterState=UI.button(self.root,'',function() self:cycleFilter() end)
 self.sort,self.sortState=UI.button(self.root,'',function() self:cycleSort() end)
 self.toast=UI.round(UI.frame(self.root,'Notification',UI.colors.card)); self.toast.Visible=false; self.toast.ZIndex=30
 self.toastText=UI.label(self.toast,'',16,false); self.toastText.Size=UDim2.new(1,-24,1,0); self.toastText.Position=UDim2.fromOffset(12,0); self.toastText.ZIndex=31
 for i,g in ipairs(groups) do
  local id=g.id; local b,state=UI.button(self.sidebar,tr:t('ui.'..id),function() self:open(g.pages[1]) end)
  self.nav[i]={button=b,state=state,id=id}
 end
 self.search:GetPropertyChangedSignal('Text'):Connect(function()
  local f=self.filters[self.current] or {position=1,sort=1}; self.filters[self.current]=f; f.query=self.search.Text; self:refresh(false)
 end)
 self.connections[#self.connections+1]=workspace.CurrentCamera:GetPropertyChangedSignal('ViewportSize'):Connect(function() self:resize() end)
 self:resize(); self:open('hub'); return self
end
function UI:resize()
 local viewport=workspace.CurrentCamera.ViewportSize; self.width,self.height=viewport.X,viewport.Y; self.mobile=viewport.X<850
 local side=self.mobile and 0 or 184; local pad=self.mobile and 12 or 24; local navH=self.mobile and 64 or 0
 self.contentX=side+pad; self.contentW=math.max(220,viewport.X-side-pad*2)
 self.header.Position=UDim2.fromOffset(side,0); self.header.Size=UDim2.new(1,-side,0,76)
 self.brand.Position=UDim2.fromOffset(pad,10); self.brand.Size=UDim2.new(.58,-pad,0,26)
 self.club.Position=UDim2.fromOffset(pad,39); self.club.Size=UDim2.new(.62,-pad,0,26)
 self.budget.Position=UDim2.new(.62,0,0,22); self.budget.Size=UDim2.new(.38,-pad,0,40)
 self.sidebar.Position=self.mobile and UDim2.new(0,0,1,-64) or UDim2.fromOffset(0,0)
 self.sidebar.Size=self.mobile and UDim2.new(1,0,0,64) or UDim2.new(0,184,1,0)
 for i,n in ipairs(self.nav) do
  n.button.Position=self.mobile and UDim2.new((i-1)/6,2,0,5) or UDim2.fromOffset(12,84+(i-1)*60)
  n.button.Size=self.mobile and UDim2.new(1/6,-4,0,54) or UDim2.fromOffset(160,48); n.button.TextSize=self.mobile and 11 or 15
 end
 self.tabbar.Position=UDim2.fromOffset(self.contentX,80); self.tabbar.Size=UDim2.fromOffset(self.contentW,48)
 self.title.Position=UDim2.fromOffset(self.contentX,136); self.title.Size=UDim2.fromOffset(self.contentW,34)
 self.search.Position=UDim2.fromOffset(self.contentX,178); self.search.Size=UDim2.new(0,math.max(100,self.contentW-206),0,46)
 self.filter.Position=UDim2.fromOffset(self.contentX+self.contentW-198,178); self.filter.Size=UDim2.fromOffset(94,46)
 self.sort.Position=UDim2.fromOffset(self.contentX+self.contentW-98,178); self.sort.Size=UDim2.fromOffset(98,46)
 self.listY=234; self.listH=math.max(80,viewport.Y-self.listY-navH-12)
 for _,page in pairs(self.pages) do page.frame.Position=UDim2.fromOffset(self.contentX,self.listY); page.frame.Size=UDim2.fromOffset(self.contentW,self.listH) end
 self.toast.Position=UDim2.new(.5,-math.min(260,(viewport.X-24)/2),1,-navH-84); self.toast.Size=UDim2.fromOffset(math.min(520,viewport.X-24),64)
 self:refresh(false)
end
function UI:clearSelection()
 pcall(function()game:GetService('GuiService').SelectedObject=nil end)
end
function UI:selectDefault()
 if self.matchActive then return end
 local page=self.pages[self.current];local row=page and page.rows[1];local action=row and row.actions[1]
 local button=action and action.button.Visible and action.state.enabled and action.button or self.nav[1].button
 pcall(function()local service=game:GetService('GuiService');service.AutoSelectGuiEnabled=true;service.SelectedObject=button end)
end
function UI:open(page)
 self.current=page
 for _,g in ipairs(groups) do for _,id in ipairs(g.pages) do if id==page then self.group=g.id end end end
 for id,p in pairs(self.pages) do p.frame.Visible=id==page end
 if not self.pages[page] then
  local f=UI.make('ScrollingFrame',{Name=page,BackgroundTransparency=1,BorderSizePixel=0,ScrollBarThickness=4,ScrollBarImageColor3=UI.colors.muted,CanvasSize=UDim2.fromOffset(0,0),Position=UDim2.fromOffset(self.contentX,self.listY),Size=UDim2.fromOffset(self.contentW,self.listH)},self.root)
  local p={frame=f,rows={},items={}}; self.pages[page]=p
  f:GetPropertyChangedSignal('CanvasPosition'):Connect(function() if self.current==page then self:paint() end end)
 end
 self.pages[page].frame.Visible=true
 for _,tab in ipairs(self.tabs) do tab.button.Visible=false end
 local chosen
 for _,g in ipairs(groups) do if g.id==self.group then chosen=g end end
 if chosen then
  for i,id in ipairs(chosen.pages) do
   if not self.tabs[i] then local b,s=UI.button(self.tabbar,'',nil); self.tabs[i]={button=b,state=s} end
   local tab=self.tabs[i]; tab.button.Visible=true; tab.button.Text=self.tr:t('ui.'..id); tab.button.Position=UDim2.fromOffset((i-1)*132,0); tab.button.Size=UDim2.fromOffset(124,46)
   tab.button.BackgroundColor3=id==page and UI.colors.lime or UI.colors.card; tab.button.TextColor3=id==page and UI.colors.bg or UI.colors.text
   tab.state.callback=function() self:open(id) end
  end
  self.tabbar.CanvasSize=UDim2.fromOffset(#chosen.pages*132,0)
 end
 for _,n in ipairs(self.nav) do n.button.BackgroundColor3=n.id==self.group and UI.colors.card or UI.colors.panel end
 local filter=self.filters[page] or {position=1,sort=1,query=''}; self.filters[page]=filter; self.search.Text=filter.query or ''
 self:refresh(false);self:selectDefault()
end
function UI:cycleFilter()
 local f=self.filters[self.current]; f.position=((f.position or 1)%5)+1; self:refresh(false)
end
function UI:cycleSort()
 local f=self.filters[self.current]; f.sort=((f.sort or 1)%6)+1; self:refresh(false)
end
function UI:refresh(reset)
 if not self.pages[self.current] then return end
 local p=self.profile; self.brand.Text='TOUCHLINE DYNASTY'
 self.club.Text=p and (p.club..'  ·  '..self.tr:t('ui.season')..' '..tostring(p.season)..' / '..tostring(p.division)) or self.tr:t('ui.loading')
 self.budget.Text=p and self.tr:money(p.cash or 0) or ''
 self.title.Text=self.tr:t('ui.'..self.current)
 local f=self.filters[self.current] or {position=1,sort=1,query=''}; local positions={'all','GK','DEF','MID','FWD'}
 self.filter.Text=self.tr:t(positions[f.position or 1]=='all' and 'ui.all' or ('position.'..positions[f.position or 1]))
 self.sort.Text=self.tr:t('ui.'..({'name','rating','age','price','wage','contract'})[f.sort or 1])
 local searchable=self.current=='market' or self.current=='squad' or self.current=='scout'
 self.search.Visible=searchable; self.filter.Visible=searchable; self.sort.Visible=searchable
 local listY=searchable and 234 or 180; self.listY=listY; self.listH=math.max(80,self.height-listY-(self.mobile and 76 or 12))
 local page=self.pages[self.current]; page.frame.Position=UDim2.fromOffset(self.contentX,listY); page.frame.Size=UDim2.fromOffset(self.contentW,self.listH)
 local items=self.handlers.items(self.current,p,f,self) or {}; page.items=items
 self.rowH=self.mobile and math.floor(214*self.textScale) or math.floor(156*self.textScale)
 page.frame.CanvasSize=UDim2.fromOffset(0,#items*self.rowH+12)
 if reset then page.frame.CanvasPosition=Vector2.new(0,0) end
 self:paint()
end
function UI:paint()
 local page=self.pages[self.current]; if not page then return end
 local offset=page.frame.CanvasPosition and page.frame.CanvasPosition.Y or 0; local first=math.max(1,math.floor(offset/self.rowH)+1)
 local visible=math.min(24,math.ceil(self.listH/self.rowH)+2)
 for i=1,visible do
  local row=page.rows[i]
  if not row then
   row={}; row.frame=UI.round(UI.frame(page.frame,'Row'..i,UI.colors.panel)); row.title=UI.label(row.frame,'',18,true); row.body=UI.label(row.frame,'',14,false); row.body.TextColor3=UI.colors.muted; row.actions={}
   row.title.Position=UDim2.fromOffset(14,8); row.title.Size=UDim2.new(1,-28,0,38)
   row.body.Position=UDim2.fromOffset(14,48); row.body.Size=UDim2.new(1,-28,1,-110)
   for a=1,4 do local b,s=UI.button(row.frame,'',nil); row.actions[a]={button=b,state=s} end
   page.rows[i]=row
  end
  local index=first+i-1; local entry=page.items[index]; row.frame.Visible=entry~=nil
  if entry then
   row.frame.Position=UDim2.fromOffset(0,(index-1)*self.rowH); row.frame.Size=UDim2.new(1,-8,0,self.rowH-10)
   row.title.Text=entry.title or ''; row.title.TextSize=math.floor(18*self.textScale); row.body.Text=entry.body or ''; row.body.TextSize=math.floor(14*self.textScale)
   row.frame.BackgroundColor3=entry.highlight and UI.colors.card or UI.colors.panel
   local actions=entry.actions or {}; local n=math.max(1,math.min(4,#actions))
   for a,slot in ipairs(row.actions) do
    local action=actions[a]; slot.button.Visible=action~=nil
    if action then
     slot.button.Text=action.label; slot.button.Position=UDim2.new((a-1)/n,7,1,-53); slot.button.Size=UDim2.new(1/n,-14,0,46)
     slot.button.TextSize=math.floor((self.mobile and 12 or 14)*self.textScale); slot.button.BackgroundColor3=action.primary and UI.colors.lime or UI.colors.card
     slot.button.TextColor3=action.primary and UI.colors.bg or (action.danger and UI.colors.red or UI.colors.text)
     slot.state.enabled=action.enabled~=false; slot.button.AutoButtonColor=slot.state.enabled; slot.button.TextTransparency=slot.state.enabled and 0 or .5
     slot.state.callback=action.callback
    end
   end
  end
 end
 for i=visible+1,#page.rows do page.rows[i].frame.Visible=false end
end
function UI:update(profile)
 self.profile=profile;for _,n in ipairs(self.nav)do n.button.Text=self.tr:t('ui.'..n.id)end;self.search.PlaceholderText=self.tr:t('ui.search'); self.textScale=math.max(.9,math.min(1.35,profile.settings and profile.settings.textScale or 1)); self:open(self.current)
end
function UI:message(text)
 self.toastText.Text=text; self.toast.Visible=true; self.toastToken=(self.toastToken or 0)+1; local token=self.toastToken
 task.delay(5,function() if not self.dead and self.toastToken==token then self.toast.Visible=false end end)
end
function UI:modal(title,body,actions)
 if self.modalFrame then self.modalFrame:Destroy() end
 local veil=UI.make('Frame',{Name='Dialog',Size=UDim2.fromScale(1,1),BackgroundColor3=UI.colors.bg,BackgroundTransparency=.15,Active=true,ZIndex=50},self.gui); self.modalFrame=veil
 local width=math.min(610,self.width-24); local panel=UI.round(UI.frame(veil,'Panel',UI.colors.panel)); panel.AnchorPoint=Vector2.new(.5,.5); panel.Position=UDim2.fromScale(.5,.5); panel.Size=UDim2.fromOffset(width,math.min(520,self.height-30)); panel.ZIndex=51
 local heading=UI.label(panel,title,23,true); heading.Position=UDim2.fromOffset(20,12); heading.Size=UDim2.new(1,-40,0,56); heading.ZIndex=52
 local bodyFrame=UI.make('ScrollingFrame',{Name='DialogBody',Position=UDim2.fromOffset(20,76),Size=UDim2.new(1,-40,1,-210),BackgroundTransparency=1,BorderSizePixel=0,ScrollBarThickness=4,CanvasSize=UDim2.fromOffset(0,0),AutomaticCanvasSize=Enum.AutomaticSize.Y,ZIndex=52},panel)
 local text=UI.label(bodyFrame,body,16,false);text.Size=UDim2.new(1,-8,0,0);text.AutomaticSize=Enum.AutomaticSize.Y;text.TextYAlignment=Enum.TextYAlignment.Top;text.ZIndex=52
 local count=math.min(4,#actions)
 for i=1,count do
  local action=actions[i]; local b=UI.button(panel,action.label,function() veil:Destroy(); self.modalFrame=nil;self:clearSelection(); if action.callback then action.callback() end;if not self.modalFrame then self:selectDefault()end end,action.primary)
  local col=(i-1)%2; local row=math.floor((i-1)/2); b.Position=UDim2.new(col/2,12,1,-122+row*58); b.Size=UDim2.new(.5,-24,0,50); b.ZIndex=53;if i==1 then pcall(function()game:GetService('GuiService').SelectedObject=b end)end
 end
 return veil
end
function UI:destroy()
 self.dead=true; for _,c in ipairs(self.connections) do c:Disconnect() end; self.gui:Destroy()
end
return UI
