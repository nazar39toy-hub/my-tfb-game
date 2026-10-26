-- Explicit Studio CLIENT measurement. Never enabled in a published client.
local D={}
function D.run(seconds,options)
 local Run=game:GetService('RunService');assert(Run:IsStudio()and Run:IsClient(),'Use the CLIENT Command Bar during Studio Play')
 options=options or {};seconds=math.max(10,math.min(1800,tonumber(seconds)or 60));local warmup=5
 local Stats=game:GetService('Stats');local Input=game:GetService('UserInputService');local player=game:GetService('Players').LocalPlayer
 local gui=player:WaitForChild('PlayerGui');local function memory()local ok,n=pcall(function()return Stats:GetTotalMemoryUsageMb()end);return ok and n or nil end
 local function traffic(name)local ok,n=pcall(function()return Stats.Network.ServerStatsItem[name]:GetValue()end);return ok and n or nil end
 local samples={};local start=os.clock();local active=false;local memoryBefore;local instancesBefore
 local connection=Run.RenderStepped:Connect(function(dt)if active then samples[#samples+1]=dt*1000 end end)
 while os.clock()-start<warmup do task.wait(.1)end
 memoryBefore=memory();instancesBefore=#gui:GetDescendants();local downloadBefore=traffic('Data Receive Kbps');active=true;start=os.clock()
 while os.clock()-start<seconds do task.wait(.1)end
 active=false;connection:Disconnect();table.sort(samples)
 local function percentile(p)if #samples==0 then return nil end;return samples[math.max(1,math.ceil(#samples*p))]end
 local view=workspace.CurrentCamera.ViewportSize
 local report={environment='Roblox Studio CLIENT',deviceLabel=options.deviceLabel or 'not supplied',viewport={x=view.X,y=view.Y},touch=Input.TouchEnabled,gamepad=Input.GamepadEnabled,warmupSeconds=warmup,elapsedSeconds=os.clock()-start,frames=#samples,frameP50Ms=percentile(.5),frameP95Ms=percentile(.95),memoryBeforeMb=memoryBefore,memoryAfterMb=memory(),playerGuiInstancesBefore=instancesBefore,playerGuiInstancesAfter=#gui:GetDescendants(),allTrafficReceiveKbpsBefore=downloadBefore,allTrafficReceiveKbpsAfter=traffic('Data Receive Kbps'),allTrafficSendKbpsAfter=traffic('Data Send Kbps')}
 print('TOUCHLINE_CLIENT_QA '..game:GetService('HttpService'):JSONEncode(report));return report
end
return D
