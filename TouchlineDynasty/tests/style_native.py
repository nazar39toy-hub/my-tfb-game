from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
exec((ROOT/'tests/native_check.py').read_text().split('results=[]')[0])
run(r'''
local C=require('Career');local M=require('Match');local f=assert(io.open('STYLE_RAW.csv','w'));f:write('style,opponent,seed,home,goals_for,goals_against\n')
for _,style in ipairs(C.styles)do for _,opponent in ipairs(C.styles)do for seed=1,20 do
 local p=C.new(7000+seed);p.style=style;p.chemistry=0;for _,q in ipairs(p.roster)do for key in pairs(q.attributes)do q.attributes[key]=70 end;q.keeping={handling=70,reflexes=70,positioning=70};q.rating=70;q.fitness=100;q.form=100;q.morale=100 end
 C.action(p,'autoLineup',{});local op={name='Benchmark',rating=C.strength(p),home=seed%2==0,kind='league',style=opponent};local m=M.simulate(p,op,C,seed)
 f:write(string.format('%s,%s,%d,%s,%d,%d\n',style,opponent,seed,tostring(op.home),m.home,m.away))
end end end;f:close()
''')
