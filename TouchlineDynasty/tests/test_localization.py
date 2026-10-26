"""Pure Lua/adapter-double checks. No claims about Studio glyph rendering."""
from pathlib import Path
import csv,json,re,subprocess,sys
from lupa import LuaRuntime
ROOT=Path(__file__).resolve().parents[1]
data=json.loads((ROOT/'localization/strings.json').read_text())
keys=set(data['en'])
assert len(keys)>=250
for locale in ('ru','uk'):
    assert set(data[locale])==keys,(locale,'key mismatch')
    for key in keys:
        assert set(re.findall(r'\{(\w+)\}',data[locale][key]))==set(re.findall(r'\{(\w+)\}',data['en'][key])),(locale,key,'parameters differ')
        assert data[locale][key].strip(),(locale,key)
# Static literal-key coverage for all delivered game modules. Dynamic families are
# covered by their explicit dictionaries and runtime smoke tests.
referenced=set()
for source in (ROOT/'src').glob('*.lua'):
    if source.name in ('Locales.lua','Localization.lua'): continue
    referenced.update(re.findall(r"['\"]((?:ui|match|shop|event|error|format|language|style|attribute|position|mentality|difficulty)\.[A-Za-z0-9_.-]+)['\"]",source.read_text()))
missing={key for key in referenced if key not in keys and not any(k.startswith(key+'.') for k in keys)}
assert not missing,('untranslated literal source keys',sorted(missing))
original=(ROOT/'src/Locales.lua').read_bytes()
subprocess.run([sys.executable,str(ROOT/'localization/build_locales.py')],check=True,capture_output=True)
assert (ROOT/'src/Locales.lua').read_bytes()==original,'locale generation not reproducible'
with (ROOT/'localization/Roblox_Cloud_Import.csv').open(encoding='utf-8-sig',newline='') as f:
    rows=list(csv.DictReader(f))
assert len(rows)==len(keys)
assert len({(r['Source'],r['Context']) for r in rows})==len(rows)
assert all(r['ru'] for r in rows)
assert all(all(not r[lang] for lang in ('es','pt-br','pl','de','fr','tr','ja','ko')) for r in rows),'unverified cloud translations must stay empty'
lua=LuaRuntime(unpack_returned_tuples=True)
lua.globals().DICT=lua.execute((ROOT/'src/Locales.lua').read_text())
lua.execute("script={Parent={Locales='Locales'}}; require=function() return DICT end")
lua.globals().L=lua.execute((ROOT/'src/Localization.lua').read_text())
lua.execute('''
assert(L.resolve('auto','ru-ru')=='ru')
assert(L.resolve('auto','uk-UA')=='uk')
assert(L.resolve('auto','pt-BR')=='pt-br')
assert(L.resolve('auto','ja-jp')=='ja')
assert(L.resolve('auto','ar-001')=='en') -- RTL is deliberately not advertised.
assert(L.resolve('en','ru-ru')=='en')
assert(L.resolve('qps-ploc','en-us')=='qps-ploc')
local en=L.new({locale='en',robloxLocale='ru'})
local ru=L.new({locale='ru'}); local uk=L.new({locale='uk'})
assert(en:t('ui.play')=='Play match')
assert(ru:t('ui.play')=='Играть матч')
assert(uk:t('ui.play')=='Грати матч')
DICT.uk['ui.play']=nil; assert(uk:t('ui.play')=='Play match'); DICT.uk['ui.play']='Грати матч'
assert(uk:t('format.fixture',{home='Клуб А',away='Team B'})=='Клуб А — Team B')
assert(en:t('format.fixture',{home='A'})=='A vs —')
assert(en:t('missing.key')=='[missing.key]' and en.missing['missing.key'])
assert(en:event('Старая русская история')=='Старая русская история')
assert(en:event({legacy='Legacy result 2:1'})=='Legacy result 2:1')
assert(ru:event({key='format.date',params={season=3,day=10}})=='Сезон 3, день 10')
assert(L.plural('ru',1)=='one' and L.plural('ru',2)=='few' and L.plural('ru',5)=='many')
assert(L.plural('pl',22)=='few' and L.plural('pl',12)=='many' and L.plural('pl',21)=='many')
assert(L.plural('ja',1)=='other' and L.plural('fr',0)=='one')
assert(L.plural('uk',11)=='many' and L.plural('uk',21)=='one' and L.plural('uk',24)=='few')
assert(en:t('format.players',{count=1})=='1 player')
assert(en:t('format.players',{count=3})=='3 players')
assert(ru:t('format.players',{count=2})=='2 игрока')
assert(uk:t('format.players',{count=5})=='5 гравців')
assert(en:number(1234567)=='1,234,567')
assert(ru:number(1234567)=='1 234 567')
assert(ru:number(12.5,1)=='12,5')
assert(en:number(0/0)=='—' and en:number(math.huge)=='—')
assert(en:money(1234)=='1,234 cr')
assert(en:setLocale('uk')=='uk' and en:t('ui.help')=='Допомога')
local q=L.new({locale='qps-ploc'})
for key,value in pairs(DICT.en) do
 local n=utf8.len(value)
 if n>=10 then local ratio=utf8.len(L.pseudo(value))/n; assert(ratio>=1.4 and ratio<=1.6,key) end
 local out=q:t(key,{home='A',away='B',season=30,day=60,count=2})
 assert(type(out)=='string' and #out>0)
end
-- CJK codepoints survive interpolation, fallback and event formatting.
assert(en:t('format.fixture',{home='日本語',away='한국어'})=='日本語 vs 한국어')
-- Simulate asynchronous API success, error, timeout and stale request completion.
spawned={}; delayed={}
task={spawn=function(fn) spawned[#spawned+1]=fn end,delay=function(_,fn) delayed[#delayed+1]=fn end}
local called=0; local service={GetTranslatorForLocaleAsync=function(_,locale)
 return {FormatByKey=function(_,key,args) return 'cloud '..locale..' '..key end}
end}
local es=L.new({locale='es'}); assert(es:t('ui.play')=='Play match')
es:attachRoblox(nil,nil,function() called=called+1 end,service)
assert(es:t('ui.play')=='Play match'); spawned[1]()
assert(es:t('ui.play')=='cloud es ui.play' and called==1)
local ja=L.new({locale='ja'}); ja:attachRoblox(nil,nil,nil,service)
delayed[#delayed](); spawned[#spawned]()
assert(ja:t('ui.play')=='Play match','late translator must not replace fallback')
local ko=L.new({locale='ko'}); ko:attachRoblox(nil,nil,nil,{GetTranslatorForLocaleAsync=function() error('outage') end}); spawned[#spawned]()
assert(ko:t('ui.play')=='Play match')
local tr=L.new({locale='tr'}); tr:attachRoblox(nil,nil,nil,service)
local first=#spawned; tr:setLocale('fr'); local second=#spawned
spawned[first](); assert(tr.translator==nil)
spawned[second](); assert(tr:t('ui.play')=='cloud fr ui.play')
tr:destroy(); assert(tr.translator==nil and tr.service==nil)
assert(#L.entries()>250)
''')
print(f'PASS localization: {len(keys)} EN/RU/UK keys; parameter parity; locale/fallback; plural/number/date; +50% pseudo; cloud timeout/stale/error adapter; deterministic exports')
print('NOT RUN: Studio CJK glyph/wrapping, physical-device layout, real cloud table lookup and Dashboard configuration')
