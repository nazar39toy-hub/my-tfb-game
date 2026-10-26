local DataStoreService=game:GetService('DataStoreService')
local RunService=game:GetService('RunService')
local HttpService=game:GetService('HttpService')
local S={sessions={}}
local dbOK,db=pcall(function() return DataStoreService:GetDataStore('TouchlineDynasty_v1') end)
if not dbOK then db=nil end
local token=game.JobId~='' and game.JobId or HttpService:GenerateGUID(false)
local function retry(fn)
 local ok,res
 for i=1,3 do ok,res=pcall(fn); if ok then return true,res end; task.wait(i) end
 return false,res
end
function S.load(player,make)
 local key='u'..player.UserId
 if not db then
  if RunService:IsStudio() then S.sessions[player]={key=key,temporary=true,busy=false}; return make(),'ТЕСТ: опубликуй игру для сохранений' end
  return nil,'Хранилище временно недоступно. Попробуй позже.'
 end
 local ok,envelope=retry(function()
  return db:UpdateAsync(key,function(old)
   if old and old.lock and old.lock~=token and (old.expires or 0)>os.time() then return nil end
   return {profile=old and old.profile or make(),lock=token,expires=os.time()+180}
  end)
 end)
 if not ok then
  if RunService:IsStudio() then
   local p=make(); S.sessions[player]={key=key,temporary=true,busy=false}; return p,'ТЕСТ: сохранения недоступны'
  end
  return nil,'Не удалось загрузить карьеру. Зайди позже — данные не перезаписаны.'
 end
 if not envelope then return nil,'Карьера открыта на другом сервере. Подожди до 3 минут.' end
 if type(envelope.profile)~='table' or envelope.profile.version~=1 then return nil,'Версия сохранения не поддерживается.' end
 S.sessions[player]={key=key,busy=false,temporary=false}
 return envelope.profile,'Сохранения подключены'
end
function S.save(player,profile,copy,release)
 local session=S.sessions[player]; if not session then return false,'Нет сессии' end
 if session.temporary then if release then S.sessions[player]=nil end; return true,'Тестовая сессия' end
 local start=os.clock()
 while session.busy and os.clock()-start<15 do task.wait(.1) end
 if session.busy then return false,'Сохранение занято' end
 session.busy=true
 local snapshot=copy(profile)
 local ok,res=retry(function()
  return db:UpdateAsync(session.key,function(old)
   if not old or old.lock~=token then return nil end
   return {profile=snapshot,lock=not release and token or nil,expires=not release and os.time()+180 or 0}
  end)
 end)
 session.busy=false
 if release then S.sessions[player]=nil end
 if not ok then return false,'Сбой сохранения — повторим автоматически' end
 if not res then return false,'LOCK_LOST' end
 return true,'Сохранено'
end
return S
