"""Deterministic source-to-place builder, no external assets required."""
from pathlib import Path
import xml.etree.ElementTree as E,zipfile,hashlib,json
ROOT=Path(__file__).resolve().parent
shared={'Diagnostics','Audio','AudioConfig','Results','UI','CareerScreens','MatchView','Input','Localization','Locales','MonetizationConfig'}
root=E.Element('roblox',version='4');E.SubElement(root,'External').text='null';E.SubElement(root,'External').text='nil'
count=0

def item(parent,cls,name,source=None):
 global count
 count+=1;n=E.SubElement(parent,'Item',{'class':cls,'referent':f'RBX{count}'})
 p=E.SubElement(n,'Properties');E.SubElement(p,'string',name='Name').text=name
 if source is not None:E.SubElement(p,'ProtectedString',name='Source').text=source
 return n

world=item(root,'Workspace','Workspace');camera=item(world,'Camera','Camera');E.SubElement(world.find('Properties'),'Ref',name='CurrentCamera').text=camera.attrib['referent'];rs=item(root,'ReplicatedStorage','ReplicatedStorage');sf=item(rs,'Folder','TouchlineShared')
ss=item(root,'ServerScriptService','ServerScriptService');server=item(ss,'Folder','TouchlineServer')
sp=item(root,'StarterPlayer','StarterPlayer');sps=item(sp,'StarterPlayerScripts','StarterPlayerScripts')
manifest=[]
for f in sorted((ROOT/'src').glob('*.lua')):
 name=f.name.removesuffix('.lua');cls='ModuleScript';parent=server;target='server'
 if f.name=='Server.server.lua':name='Main';cls='Script'
 elif f.name=='Client.client.lua':name='TouchlineClient';cls='LocalScript';parent=sps;target='client'
 elif name in shared:parent=sf;target='shared'
 source=f.read_text();item(parent,cls,name,source);manifest.append((target,cls,name,f.name))
 # MonetizationConfig is non-secret and required locally by both adapters.
 if f.stem=='MonetizationConfig':item(server,cls,name,source);manifest.append(('server',cls,name,f.name))
E.indent(root);place=ROOT/'TouchlineDynasty_RELEASE.rbxlx';E.ElementTree(root).write(place,encoding='utf-8',xml_declaration=True)
installer=["-- Studio Edit mode only. Refuses occupied names; never deletes existing objects.","assert(not game:GetService('RunService'):IsRunning(), 'Stop Play first')","local ss=game:GetService('ServerScriptService');local rs=game:GetService('ReplicatedStorage');local sp=game:GetService('StarterPlayer'):WaitForChild('StarterPlayerScripts')","assert(not ss:FindFirstChild('TouchlineServer') and not rs:FindFirstChild('TouchlineShared') and not sp:FindFirstChild('TouchlineClient'), 'Touchline names occupied: use the supplied place or move the old project objects to a backup')","local server=Instance.new('Folder');server.Name='TouchlineServer'","local shared=Instance.new('Folder');shared.Name='TouchlineShared'","local function put(class,name,source,parent)local s=Instance.new(class);s.Name=name;s.Source=source;s.Parent=parent;return s end"]
for target,cls,name,file in manifest:
 source=(ROOT/'src'/file).read_text();assert ']========]' not in source
 installer.append(f"put('{cls}','{name}',[========[{source}]========],{dict(server='server',shared='shared',client='sp')[target]})")
installer.append("shared.Parent=rs;server.Parent=ss;print('Touchline installed; live checks pending')")
(ROOT/'INSTALL_STUDIO.lua').write_text('\n'.join(installer))
embedded=[]
for n in E.parse(place).iter('Item'):
 p=n.find('Properties');s=p.find("ProtectedString[@name='Source']")
 if s is not None:embedded.append((p.find("string[@name='Name']").text,s.text))
for _,_,name,file in manifest:assert (name,(ROOT/'src'/file).read_text()) in embedded
assert len(embedded)==len(manifest)
(ROOT/'BUILD_MANIFEST.json').write_text(json.dumps({'scripts':len(manifest),'place_sha256':hashlib.sha256(place.read_bytes()).hexdigest(),'sources':{f.name:hashlib.sha256(f.read_bytes()).hexdigest() for f in sorted((ROOT/'src').glob('*.lua'))}},indent=2))
out=ROOT.parent/'TouchlineDynasty_RELEASE.zip'
with zipfile.ZipFile(out,'w',zipfile.ZIP_DEFLATED) as z:
 for f in sorted(ROOT.rglob('*')):
  if not f.is_file() or '__pycache__' in str(f) or f.name=='TouchlineDynasty.rbxlx':continue
  info=zipfile.ZipInfo('TouchlineDynasty/'+str(f.relative_to(ROOT)),(2026,10,24,0,0,0));info.compress_type=zipfile.ZIP_DEFLATED;info.external_attr=0o644<<16
  z.writestr(info,f.read_bytes())
with zipfile.ZipFile(out) as z:assert z.testzip() is None
print('PASS XML, embedded sources:',len(manifest),'ZIP integrity;',out)
