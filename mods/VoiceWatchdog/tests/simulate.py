"""Runs VoiceWatchdog against mocked UE4SS objects (lupa / Lua 5.1).
  python mods/VoiceWatchdog/tests/simulate.py
"""
import os, shutil, sys, tempfile

import lupa  # pip install lupa

SRC = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "Scripts", "main.lua")
CUE = "V_workchr_0102_A_01_00_001"

HARNESS = r"""
local clock=0
os.clock=function() return clock end
local loop
function RegisterCustomProperty() end
PropertyTypes={ByteProperty=1}
function LoopInGameThreadWithDelay(ms,fn) loop=fn end
-- modes: normal (starts by itself), nudge (pause/resume fixes it), restart (Play fixes it,
-- then never ends), never (stays in Prep), paused (game pause menu while in Prep)
function mkplayer(name,mode)
 local p={name=name,mode=mode,status=1,paused=(mode=='paused'),time=0,started=clock,calls={}}
 function p:IsValid() return true end
 function p:GetAddress() return self.name end
 function p:GetStatus() return self.status end
 function p:IsPaused() return self.paused end
 function p:GetTime() return self.time end
 function p:Pause(b) table.insert(self.calls,'Pause'..tostring(b)); if b==false and self.mode=='nudge' then self.status=2 end end
 function p:Stop() table.insert(self.calls,'Stop'); self.status=0 end
 function p:Play(t) table.insert(self.calls,'Play'); self.time=0; if self.mode=='restart' then self.status=2 else self.status=1 end end
 return p
end
voices={}
local sound={VWVoicesPaused=0,_VoiceList={}}
function sound:IsValid() return true end
function sound._VoiceList:ForEach(fn)
 for k,p in pairs(voices) do
  fn({get=function() return {ToString=function() return k end} end},
     {get=function() return {IsValid=function() return true end, Player=p} end})
 end
end
local world={IsValid=function() return true end}
local parser={CommuScriptSound=sound}
function parser:IsValid() return true end
function parser:GetWorld() return world end
function FindAllOf(c) return {parser} end
function addvoice(k,mode) voices[k]=mkplayer(k,mode) end
function step(dt)
 clock=clock+dt
 for k,p in pairs(voices) do
  if not p.paused and p.status~=0 then p.time=p.time+dt end
  if p.mode=='normal' and p.status==1 and clock-p.started>0.2 then p.status=2 end
  if (p.mode=='normal' or p.mode=='nudge') and p.status==2 and p.time>4.8 then p.status=0 end
 end
 loop()
end
function calls(k) return table.concat(voices[k].calls,',') end
function status(k) return voices[k].status end
"""


def run(mode, secs=14):
    d = tempfile.mkdtemp().replace(chr(92), "/")
    os.makedirs(d + "/Scripts")
    with open(d + "/durations.tsv", "w") as f:
        f.write("# test\n%s\t4797\n" % CUE)
    src = open(SRC, encoding="utf-8").read()
    marker = "local directory="
    start = src.index(marker)
    end = src.index("\n", start)
    src = src[:start] + "local directory='%s/Scripts/'" % d + src[end:]
    L = lupa.LuaRuntime()
    L.execute(HARNESS)
    L.execute(src)
    g = L.globals()
    g.addvoice(CUE, mode)
    for _ in range(int(secs / 0.25)):
        g.step(0.25)
    log = open(d + "/watchdog.log").read().splitlines()[1:]
    return g.calls(CUE), g.status(CUE), log


expect = {
    "normal": ("", 0),
    "nudge": ("Pausetrue,Pausefalse", 0),
    "restart": ("Pausetrue,Pausefalse,Stop,Play,Stop", 0),
    "never": ("Pausetrue,Pausefalse,Stop,Play,Stop,Play,Stop", 0),
    "paused": ("", 1),
}
failed = 0
for mode, (want_calls, want_status) in expect.items():
    calls, status, log = run(mode)
    ok = calls == want_calls and status == want_status
    failed += not ok
    print("%s %-7s calls=[%s] status=%s" % ("PASS" if ok else "FAIL", mode, calls, status))
    for line in log:
        print("      " + line[21:])
sys.exit(1 if failed else 0)
