local Config=require(script.Parent.AudioConfig)
local Audio={}
function Audio.new(service)
 local self=setmetatable({sounds={},settings={},lastSeq=-1,lastOwner=nil,lastPhase=nil},{__index=Audio})
 for key,item in pairs(Config)do
  if type(item.id)=='number'and item.id>0 and item.id%1==0 then
   local s=Instance.new('Sound');s.Name='Touchline_'..key;s.SoundId='rbxassetid://'..item.id;s.Looped=item.looped==true;s.Volume=0;s.Parent=service;self.sounds[key]=s
  end
 end
 return self
end
function Audio:settingsChanged(settings)
 self.settings=settings or {};for key,sound in pairs(self.sounds)do local item=Config[key];local volume=tonumber(self.settings[item.category])or 0;sound.Volume=math.max(0,math.min(1,volume))*item.volume end
end
function Audio:play(key)
 local sound=self.sounds[key];if sound then pcall(function()sound.TimePosition=0;sound:Play()end)end
end
function Audio:match(active)
 for _,key in ipairs({'crowd','music'})do local sound=self.sounds[key];if sound then pcall(function()if active then sound:Play()else sound:Stop()end end)end end
 if not active then self.lastSeq=-1;self.lastOwner=nil;self.lastPhase=nil end
end
function Audio:snapshot(data)
 if type(data)~='table'or type(data.seq)~='number'or data.seq<=self.lastSeq then return end;self.lastSeq=data.seq
 if data.phase~=self.lastPhase and (data.phase=='kickoff'or data.phase=='halftime'or data.phase=='ended'or data.phase=='restart')then self:play('whistle')end
 if self.lastOwner and not data.owner and data.phase=='play'then self:play('kick')end
 self.lastOwner=data.owner;self.lastPhase=data.phase
end
function Audio:destroy()
 for _,sound in pairs(self.sounds)do sound:Destroy()end;self.sounds={}
end
return Audio
