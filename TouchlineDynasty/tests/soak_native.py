"""Accelerated 30 game-minute heap check; not a real-time Roblox soak."""
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
exec((ROOT/'tests/native_check.py').read_text().split('results=[]')[0])
run(r'''
local C=require('Career');local M=require('Match');local matches={};local profiles={};local samples={}
for i=1,12 do profiles[i]=C.new(i+5000);local p=profiles[i];matches[i]=M.new(p,C.next(p),C,i);M.setMode(matches[i],'simulate')end
for tick=1,36000 do
 for i,m in ipairs(matches)do
  if m.ended then local p=profiles[i];matches[i]=M.new(p,C.next(p),C,i);M.setMode(matches[i],'simulate')else M.step(m,.05)end
 end
 if tick%1200==0 then collectgarbage('collect');samples[#samples+1]={seconds=tick*.05,kib=collectgarbage('count')}end
end
local f=assert(io.open('SOAK_NATIVE.json','w'));f:write('{"environment":"system Lua 5.4; accelerated; no Roblox", "simulated_minutes":30,"matches":12,"samples":[')
for i,row in ipairs(samples)do if i>1 then f:write(',')end;f:write(string.format('{"seconds":%d,"lua_heap_kib":%.3f}',row.seconds,row.kib))end
f:write(']}');f:close()
''')
