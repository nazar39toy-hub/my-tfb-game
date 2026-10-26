from pathlib import Path
from lupa import LuaRuntime
ROOT=Path(__file__).resolve().parents[1]
lua=LuaRuntime(unpack_returned_tuples=True)
C=lua.execute((ROOT/'src/Career.lua').read_text()); M=lua.execute((ROOT/'src/Match.lua').read_text())
lua.globals().C=C; lua.globals().M=M
lua.execute((ROOT/'tests/mock_roblox.lua').read_text())
lua.execute((ROOT/'src/Client.client.lua').read_text())
lua.execute('''
p=C.new(9); p.strength=55; p.table=C.sorted(p); p.next=C.next(p,'league'); p.saveStatus='TEST'
RemoteEvent.OnClientEvent:Fire('profile',p)
for _,tab in ipairs({'Клуб','Состав','Трансферы','Развитие','Лига','Карьера','Помощь'}) do assert(click(tab)) end
click('Состав'); click('Заменить'); click('Поставить'); assert(Command.lastAction=='swap')
click('Клуб'); click('ИГРАТЬ МАТЧ'); assert(Command.lastAction=='play')
local m=M.new(p,C.next(p,'league'),C,9)
RemoteEvent.OnClientEvent:Fire('matchStart',M.snapshot(m))
Run.RenderStepped:Fire(.016)
RemoteEvent.OnClientEvent:Fire('snapshot',M.snapshot(m))
Run.RenderStepped:Fire(.09)
assert(Command.lastAction=='input')
RemoteEvent.OnClientEvent:Fire('result',{home=2,away=1,op='Test FC',income=50000})
click('Дальше'); click('Клуб')
''')
print('PASS client smoke: all 7 pages, lineup button, kickoff, snapshots, RenderStepped, result modal')
# Save mock dashboard geometry for internal visual QA (not a Studio screenshot).
import json
def convert(v):
    if isinstance(v,(str,int,float,bool)) or v is None: return v
    try: return {str(k):convert(val) for k,val in v.items()}
    except Exception: return None
nodes=[]
objects=lua.globals().Objects
index={}
for i in range(1,len(objects)+1):
    o=objects[i]
    if lua.globals().isAlive(o):
        # A numeric handle avoids Python wrapper identity issues.
        o['testHandle']=i
for i in range(1,len(objects)+1):
    o=objects[i]
    if lua.globals().isAlive(o):
        props=o['props']; parent=props['Parent']
        node={'id':i,'parent':parent['testHandle'] if parent else None,'class':props['ClassName']}
        for k in ['Name','Text','Position','Size','BackgroundColor3','BackgroundTransparency','TextColor3','TextSize','Visible','AnchorPoint','ZIndex','TextXAlignment']:
            val=props[k]
            if val is not None: node[k]=convert(val)
        nodes.append(node)
(ROOT/'tests/ui_mock.json').write_text(json.dumps(nodes,ensure_ascii=False))
