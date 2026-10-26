-- Input intentions only; movement, power and cooldowns are validated by the server.
local UI=require(script.Parent.UI)
local I={}
local defaults={pass='Space',shoot='F',through='E',switch='Q',tackle='R',sprint='LeftShift'}
I.defaults=defaults
local function keyName(input) local k=input.KeyCode; if type(k)=='string' then return k:match('%.([^%.]+)$') or k end; return k and k.Name end
function I.new(gui,view,tr,send)
 local UIS=game:GetService('UserInputService'); local self={uis=UIS,view=view,tr=tr,send=send,active=false,blocked=false,keys={},bindings={},connections={},move=Vector2.new(0,0),stick=Vector2.new(0,0),pad=Vector2.new(0,0),aim=0,sprint=false,lastSent=0,charge=nil,joystickTouch=nil,shootTouch=nil,dead=false}
 setmetatable(self,{__index=I}); self:setSettings({})
 self.root=UI.make('Frame',{Name='MatchControls',BackgroundTransparency=1,Size=UDim2.fromScale(1,1),Visible=false,ZIndex=20},gui)
 self.joystick=UI.round(UI.make('Frame',{Name='Movement',Size=UDim2.fromOffset(138,138),BackgroundColor3=UI.colors.panel,BackgroundTransparency=.2,Active=true},self.root),100)
 self.knob=UI.round(UI.make('Frame',{Size=UDim2.fromOffset(54,54),Position=UDim2.new(.5,-27,.5,-27),BackgroundColor3=UI.colors.muted,BackgroundTransparency=.15},self.joystick),100)
 self.actions={}
 for index,action in ipairs({'pass','shoot','through','switch','tackle','sprint'}) do
  local b=UI.button(self.root,tr:t('ui.'..action),nil,action=='shoot'); b.Name=action; self.actions[action]=b
  if action=='shoot' then
   self.connections[#self.connections+1]=b.InputBegan:Connect(function(input) if self:touch(input) and self:canControl() then self.shootTouch=input; self.charge=os.clock() end end)
   self.connections[#self.connections+1]=b.InputEnded:Connect(function(input) if input==self.shootTouch then self:shoot(); self.shootTouch=nil end end)
  elseif action=='sprint' then
   self.connections[#self.connections+1]=b.InputBegan:Connect(function(input) if self:touch(input) and self:canControl() then self:setSprint(true); self.sprintTouch=input end end)
   self.connections[#self.connections+1]=b.InputEnded:Connect(function(input) if input==self.sprintTouch then self:setSprint(false); self.sprintTouch=nil end end)
  else
   self.connections[#self.connections+1]=b.Activated:Connect(function() if self:canControl() then self.send('control',{action=action}) end end)
  end
 end
 self.hint=UI.label(self.root,'',13,false); self.hint.TextColor3=UI.colors.muted; self.hint.TextXAlignment=Enum.TextXAlignment.Center
 self.connections[#self.connections+1]=self.joystick.InputBegan:Connect(function(input) if self:touch(input) and self:canControl() and not self.joystickTouch then self.joystickTouch=input; self:updateTouch(input) end end)
 self.connections[#self.connections+1]=UIS.InputBegan:Connect(function(input,processed) self:began(input,processed) end)
 self.connections[#self.connections+1]=UIS.InputChanged:Connect(function(input,processed)
  if input==self.joystickTouch then self:updateTouch(input) end
  local key=keyName(input)
  if key=='Thumbstick1' and not processed then self.pad=Vector2.new(input.Position.X,-input.Position.Y) end
  if key=='Thumbstick2' and not processed then self.aim=-input.Position.Y end
 end)
 self.connections[#self.connections+1]=UIS.InputEnded:Connect(function(input) self:ended(input) end)
 self.connections[#self.connections+1]=UIS.WindowFocusReleased:Connect(function() self:reset() end)
 self.connections[#self.connections+1]=UIS.TextBoxFocused:Connect(function() self:reset() end)
 self.connections[#self.connections+1]=workspace.CurrentCamera:GetPropertyChangedSignal('ViewportSize'):Connect(function() self:resize() end)
 self:resize(); return self
end
function I:touch(input) return input.UserInputType==Enum.UserInputType.Touch or input.UserInputType==Enum.UserInputType.MouseButton1 end
function I:setSettings(settings)
 self.settings=settings;for action,button in pairs(self.actions or {})do button.Text=self.tr:t('ui.'..action)end; for action,key in pairs(defaults) do self.bindings[action]=(settings.bindings or {})[action] or key end
end
function I:canControl()
 return self.active and not self.view.replay and not self.blocked and not self.uis:GetFocusedTextBox() and (not self.view.latest or self.view.latest.phase~='penalties' and self.view.latest.interactive~=false)
end
function I:resize()
 local v=workspace.CurrentCamera.ViewportSize; self.joystick.Position=UDim2.new(0,16,1,-214)
 local touch=self.uis.TouchEnabled; self.joystick.Visible=touch
 local index=0
 for _,action in ipairs({'pass','shoot','through','switch','tackle','sprint'}) do
  local b=self.actions[action]; local col=index%3; local row=math.floor(index/3)
  b.Visible=touch; b.Position=UDim2.new(1,-(3-col)*63-10,1,-190+row*62); b.Size=UDim2.fromOffset(58,54); b.TextSize=11; index=index+1
 end
 self.hint.Position=UDim2.new(.5,-math.min(310,v.X/2),1,-84); self.hint.Size=UDim2.fromOffset(math.min(620,v.X),24)
 local parts={}; for _,a in ipairs({'pass','shoot','through','switch','tackle','sprint'}) do parts[#parts+1]=self.tr:t('ui.'..a)..' ['..self.bindings[a]..']' end
 self.hint.Text=touch and '' or table.concat(parts,'  ·  ')
end
function I:updateTouch(input)
 local center=self.joystick.AbsolutePosition+self.joystick.AbsoluteSize/2; local delta=Vector2.new(input.Position.X,input.Position.Y)-center
 local len=delta.Magnitude; if len>48 then delta=delta/len*48 end
 self.stick=delta/48; self.knob.Position=UDim2.new(.5,delta.X-27,.5,delta.Y-27)
end
function I:setSprint(enabled)
 if self.sprint==enabled then return end; self.sprint=enabled
 if self.active then self.send('control',{action='sprint',enabled=enabled}) end
end
function I:began(input,processed)
 local key=keyName(input)
 if self.remapping and not processed and input.UserInputType==Enum.UserInputType.Keyboard then
  local callback=self.remapping; self.remapping=nil; callback(key); return
 end
 if processed or not self:canControl() then return end
 self.keys[key]=true
 local pads={ButtonA='pass',ButtonX='through',ButtonB='shoot',ButtonY='switch',ButtonR1='tackle',ButtonR2='sprint'}
 local action=pads[key]; for a,k in pairs(self.bindings) do if k==key then action=a; break end end
 if action=='shoot' then self.charge=os.clock()
 elseif action=='sprint' then self:setSprint(true)
 elseif action then self.send('control',{action=action}) end
end
function I:ended(input)
 local key=keyName(input); self.keys[key]=nil
 if input==self.joystickTouch then self.joystickTouch=nil; self.stick=Vector2.new(0,0); self.knob.Position=UDim2.new(.5,-27,.5,-27) end
 if input==self.shootTouch then self:shoot(); self.shootTouch=nil end
 if input==self.sprintTouch or key==self.bindings.sprint or key=='ButtonR2' then self:setSprint(false); self.sprintTouch=nil end
 if key==self.bindings.shoot or key=='ButtonB' then self:shoot() end
end
function I:shoot()
 if not self.charge then return end
 local duration=os.clock()-self.charge; self.charge=nil
 if not self:canControl() then return end
 local y=32+self.aim*11
 if not self.uis.TouchEnabled and self.uis.MouseEnabled then
  local mouse=self.uis:GetMouseLocation(); local pos,size=self.view.pitch.AbsolutePosition,self.view.pitch.AbsoluteSize
  if size.Y>0 then y=math.max(0,math.min(64,(mouse.Y-pos.Y)/size.Y*64)) end
 end
 self.send('control',{action='shoot',y=y,power=math.max(.25,math.min(1,.35+duration*.9))})
 if self.settings.haptics then pcall(function() game:GetService('HapticService'):SetMotor(Enum.UserInputType.Gamepad1,Enum.VibrationMotor.Small,.2); task.delay(.08,function() pcall(function() game:GetService('HapticService'):SetMotor(Enum.UserInputType.Gamepad1,Enum.VibrationMotor.Small,0) end) end) end) end
end
function I:step()
 if not self:canControl() then return end
 local x,y=self.stick.X+self.pad.X,self.stick.Y+self.pad.Y
 if self.keys.W or self.keys.Up then y=y-1 end; if self.keys.S or self.keys.Down then y=y+1 end
 if self.keys.A or self.keys.Left then x=x-1 end; if self.keys.D or self.keys.Right then x=x+1 end
 local length=math.sqrt(x*x+y*y); if length>1 then x,y=x/length,y/length end
 if os.clock()-self.lastSent>=.08 then self.lastSent=os.clock(); self.send('input',{x=x,y=y}) end
end
function I:setActive(active)
 self.active=active; self.root.Visible=active; self:reset(); self:resize()
end
function I:setBlocked(blocked) self.blocked=blocked; if blocked then self:reset() end end
function I:reset()
 self.keys={}; self.stick=Vector2.new(0,0); self.pad=Vector2.new(0,0); self.charge=nil; self.joystickTouch=nil; self.shootTouch=nil
 if self.active then self.send('input',{x=0,y=0}) end; self:setSprint(false); self.knob.Position=UDim2.new(.5,-27,.5,-27)
end
function I:remap(callback) self.remapping=callback; self:reset() end
function I:destroy() self.dead=true; self:reset(); for _,c in ipairs(self.connections) do c:Disconnect() end; self.root:Destroy() end
return I
