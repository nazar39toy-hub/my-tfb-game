from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
exec((ROOT/'tests/native_check.py').read_text().split('results=[]')[0])
run(r'''
local C=require('Career');local M=require('Match');local matches={};local timings={};collectgarbage('collect');local memoryBefore=collectgarbage('count');local loadStart=os.clock()
for i=1,12 do local p=C.new(i+9100);local op=C.next(p);matches[i]=M.new(p,op,C,i+9100);M.setMode(matches[i],'simulate')end
local loadSeconds=os.clock()-loadStart
for tick=1,1000 do
 local start=os.clock();for _,m in ipairs(matches)do M.step(m,.05)end;timings[#timings+1]=(os.clock()-start)*1000
end
collectgarbage('collect');local memoryAfter=collectgarbage('count');table.sort(timings)
local f=assert(io.open('PERFORMANCE_NATIVE.json','w'));f:write(string.format('{"environment":"system Lua 5.4; no Roblox engine","matches":12,"ticks":1000,"simulated_seconds":50,"batch_step_p50_ms":%.6f,"batch_step_p95_ms":%.6f,"load_12_profiles_seconds":%.6f,"lua_heap_before_kib":%.3f,"lua_heap_after_kib":%.3f}',timings[500],timings[950],loadSeconds,memoryBefore,memoryAfter));f:close()
''')
