-- Categories never mix difficulty or control modes. Optional global adapter.
local R={}
local modes={manual=true,highlights=true,simulate=true}
local difficulty={easy=true,normal=true,hard=true}
function R.category(mode,level)
 if not modes[mode] or not difficulty[level] then return nil end
 return mode..'_'..level
end
function R.record(p,result)
 if result.training or result.forfeit then return end
 local key=R.category(result.mode,p.difficulty);if not key then return end
 p.records.categories=p.records.categories or {};local row=p.records.categories[key] or {played=0,wins=0,points=0};p.records.categories[key]=row
 row.played=row.played+1
 local win=result.home>result.away or result.penWin==true
 if win then row.wins=row.wins+1;row.points=row.points+3 elseif result.home==result.away then row.points=row.points+1 end
end
function R.adapter(service,isStudio,clock)
 clock=clock or os.clock
 local lastWrite,lastRead,cache={},{},{}
 local prefix=isStudio and 'TD_TEST_records_v2_' or 'TD_records_v2_'
 local adapter={}
 function adapter.publish(userId,key,points)
  if type(key)~='string' then return false,'INVALID_RECORD' end
  if not R.category(key:match('^(.*)_'),key:match('_([^_]+)$')) or type(userId)~='number' or userId%1~=0 or type(points)~='number' or points~=points or points<0 or points>1000000 or points%1~=0 then return false,'INVALID_RECORD' end
  local token=userId..':'..key;if lastWrite[token] and clock()-lastWrite[token]<120 then return false,'RECORD_COOLDOWN' end
  lastWrite[token]=clock()
  local ok=pcall(function() service:GetOrderedDataStore(prefix..key):UpdateAsync(tostring(userId),function(old)return math.max(type(old)=='number' and old or 0,points)end)end)
  if not ok then lastWrite[token]=nil end
  return ok,ok and 'SAVED' or 'STORE_UNAVAILABLE'
 end
 function adapter.read(mode,level)
  local key=R.category(mode,level);if not key then return nil,'INVALID_RECORD' end
  if lastRead[key] and clock()-lastRead[key]<60 then return cache[key] or {},'CACHED' end
  lastRead[key]=clock()
  local ok,rows=pcall(function()return service:GetOrderedDataStore(prefix..key):GetSortedAsync(false,10):GetCurrentPage()end)
  if not ok then lastRead[key]=nil;return nil,'STORE_UNAVAILABLE' end
  local out={};for _,row in ipairs(rows)do if type(row.value)=='number' and row.value>=0 and row.value<=1000000 then out[#out+1]={userId=tostring(row.key),points=row.value}end end
  cache[key]=out;return out,'SAVED'
 end
 function adapter.clear(userId)for key in pairs(lastWrite)do if key:sub(1,#tostring(userId)+1)==tostring(userId)..':'then lastWrite[key]=nil end end end
 return adapter
end
return R
