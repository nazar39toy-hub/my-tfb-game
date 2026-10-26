-- Shared competitive rules. Difficulty is disclosed and separates records.
return {
 step=.05, duration=210, extraTime=70, aiInterval=.20, snapshotInterval=.10,
 halftimePause=2, restartPause=1.15, penaltyTimeout=8, maxSubstitutions=5,
 replayFrames=45, eventLimit=64,
 difficulty={easy=.93,normal=1,hard=1.07},
 styles={
  possession={width=1,depth=1,press=1,passing=1.08,speed=.96,stamina=1},
  counter={width=.92,depth=.85,press=.8,passing=.98,speed=1.07,stamina=1.03},
  press={width=.92,depth=1.13,press=1.5,passing=.97,speed=1.02,stamina=1.32},
  lowblock={width=.8,depth=.7,press=.65,passing=.96,speed=.97,stamina=.84},
  wings={width=1.22,depth=1.02,press=.95,passing=1.02,speed=1,stamina=1.1},
 },
}
