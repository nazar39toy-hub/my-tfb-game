"""Original deterministic PCM sounds; no external recordings or samples."""
from pathlib import Path
import math,random,struct,wave
ROOT=Path(__file__).resolve().parent;rate=22050
for name,duration in [('kick',.14),('whistle',.44),('ui',.065),('crowd',3.0)]:
 rng=random.Random(741);samples=[];filtered=0
 for i in range(int(rate*duration)):
  t=i/rate;noise=rng.uniform(-1,1)
  if name=='kick':v=(math.sin(2*math.pi*(100-45*t/duration)*t)*.7+noise*.3)*math.exp(-t*36)
  elif name=='whistle':v=(math.sin(2*math.pi*2700*t)+.35*math.sin(2*math.pi*3100*t))*.3*min(1,t/.025,(duration-t)/.04)
  elif name=='ui':v=math.sin(2*math.pi*1100*t)*.35*math.exp(-t*70)
  else:
   filtered=filtered*.86+noise*.14
   envelope=.6+.2*math.sin(2*math.pi*t/duration)
   v=(filtered*.6+noise*.08)*envelope*min(1,t/.1,(duration-t)/.1)
  samples.append(struct.pack('<h',round(max(-1,min(1,v))*22000)))
 with wave.open(str(ROOT/(name+'.wav')),'wb')as f:f.setparams((1,2,rate,0,'NONE','not compressed'));f.writeframes(b''.join(samples))
print('Generated 4 original WAV files')
