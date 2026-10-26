-- Result navigation reuses stored statistics; it never replays a simulation.
local R={}
function R.show(ui,tr,data,profile,onContinue)
 local function open()
  local s=data.stats or {};local teams=s.teams;local body=tostring(data.home)..' : '..tostring(data.away)..'  '..tostring(data.op)..'\n'..tr:t('ui.income')..' '..tr:money(data.income or 0)..' · '..tr:t('ui.expenses')..' '..tr:money(data.costs or 0)..'\n'..tr:t('ui.net')..' '..tr:money(data.net or 0)
  if teams then for _,field in ipairs({'shots','onTarget','passAccuracy','possessionPercent','yellow','red'})do body=body..'\n'..tr:t('report.'..field)..': '..tostring(teams[1][field]or 0)..' : '..tostring(teams[2][field]or 0)end end
  if s.playerOfMatch then body=body..'\n'..tr:t('ui.playerOfMatch')..': '..s.playerOfMatch.name..' ('..s.playerOfMatch.rating..')'end
  if data.training then body=body..'\n'..tr:t(data.training.success and 'training.success' or 'training.ended')..' · '..tr:t('ui.tokens')..' +'..tostring(data.cosmeticReward or 0)end
  if s.shootout then body=body..'\n'..tr:t('report.shootout',{home=s.shootout.scores[1],away=s.shootout.scores[2]})end
  if data.technical then body=body..'\n'..tr:t('report.technical')elseif data.forfeit then body=body..'\n'..tr:t('match.forfeit')end
  local actions={{label=tr:t('ui.continue'),callback=onContinue}}
  if teams then
   actions[#actions+1]={label=tr:t('report.ratings'),callback=function()
    local lines={};for _,q in ipairs(profile and profile.roster or {})do if s.ratings and s.ratings[q.id]then lines[#lines+1]=q.name..' · '..tostring(s.ratings[q.id])end end
    ui:modal(tr:t('report.ratings'),table.concat(lines,'\n'),{{label=tr:t('report.back'),callback=open}})
   end}
   actions[#actions+1]={label=tr:t('report.factors'),callback=function()
    local lines={tr:t(data.neutral and 'report.neutral'or data.venueHome and 'report.home' or 'report.away'),tr:t('difficulty.'..((profile or {}).difficulty or 'normal')),tr:t('style.'..((profile or {}).style or 'counter'))}
    if teams[1].red>0 then lines[#lines+1]=tr:t('report.dismissal')end
    lines[#lines+1]=tr:t(teams[1].onTarget>=teams[2].onTarget and 'report.moreShots' or 'report.fewerShots')
    ui:modal(tr:t('report.factors'),table.concat(lines,'\n'),{{label=tr:t('report.back'),callback=open}})
   end}
  end
  ui:modal(tr:t('ui.result'),body,actions)
 end
 open()
end
return R
