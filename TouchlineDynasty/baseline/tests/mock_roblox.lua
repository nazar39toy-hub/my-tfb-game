-- Minimal UI test double. This does not emulate Roblox rendering or networking.
local function signal()
 local s={listeners={}}
 function s:Connect(fn) table.insert(self.listeners,fn); return {Disconnect=function() end} end
 function s:Fire(...) for _,fn in ipairs(self.listeners) do fn(...) end end
 return s
end
Objects={}
local meta={}
meta.__index=function(t,k)
 if k=='GetPropertyChangedSignal' then return function() return signal() end end
 if k=='WaitForChild' or k=='FindFirstChild' then return function(self,name) for _,child in ipairs(self.children) do if child.Name==name then return child end end; return nil end end
 if k=='ClearAllChildren' then return function(self) for _,c in ipairs(self.children) do c.destroyed=true end; self.children={} end end
 if k=='Destroy' then return function(self) self.destroyed=true end end
 if k=='FireServer' then return function(self,action,arg) self.lastAction=action; self.lastArg=arg end end
 return rawget(t,'props')[k]
end
meta.__newindex=function(t,k,v)
 if k=='Parent' and v then table.insert(v.children,t) end
 rawget(t,'props')[k]=v
end
Instance={new=function(class)
 local t=setmetatable({props={},children={}},meta)
 t.ClassName=class; t.Name=class
 for _,name in ipairs({'Activated','InputBegan','InputChanged','InputEnded','OnClientEvent'}) do t[name]=signal() end
 table.insert(Objects,t); return t
end}
Enum=setmetatable({}, {__index=function(t,k)
 local category=setmetatable({}, {__index=function(tt,kk) rawset(tt,kk,k..'.'..kk); return k..'.'..kk end}); rawset(t,k,category); return category
end})
Color3={fromRGB=function(r,g,b) return {R=r/255,G=g/255,B=b/255} end,new=function(r,g,b) return {R=r,G=g,B=b} end}
UDim={new=function(s,o) return {Scale=s,Offset=o} end}
UDim2={new=function(a,b,c,d) return {X=UDim.new(a,b),Y=UDim.new(c,d)} end}
UDim2.fromOffset=function(x,y) return UDim2.new(0,x,0,y) end
UDim2.fromScale=function(x,y) return UDim2.new(x,0,y,0) end
local vm={}
vm.__index=function(v,k)
 if k=='Magnitude' then return math.sqrt(v.X*v.X+v.Y*v.Y) end
 if k=='Unit' then local d=math.sqrt(v.X*v.X+v.Y*v.Y); return Vector2.new(v.X/d,v.Y/d) end
 if k=='Lerp' then return function(a,b,t) return Vector2.new(a.X+(b.X-a.X)*t,a.Y+(b.Y-a.Y)*t) end end
end
vm.__add=function(a,b) return Vector2.new(a.X+b.X,a.Y+b.Y) end
vm.__sub=function(a,b) return Vector2.new(a.X-b.X,a.Y-b.Y) end
vm.__div=function(a,b) return Vector2.new(a.X/b,a.Y/b) end
vm.__mul=function(a,b) return Vector2.new(a.X*b,a.Y*b) end
Vector2={new=function(x,y) return setmetatable({X=x,Y=y},vm) end}
Vector3={new=function(x,y,z) return {X=x,Y=y,Z=z} end}
CFrame={new=function() return {} end}
math.clamp=function(v,a,b) return math.max(a,math.min(b,v)) end
workspace={CurrentCamera=Instance.new('Camera')}; workspace.CurrentCamera.ViewportSize=Vector2.new(1280,800)
local player=Instance.new('Player'); player.UserId=9
local pg=Instance.new('Folder'); pg.Name='PlayerGui'; pg.Parent=player
local ps=Instance.new('Folder'); ps.Name='PlayerScripts'; ps.Parent=player; player.PlayerScripts=ps
local pm=Instance.new('ModuleScript'); pm.Name='PlayerModule'; pm.Parent=ps
local rs=Instance.new('Folder'); local net=Instance.new('Folder'); net.Name='TouchlineNet'; net.Parent=rs
RemoteEvent=Instance.new('RemoteEvent'); RemoteEvent.Name='Event'; RemoteEvent.Parent=net
Command=Instance.new('RemoteEvent'); Command.Name='Command'; Command.Parent=net
Input={TouchEnabled=false,InputBegan=signal(),InputChanged=signal(),InputEnded=signal(),GetMouseLocation=function() return Vector2.new(1000,410) end}
Run={RenderStepped=signal()}
local services={Players={LocalPlayer=player},ReplicatedStorage=rs,UserInputService=Input,RunService=Run,TweenService={}}
game={GetService=function(_,name) return services[name] end}
task={delay=function() end,spawn=function() end,wait=function() end}
require=function() return {GetControls=function() return {Disable=function() end} end} end
function isAlive(obj)
 while obj do if obj.destroyed then return false end; obj=obj.Parent end; return true
end
function click(text)
 for i=#Objects,1,-1 do local obj=Objects[i]; if isAlive(obj) and obj.ClassName=='TextButton' and obj.Text==text then obj.Activated:Fire(); return true end end
 error('button not found: '..text)
end
