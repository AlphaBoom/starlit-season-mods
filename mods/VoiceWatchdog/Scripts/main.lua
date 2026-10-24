-- Starlit Season v1.61. A dialogue voice can stay in CRI Prep forever: it is silent and
-- the dialogue waits for it, so auto-advance stops too. Such a voice is paused and
-- resumed first, then restarted; a restarted voice does not end by itself, so it is
-- stopped after its cue length. If it never starts, it is stopped so the dialogue can
-- carry on without it.
-- Players are reached through CommuScriptSound._VoiceList only: native calls on a
-- finished component found by a global scan crash the game.
local PREP_LIMIT=1.0
local MAX_RESTARTS=2
local END_MARGIN=0.25
local directory=debug.getinfo(1,'S').source:gsub('^@',''):match('^(.*[/\\])')
local file=io.open(directory..'../watchdog.log','a')
local function log(s)file:write(os.date('!%Y-%m-%dT%H:%M:%SZ ')..s..'\n');file:flush()end
local function valid(o)return o and o:IsValid()end
local function unbox(v)local ok,x=pcall(function()return v:get()end);return ok and x or v end
local function text(v)local ok,s=pcall(function()return v:ToString()end);return ok and s or tostring(v)end
RegisterCustomProperty({Name='VWVoicesPaused',Type=PropertyTypes.ByteProperty,BelongsToClass='/Script/imal.CommuScriptSound',OffsetInternal=0x348})

-- Cue lengths (ms) from CueSheet_Voice, loaded on the first restart only.
local lengths
local function cueLength(cue)
 if not lengths then
  lengths={}
  local f=io.open(directory..'../durations.tsv','r')
  if f then
   for line in f:lines()do local n,ms=line:match('^([^\t#]+)\t(%d+)$');if n then lengths[n]=tonumber(ms)end end
   f:close()
  else log('durations.tsv missing')end
 end
 local ms=lengths[cue];return ms and ms/1000
end

local parsers,lastScan,tick={},-100,0
local tracked={}
local function eachVoice(fn)
 for _,p in ipairs(parsers)do if valid(p)and valid(p:GetWorld())then
  local s=p.CommuScriptSound
  if valid(s)and s.VWVoicesPaused==0 then
   s._VoiceList:ForEach(function(key,value)
    local inst=unbox(value)
    if valid(inst)and valid(inst.Player)then fn(inst.Player,text(unbox(key)))end
   end)
  end
 end end
end
log('VoiceWatchdog ready')
LoopInGameThreadWithDelay(250,function()
 local ok,err=pcall(function()
  tick=tick+1
  if tick-lastScan>=8 then lastScan=tick;parsers=FindAllOf('CommuScriptParser')or{}end
  local now=os.clock();local seen={}
  eachVoice(function(player,cue)
   local id=player:GetAddress();seen[id]=true
   local t=tracked[id]
   if not t or t.cue~=cue then t={cue=cue,restarts=0};tracked[id]=t end
   local status=player:GetStatus()
   if t.report and status~=1 then log(('%s now status=%d'):format(cue,status));t.report=nil end
   if t.endAt and status==2 and player:GetTime()>=t.endAt then
    t.endAt=nil;player:Stop();log(cue..' restarted voice reached its length, stopped')
    return
   end
   if status~=1 or player:IsPaused()then t.since=nil;return end
   t.since=t.since or now
   if now-t.since<PREP_LIMIT or t.given then return end
   t.since=nil;t.report=true
   if not t.nudged then
    -- Window focus loss/regain revives such a voice; try the same pause/resume first.
    t.nudged=true
    log(('%s stuck in Prep, pause/resume time=%s'):format(cue,tostring(player:GetTime())))
    player:Pause(true);player:Pause(false)
   elseif t.restarts<MAX_RESTARTS then
    t.restarts=t.restarts+1
    local length=cueLength(cue)
    t.endAt=length and length+END_MARGIN
    log(('%s stuck in Prep, restart %d length=%s'):format(cue,t.restarts,tostring(length)))
    player:Stop();player:Play(0.0)
   else
    t.given=true;t.endAt=nil
    log(cue..' still in Prep, stopped so the dialogue can continue')
    player:Stop()
   end
  end)
  for id in pairs(tracked)do if not seen[id]then tracked[id]=nil end end
 end)
 if not ok then log('ERROR '..tostring(err))end
end)
