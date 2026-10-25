-- Starlit Season Steam v1.61. Unreal calls stay on the game thread.
local QUICK=16 -- extra save slot "slotQuick", shown directly below AUTO; used by F5 / F6.
local LABELS={'SAVE','LOAD'} -- English: no localisation needed
local directory=debug.getinfo(1,'S').source:gsub('^@',''):match('^(.*[/\\])')
local function native(name)return assert(package.loadlib(directory..'../DialogueMenu.dll',name))end
local openMenu,resume,repause,setInput=native('MenuOpen'),native('MenuResume'),native('MenuRepause'),native('MenuInput')
local slotsExtend,slotAppend,slotSetup=native('SlotsExtend'),native('SlotAppend'),native('SlotSetup')
local saveBegin,saveFix=native('DialogueSaveBegin'),native('DialogueSaveFix')
-- Class default objects are looked up on use: mods can start before the engine has
-- loaded UMG, and an early lookup then stays empty for the whole session.
local cdoCache={}
local function cdo(path)
 local o=cdoCache[path]
 if o and o:IsValid()then return o end
 local c=StaticFindObject(path)
 o=c and c:IsValid()and c:GetCDO()or nil
 cdoCache[path]=o
 return o
end
local function log(s)print('[DialogueMenu] '..s..'\n')end
local function valid(o)return o and o:IsValid()end
local function prop(class,name,offset,kind)
 RegisterCustomProperty({Name=name,Type=kind or PropertyTypes.ByteProperty,BelongsToClass='/Script/imal.'..class,OffsetInternal=offset})
end
prop('CommuScriptPause','DMPaused',0x230)
for _,p in ipairs({{'DMCursor',0x378},{'DMBusy',0x379},{'DMLog',0x37a}})do prop('WidgetCommuScriptPause',p[1],p[2])end
prop('WidgetSaveLoad','DMSaving',0x500)
prop('WidgetSaveLoad','DMReady',0x551)
prop('WidgetSaveLoad','DMFlag',0x555)
prop('WidgetSaveLoad','DMColumn',0x558,PropertyTypes.IntProperty)
prop('WidgetSaveLoad','DMRow',0x55c,PropertyTypes.IntProperty)

local quickReady=slotsExtend()==QUICK
log(quickReady and 'Quick slot registered' or 'Quick slot unavailable')

local frame,parsers,pc=0,{},nil
local session,pending,current,lastError=nil,nil,nil,nil
local installed={}
local mouseTargets={}
local mouseChecker=nil
local sel=nil -- selected mod button (1 SAVE, 2 LOAD)
local lastSave,lastLoad=false,false
local keys={save={KeyName=FName('F5')},load={KeyName=FName('F6')}}
local function pressed(k)return valid(pc)and pc:IsInputKeyDown(k)end
local function activeParser()
 for _,p in ipairs(parsers)do if valid(p)and valid(p:GetWorld())then
  local m=p.CommuScriptMessage
  if valid(m)and(valid(m._WidgetMessage)or valid(m._WidgetNovel)or valid(m._WidgetCinema))then return p end
 end end
end
local function margin(m)return{Left=m.Left,Top=m.Top,Right=m.Right,Bottom=m.Bottom}end

---------------------------------------------------------------------------
-- Dialogue pause menu: native look-alike SAVE / LOAD buttons above 戻る.
---------------------------------------------------------------------------
-- Keep the enlarged menu centred where the original three buttons were.
-- Applied in the same tick the buttons are inserted, so the first open never jumps.
local function layout(info,ref,padding)
 local h=ref:GetDesiredSize().Y
 if not h or h<=0 then h=62 end
 info.row:SetRenderTranslation({X=0,Y=-(h+padding.Top+padding.Bottom)})
end
local function findNamed(o,name,class)
 local found
 local function walk(x)
  if found or not valid(x)then return end
  if(name and x:GetFName():ToString()==name)or(class and x:IsA(class))then found=x return end
  if x:IsA('/Script/UMG.UserWidget')then walk(x.WidgetTree.RootWidget)
  elseif x:IsA('/Script/UMG.PanelWidget')then for i=0,x:GetChildrenCount()-1 do walk(x:GetChildAt(i))end end
 end
 walk(o);return found
end
-- A single independent checker binds the hit areas' native Slate delegates.
-- Keep it for the process lifetime; it stores only weak references to hit areas.
-- Its outer is the permanent CDO so it cannot retain a dialogue/world after travel.
local function bindMouse(w,buttons)
 if not valid(mouseChecker)then
  local class=StaticFindObject('/Script/imal.HitAreaChecker')
  mouseChecker=StaticConstructObject(class,class:GetCDO(),0,0,0x40000000) -- Internal RootSet
 end
 if not valid(mouseChecker)then error('Mouse checker not created')end
 local hits={}
 for n,b in ipairs(buttons)do
  local h=findNamed(b,nil,'/Script/imal.HitAreaWidget')
  if not valid(h)then error('Pause button hit area not found')end
  mouseChecker:AddHitArea(h,n)
  hits[n]=h:GetAddress()
  mouseTargets[h:GetAddress()]={widget=w,index=n}
 end
 return hits
end
local function extend(w)
 if not valid(w)or not w._ButtonList:Contains(0)then return end
 local id=w:GetAddress();local info=installed[id]
 if info then return info end
 local wbl=cdo('/Script/UMG.WidgetBlueprintLibrary');if not wbl or not valid(pc)then return end -- retried next tick
 local ref=w._ButtonList:Find(1):get();local row=ref:GetParent()
 if not valid(row)or not row:IsA('/Script/UMG.VerticalBox')then return end
 local back=row:GetChildAt(row:GetChildrenCount()-1)
 local backSlot={padding=margin(back.Slot.Padding),align=back.Slot.HorizontalAlignment,valign=back.Slot.VerticalAlignment}
 local refSlot={padding=margin(ref.Slot.Padding),align=ref.Slot.HorizontalAlignment,valign=ref.Slot.VerticalAlignment}
 back:RemoveFromParent()
 local buttons={}
 for n,label in ipairs(LABELS)do
  local b=wbl:Create(w:GetWorld(),ref:GetClass(),pc)
  local slot=row:AddChildToVerticalBox(b)
  slot:SetPadding(refSlot.padding);slot:SetHorizontalAlignment(refSlot.align);slot:SetVerticalAlignment(refSlot.valign)
  b:SetText(label);b:SetSelect(false);buttons[n]=b
 end
 local s=row:AddChildToVerticalBox(back)
 s:SetPadding(backSlot.padding);s:SetHorizontalAlignment(backSlot.align);s:SetVerticalAlignment(backSlot.valign)
 info={widget=w,buttons=buttons,row=row};installed[id]=info
 info.hits=bindMouse(w,buttons)
 layout(info,ref,refSlot.padding)
 log('Added SAVE / LOAD to pause menu')
 return info
end
-- Cursor sound: the game's static PlaySE helper (WidgetCostumeGet::PlaySE ignores
-- its instance), with the system move sound the save/load screen uses.
local moveSE=nil
local function learnSE(w)
 if not moveSE and valid(w)then local id=w.SE_Move:ToString();if id~=''then moveSE=id;log('Move sound '..id)end end
end
local function playMove()
 if not moveSE then
  local cdo=StaticFindObject('/Game/Widget/System/WBP_SaveLoad.Default__WBP_SaveLoad_C')
  if valid(cdo)then learnSE(cdo)end
 end
 local snd=cdo('/Script/imal.WidgetCostumeGet')
 if snd and moveSE then pcall(function()snd:PlaySE(moveSE)end)end
end
local function nativeButton(w,i)
 if w._ButtonList:Contains(i)then return w._ButtonList:Find(i):get()end
end
local function select(n,quiet)
 local w=current;local info=installed[w:GetAddress()]
 for i,b in ipairs(info.buttons)do if valid(b)then b:SetSelect(i==n)end end
 if n and n~=sel and not quiet then playMove()end
 if n then
  local b=info.buttons[n];if valid(b)then b:PlaySelectAnimation()end
  local cur=nativeButton(w,w.DMCursor);if valid(cur)then cur:SetSelect(false)end
 end
 sel=n
end
local function restoreNative()
 local w=current;select(nil);playMove()
 local cur=nativeButton(w,w.DMCursor);if valid(cur)then cur:SetSelect(true);cur:PlaySelectAnimation()end
end
local function menuReady()
 local w=current
 return valid(w)and w:IsInViewport()and w:IsVisible()and installed[w:GetAddress()]
  and w.DMBusy==0 and w.DMLog==0 and not session
end
-- Returns true when the move is consumed by the two mod buttons.
local function move(up)
 local cursor=current.DMCursor
 if not sel then
  if not up and cursor==1 then select(1)return true end
  if up and cursor==2 then select(2)return true end
  return false
 end
 if up and sel==2 then select(1)return true end
 if not up and sel==1 then select(2)return true end
 -- Mouse can enter from any native cursor; leave at the visual neighbour.
 current.DMCursor=up and 1 or 2
 restoreNative()return true
end
RegisterHook('/Script/imal.CommuScriptInput:OnPressed_Pause',function(_,kind)
 if not menuReady()then sel=nil return end
 local k=kind:get()
 if k==15 or k==16 then if move(k==15)then kind:set(255)end
 elseif k==22 and sel then pending={mode=sel-1,fromPause=true};kind:set(255)
 elseif sel then select(nil)end
end)
local axisNext=0
RegisterHook('/Script/imal.CommuScriptInput:OnMoveAxis_Pause',function(_,kind,value)
 if not menuReady()or kind:get()~=0 then return end
 local v=value:get()
 if type(v)~='number'or math.abs(v)<=0.5 then axisNext=0 return end
 local now=os.clock()
 if now<axisNext then if sel then kind:set(255)end return end
 if move(v>0)then kind:set(255);axisNext=now+0.22 end
end)
-- Handle events after the hit area's native callback. The independent checker
-- has no pause-menu delegates, so these clicks cannot also trigger Skip/Back.
for _,event in ipairs({'OnHoveredCallBack','OnClickedCallBack'})do
 RegisterHook('/Script/imal.HitAreaWidget:'..event,function()end,function(self)
  local t=mouseTargets[self:get():GetAddress()]
  if not t or not menuReady()or t.widget:GetAddress()~=current:GetAddress()then return end
  if sel~=t.index then select(t.index)end
  if event=='OnClickedCallBack'then pending={mode=t.index-1,fromPause=true}end
 end)
end
RegisterHook('/Script/imal.WidgetCommuScriptPause:OnHoveredCursor',function(self)
 if sel and current and self:get():GetAddress()==current:GetAddress()then select(nil)end
end)
-- The game creates the pause widget inside its input handler; extend it before the next frame renders.
local function extendAll()
 for _,p in ipairs(parsers)do if valid(p)then
  local pause=p.CommuScriptPause
  if valid(pause)then local w=pause._WidgetPause
   if valid(w)and not installed[w:GetAddress()]then extend(w)end
   if valid(w)and pause.DMPaused~=0 then current=w end
  end
 end end
end
RegisterHook('/Script/imal.CommuScriptInput:OnPressed_Commu',function()end,function()pcall(extendAll)end)

---------------------------------------------------------------------------
-- Save / load screens: an independent QUICK slot row below AUTO.
---------------------------------------------------------------------------
local screens={} -- WidgetSaveLoad address -> {widget, quick}
-- QUICK row style: one of the game's own row styles (the same switch that gives
-- AUTO its look), so textures, gradient and shape are the game's.
local QUICK_STYLE='Clear'
local function tint(q)
 if not valid(q)then return end
 local style=findNamed(q,'WidgetSwitcher_clear')
 if not valid(style)then return end
 local panel=findNamed(style,QUICK_STYLE)
 if not valid(panel)then return end
 if style:GetActiveWidget():GetAddress()~=panel:GetAddress()then style:SetActiveWidget(panel)end
 for j=0,panel:GetChildrenCount()-1 do
  local c=panel:GetChildAt(j)
  if c:GetFName():ToString():find('clear_icon')and c:IsVisible()then c:SetVisibility(1)end
 end
end
local function label(q)
 for name,text in pairs({TextBlock_96='QUICK',text_slot_number='QS'})do
  local t=findNamed(q,name)
  if valid(t)and t:GetText():ToString()~=text then t:SetText(FText(text))end
 end
end
local function attachQuick(w)
 local id=w:GetAddress();local info=screens[id]
 if info then return info end
 if not quickReady or #w.SlotList~=QUICK then return end
 if not valid(pc)then pc=cdo('/Script/Engine.GameplayStatics'):GetPlayerController(w:GetWorld(),0)end
 if not valid(pc)or not cdo('/Script/UMG.WidgetBlueprintLibrary')then return end -- retried next tick
 screens[id]={widget=w} -- attempted once per screen, even if it fails below
 local first=w.SlotList[2] -- Slot 01; AUTO (index 0) lives in its own panel.
 local list=valid(first)and first:GetParent()
 if not valid(list)or not list:IsA('/Script/UMG.PanelWidget')then log('QUICK: slot list not found')return end
 local q=cdo('/Script/UMG.WidgetBlueprintLibrary'):Create(w:GetWorld(),first:GetClass(),pc)
 if not valid(q)then log('QUICK: row not created')return end
 local wa,qa=w:GetAddress(),q:GetAddress()
 local n,detail=slotAppend(wa,qa)
 if n~=QUICK+1 then log(string.format('QUICK: append failed %s %s (%s / %s)',tostring(n),detail and string.format('%x',detail)or'',w:GetClass():GetFullName(),q:GetClass():GetFullName()))return end
 -- Rebuild the list with QUICK first so it sits directly below AUTO.
 local children={}
 for i=0,list:GetChildrenCount()-1 do
  local c=list:GetChildAt(i);children[#children+1]={c,c.Slot and margin(c.Slot.Padding)}
 end
 list:ClearChildren()
 local s=list:AddChild(q);if children[1][2]then s:SetPadding(children[1][2])end
 for _,e in ipairs(children)do
  local cs=list:AddChild(e[1]);if e[2]then cs:SetPadding(e[2])end
 end
 w.RowNum=#w.SlotList
 slotSetup(q:GetAddress(),QUICK,w.DMFlag)
 -- Mouse: register the row's hit area under the slot index, like the native rows.
 local hit=findNamed(q.WidgetTree.RootWidget,nil,'/Script/imal.HitAreaWidget')
 if valid(hit)and valid(w.HitAreaChecker)then w.HitAreaChecker:AddHitArea(hit,QUICK)end
 label(q);tint(q)
 screens[id].quick=q
 log(string.format('Added QUICK slot (%s, column %d, hit %s)',list:GetClass():GetFName():ToString(),w.DMColumn,tostring(valid(hit))))
 return screens[id]
end
local function autoShown(w)return valid(w.PanelContinue)and w.PanelContinue:IsVisible()end
-- Navigation order: AUTO(0) -> QUICK(16) -> 1 .. 15 -> wrap.
local function target(w,down)
 local i,auto=w.DMRow,autoShown(w)
 if down then
  if i==0 then return QUICK elseif i==QUICK then return 1
  elseif i==QUICK-1 then return auto and 0 or QUICK else return i+1 end
 end
 if i==1 then return QUICK elseif i==QUICK then return auto and 0 or QUICK-1
 elseif i==0 then return QUICK-1 else return i-1 end
end
for _,dir in ipairs({'Down','Up'})do
 local blocked={}
 RegisterHook('/Script/imal.WidgetSaveLoad:OnMove'..dir,function(self)
  local w=self:get()
  local info=screens[w:GetAddress()]
  if info and info.quick and w.DMReady~=0 and w.DMSaving==0 then blocked[w:GetAddress()]=true;w.DMReady=0 end
 end,function(self)
  local w=self:get()
  if blocked[w:GetAddress()]then
   blocked[w:GetAddress()]=nil;w.DMReady=1
   w:OnHoveredCursor(target(w,dir=='Down'))
  end
 end)
end

local function openDialog()
 for _,d in ipairs(FindAllOf('WidgetDialog')or{})do
  if valid(d)and d:IsInViewport()and d:IsVisible()then return d end
 end
end
-- F5 / F6: drive the native screen on the QUICK slot, step by step.
local function quickStep(s)
 local w=s.widget;local d=openDialog()
 local since=s.frames-(s.at or 0)
 if s.step==0 then
  w:OnHoveredCursor(QUICK);w:OnClickedCursor(QUICK);s.step=1;s.at=s.frames
 elseif s.step==1 then
  if d and since>20 then
   d:OnClickYesNoButton(true,false,false);s.step=2;s.at=s.frames;s.dialog=d:GetAddress()
   if s.mode==1 then s.step=4 end -- the game takes over and loads the slot
  elseif not d and since>120 then w:OnCancel();s.step=4;log('Quick load: no quick save yet')end
 elseif s.step==2 and since>20 then
  if d and d:GetAddress()~=s.dialog then d:OnClickCloseButon(false);s.dialog=d:GetAddress();s.at=s.frames
  elseif not d and since>60 then w:OnCancel();s.step=3 end
 end
end

-- Outside a dialogue F5 / F6 go through the scene's SYSTEM menu exactly as a click
-- would: guide bar SYSTEM, then セーブ / ロード, then the QUICK slot; afterwards the
-- menu closes itself (OnCancel). The game decides whether saving is allowed here.
-- The SYSTEM menu is kept transparent meanwhile so only the save screen is seen.
local scene=nil
local function visibleOf(class)
 for _,w in ipairs(FindAllOf(class)or{})do if valid(w)and w:IsInViewport()and w:IsVisible()then return w end end
end
-- The SYSTEM button: home guide bar (OnClickedSystem) or the map screen (OnClickSystem).
local systemFn={}
local function systemButton()
 for _,w in ipairs(FindAllOf('UserWidget')or{})do if valid(w)and w:IsInViewport()and w:IsVisible()then
  local c=w:GetClass();local id=c:GetAddress()
  if systemFn[id]==nil then
   systemFn[id]=false
   local k=c
   while valid(k)and systemFn[id]==false do
    k:ForEachFunction(function(f)local n=f:GetFName():ToString();if n=='OnClickedSystem'or n=='OnClickSystem'then systemFn[id]=n end end)
    k=k:GetSuperStruct()
   end
  end
  if systemFn[id]then return w,systemFn[id]end
 end end
end
function sceneQuick(mode)
 if scene then return end
 local w,fn=systemButton()
 if not w or visibleOf('WidgetSystemSelectBase')or visibleOf('WidgetSaveLoad')then log('Ignored: no SYSTEM menu here')return end
 scene={mode=mode,step='system',frames=0}
 w[fn](w)
end
local function sceneTick()
 local t=scene;t.frames=t.frames+1
 if t.step=='system'then
  local sys=visibleOf('WidgetSystemSelectBase')
  if sys and not t.sys then t.sys=sys;t.at=t.frames;sys:SetRenderOpacity(0)end
  if t.sys and t.frames-t.at>20 then
   t.sys:OnHoveredCursor(t.mode);t.sys:OnClickedCursor(t.mode);t.step='screen';t.at=t.frames
  elseif not t.sys and t.frames>90 then log('Ignored: SYSTEM menu not available');scene=nil end
 elseif t.step=='screen'then
  local w=visibleOf('WidgetSaveLoad')
  if w and not session then
   attachQuick(w)
   session={widget=w,mode=t.mode,quick=true,frames=0,step=0,scene=true}
   log('Opened '..(t.mode==0 and 'SAVE'or'LOAD')..' quick (scene)')
   t.step='wait'
  elseif t.frames-t.at>120 then log('Quick: save screen did not open');if valid(t.sys)then t.sys:SetRenderOpacity(1)end;scene=nil end
 elseif t.step=='wait'then
  if not session then t.step='close';t.at=t.frames end
 elseif t.step=='close'then
  -- After a confirmed load the game travels away. Otherwise the save screen's own
  -- callback reopens the SYSTEM menu; close it once it accepts input (retrying while
  -- its in-animation runs), and only then make it visible again.
  local sys=valid(t.sys)and t.sys:IsInViewport()and t.sys:IsVisible()
  if sys then
   t.seen=true
   if (t.frames-t.at)%30==20 then t.sys:OnCancel()end
   if t.frames-t.at>600 then t.sys:SetRenderOpacity(1);scene=nil end
  elseif t.seen or t.frames-t.at>600 then
   if valid(t.sys)then t.sys:SetRenderOpacity(1)end
   scene=nil
  end
 end
end
local function open(request)
 if session then log('Ignored: save/load screen already open')return end
 local parser=activeParser()
 if not valid(parser)then if request.quick then sceneQuick(request.mode)end return end
 local pause=parser.CommuScriptPause;if not valid(pause)then log('Ignored: no dialogue pause')return end
 if not request.fromPause and pause.DMPaused~=0 then
  -- F5 / F6 from the open dialogue menu: run over the menu and come back to it.
  if menuReady()then request.fromPause=true else log('Ignored: dialogue busy')return end
 end
 if request.quick and not quickReady then return end
 -- Saves made from a dialogue are rewritten from the AUTO save (see DialogueSaveFix).
 local fixing=false
 if request.mode==0 then fixing=saveBegin()==1 end
 local addr=openMenu(pause:GetAddress(),request.mode)
 if not addr or addr<=0 then error('Native initialization rejected: '..tostring(addr))end
 local w
 for _,candidate in ipairs(FindAllOf('WidgetSaveLoad')or{})do if valid(candidate)and candidate:GetAddress()==addr then w=candidate;break end end
 if not valid(w)then resume(pause:GetAddress());error('Save/load widget not found')end
 attachQuick(w)
 session={parser=parser,pause=pause,widget=w,parent=request.fromPause and current or nil,mode=request.mode,quick=request.quick,frames=0,step=0,returnSel=sel,fixing=fixing}
 if valid(session.parent)then select(nil);session.parent:SetVisibility(1)end
 log('Opened '..(request.mode==0 and 'SAVE' or 'LOAD')..(request.quick and ' quick' or ''))
end

local watched={}
NotifyOnNewObject('/Script/imal.WidgetSaveLoad',function(w)watched[#watched+1]=w end)
print('[DialogueMenu] Ready: pause menu SAVE / LOAD; QUICK slot; F5 quick save / F6 quick load\n')
LoopInGameThreadWithDelay(1,function()
 local ok,err=pcall(function()
  frame=frame+1
  if frame%25==1 then
   parsers=FindAllOf('CommuScriptParser')or{}
   for _,p in ipairs(parsers)do if valid(p)and valid(p:GetWorld())then pc=cdo('/Script/Engine.GameplayStatics'):GetPlayerController(p:GetWorld(),0);break end end
   if not valid(pc)then
    for _,w in ipairs(watched)do if valid(w)then pc=cdo('/Script/Engine.GameplayStatics'):GetPlayerController(w:GetWorld(),0);break end end
   end
   current=nil
   for _,p in ipairs(parsers)do if valid(p)and valid(p.CommuScriptPause)then
    local w=p.CommuScriptPause._WidgetPause
    if valid(w)then extend(w);if p.CommuScriptPause.DMPaused~=0 then current=w end end
   end end
   if not current then sel=nil end
   for id,info in pairs(screens)do if not valid(info.widget)then screens[id]=nil end end
   for id,info in pairs(installed)do if not valid(info.widget)then
    for _,hit in ipairs(info.hits or{})do mouseTargets[hit]=nil end
    installed[id]=nil
   end end
   local live={}
   for _,w in ipairs(watched)do if valid(w)then live[#live+1]=w end end
   watched=live
  end
  extendAll()
  -- Native screens (title LOAD, map SYSTEM) are attached as soon as their slot list exists.
  for _,w in ipairs(watched)do
   if valid(w)then
    local info=screens[w:GetAddress()]
    learnSE(w)
    if not info then attachQuick(w)
    elseif valid(info.quick)and w:IsInViewport()then label(info.quick);tint(info.quick)end
   end
  end
  if scene then local ok,e=pcall(sceneTick);if not ok then log('Quick (scene): '..tostring(e));scene=nil end end
  if pending then local request=pending;pending=nil;open(request)end
  if session then
   local s=session;s.frames=s.frames+1
   if s.frames>10 and(not valid(s.widget)or not s.widget:IsInViewport())then
    -- The native load sets the screen's processing flag and never clears it (it travels).
    if s.mode==1 and valid(s.widget)and s.widget.DMSaving~=0 then s.loading=true end
    -- The game closes the screen as soon as the save message is dismissed.
    if s.fixing and valid(s.widget)then local r=saveFix(s.widget:GetAddress());if r>0 then log('Dialogue save resume point: slot '..r)end end
    if valid(s.parent)and valid(s.pause)and not s.loading then
     -- Back to the menu exactly as it was: the screen's close path dropped the paused
     -- state and the dialogue input mode, so restore both; the menu never closes.
     repause(s.pause:GetAddress());setInput(s.parser:GetAddress(),2)
     s.parent:SetVisibility(0);current=s.parent
     if s.returnSel then select(s.returnSel,true)end
    elseif valid(s.parent)and valid(s.pause)then
     -- A load was confirmed: the game is travelling to the loaded save; leave the menu.
     s.parent:SetVisibility(0);resume(s.pause:GetAddress());setInput(s.parser:GetAddress(),1)
    elseif valid(s.pause)then resume(s.pause:GetAddress());if valid(s.parser)then setInput(s.parser:GetAddress(),1)end end
    session=nil
    if valid(current)then log(string.format('Back in menu: cursor %d busy %d log %d paused %d',current.DMCursor,current.DMBusy,current.DMLog,valid(s.pause)and s.pause.DMPaused or -1))end
   else
    if s.mode==1 and s.widget.DMSaving~=0 then s.loading=true end
    -- After a save completes (screen idle again), store the dialogue's resume point.
    if s.fixing and valid(s.widget)and s.frames%15==0 and s.widget.DMSaving==0 then
     local r=saveFix(s.widget:GetAddress())
     if r>0 then log('Dialogue save resume point: slot '..r)end
     if r>0 then
      s.widget.SlotList:ForEach(function(i,e)local c=e:get();if i==(r==QUICK and #s.widget.SlotList or r+1)then slotSetup(c:GetAddress(),r,s.widget.DMFlag)end end)
     end
    end
    if s.quick and s.frames>30 and s.widget.DMReady~=0 then quickStep(s)end
   end
  end
  local save,load=pressed(keys.save),pressed(keys.load)
  if save and not lastSave then open({mode=0,quick=true})elseif load and not lastLoad then open({mode=1,quick=true})end
  lastSave,lastLoad=save,load
 end)
 if not ok and err~=lastError then lastError=err;log(tostring(err))end
end)
