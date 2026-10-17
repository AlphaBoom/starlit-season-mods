-- Starlit Season Steam v1.61. Unreal calls stay on the game thread.
local QUICK=16 -- extra save slot "slotQuick", shown directly below AUTO; used by F5 / F6.
local LABELS={'セーブする','ロードする'}
local directory=debug.getinfo(1,'S').source:gsub('^@',''):match('^(.*[/\\])')
local function native(name)return assert(package.loadlib(directory..'../DialogueMenu.dll',name))end
local openMenu,resume=native('MenuOpen'),native('MenuResume')
local slotsExtend,slotAppend,slotSetup=native('SlotsExtend'),native('SlotAppend'),native('SlotSetup')
local gameplay=StaticFindObject('/Script/Engine.GameplayStatics'):GetCDO()
local widgets=StaticFindObject('/Script/UMG.WidgetBlueprintLibrary'):GetCDO()
local function log(s)print('[DialogueMenu] '..s..'\n')end
local function valid(o)return o and o:IsValid()end
local function prop(class,name,offset,kind)
 RegisterCustomProperty({Name=name,Type=kind or PropertyTypes.ByteProperty,BelongsToClass='/Script/imal.'..class,OffsetInternal=offset})
end
prop('CommuScriptPause','DMPaused',0x230)
for _,p in ipairs({{'DMCursor',0x378},{'DMBusy',0x379},{'DMLog',0x37a}})do prop('WidgetCommuScriptPause',p[1],p[2])end
prop('WidgetSaveLoad','DMBusy',0x500)
prop('WidgetSaveLoad','DMReady',0x551)
prop('WidgetSaveLoad','DMFlag',0x555)
prop('WidgetSaveLoad','DMColumn',0x558,PropertyTypes.IntProperty)
prop('WidgetSaveLoad','DMRow',0x55c,PropertyTypes.IntProperty)

local quickReady=slotsExtend()==QUICK
log(quickReady and 'Quick slot registered' or 'Quick slot unavailable')

local frame,parsers,pc=0,{},nil
local session,pending,current,lastError=nil,nil,nil,nil
local installed={}
local sel,from=nil,nil -- selected mod button (1 SAVE, 2 LOAD) and native cursor it was entered from
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
local function hitArea(b)
 if valid(b.HitArea)then return b.HitArea end
 local h=b.HitAreaWidget;if valid(h)then return h end
end
local function extend(w)
 if not valid(w)or not w._ButtonList:Contains(0)then return end
 local id=w:GetAddress();local info=installed[id]
 if info then return info end
 local ref=w._ButtonList:Find(1):get();local row=ref:GetParent()
 if not valid(row)or not row:IsA('/Script/UMG.VerticalBox')then return end
 local back=row:GetChildAt(row:GetChildrenCount()-1)
 local backSlot={padding=margin(back.Slot.Padding),align=back.Slot.HorizontalAlignment,valign=back.Slot.VerticalAlignment}
 local refSlot={padding=margin(ref.Slot.Padding),align=ref.Slot.HorizontalAlignment,valign=ref.Slot.VerticalAlignment}
 back:RemoveFromParent()
 local buttons={}
 for n,label in ipairs(LABELS)do
  local b=widgets:Create(w:GetWorld(),ref:GetClass(),pc)
  local slot=row:AddChildToVerticalBox(b)
  slot:SetPadding(refSlot.padding);slot:SetHorizontalAlignment(refSlot.align);slot:SetVerticalAlignment(refSlot.valign)
  b:SetText(label);b:SetSelect(false);buttons[n]=b
 end
 local s=row:AddChildToVerticalBox(back)
 s:SetPadding(backSlot.padding);s:SetHorizontalAlignment(backSlot.align);s:SetVerticalAlignment(backSlot.valign)
 info={widget=w,buttons=buttons,row=row};installed[id]=info
 layout(info,ref,refSlot.padding)
 log('Added SAVE / LOAD to pause menu')
 return info
end
local function nativeButton(w,i)
 if w._ButtonList:Contains(i)then return w._ButtonList:Find(i):get()end
end
local function select(n)
 local w=current;local info=installed[w:GetAddress()]
 for i,b in ipairs(info.buttons)do if valid(b)then b:SetSelect(i==n)end end
 if n then
  local b=info.buttons[n];if valid(b)then b:PlaySelectAnimation()end
  local cur=nativeButton(w,w.DMCursor);if valid(cur)then cur:SetSelect(false)end
 end
 sel=n
end
local function restoreNative()
 local w=current;select(nil)
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
  if not up and cursor==1 then from=1;select(1)return true end
  if up and cursor==2 then from=2;select(2)return true end
  return false
 end
 if up and sel==2 then select(1)return true end
 if not up and sel==1 then select(2)return true end
 -- Leaving the mod buttons: let the game move when its cursor lands on the right neighbour.
 if(up and from==2)or(not up and from==1)then select(nil)return false end
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
 screens[id]={widget=w} -- attempted once per screen, even if it fails below
 local first=w.SlotList[2] -- Slot 01; AUTO (index 0) lives in its own panel.
 local list=valid(first)and first:GetParent()
 if not valid(list)or not list:IsA('/Script/UMG.PanelWidget')then log('QUICK: slot list not found')return end
 local q=widgets:Create(w:GetWorld(),first:GetClass(),pc)
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
 label(q)
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
  if info and info.quick and w.DMReady~=0 and w.DMBusy==0 then blocked[w:GetAddress()]=true;w.DMReady=0 end
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

local function open(request)
 if session then return end
 local parser=activeParser();if not valid(parser)then return end
 local pause=parser.CommuScriptPause;if not valid(pause)then return end
 if not request.fromPause and pause.DMPaused~=0 then return end
 if request.quick and not quickReady then return end
 local addr=openMenu(pause:GetAddress(),request.mode)
 if not addr or addr<=0 then error('Native initialization rejected: '..tostring(addr))end
 local w
 for _,candidate in ipairs(FindAllOf('WidgetSaveLoad')or{})do if valid(candidate)and candidate:GetAddress()==addr then w=candidate;break end end
 if not valid(w)then resume(pause:GetAddress());error('Save/load widget not found')end
 attachQuick(w)
 session={pause=pause,widget=w,parent=request.fromPause and current or nil,mode=request.mode,quick=request.quick,frames=0,step=0,returnSel=sel}
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
   for _,p in ipairs(parsers)do if valid(p)and valid(p:GetWorld())then pc=gameplay:GetPlayerController(p:GetWorld(),0);break end end
   if not valid(pc)then
    for _,w in ipairs(watched)do if valid(w)then pc=gameplay:GetPlayerController(w:GetWorld(),0);break end end
   end
   current=nil
   for _,p in ipairs(parsers)do if valid(p)and valid(p.CommuScriptPause)then
    local w=p.CommuScriptPause._WidgetPause
    if valid(w)then extend(w);if p.CommuScriptPause.DMPaused~=0 then current=w end end
   end end
   if not current then sel=nil end
   for id,info in pairs(screens)do if not valid(info.widget)then screens[id]=nil end end
   local live={}
   for _,w in ipairs(watched)do if valid(w)then live[#live+1]=w end end
   watched=live
  end
  extendAll()
  -- Native screens (title LOAD, map SYSTEM) are attached as soon as their slot list exists.
  for _,w in ipairs(watched)do
   if valid(w)then
    local info=screens[w:GetAddress()]
    if not info then attachQuick(w)
    elseif valid(info.quick)and w:IsInViewport()then label(info.quick)end
   end
  end
  if pending then local request=pending;pending=nil;open(request)end
  if session then
   local s=session;s.frames=s.frames+1
   if s.frames>10 and(not valid(s.widget)or not s.widget:IsInViewport())then
    if valid(s.parent)and s.parent:IsInViewport()then s.parent:SetVisibility(0);current=s.parent;if s.returnSel then select(s.returnSel)end
    elseif valid(s.pause)then resume(s.pause:GetAddress())end
    session=nil
   elseif s.quick and s.frames>30 and s.widget.DMReady~=0 then quickStep(s)end
  end
  if menuReady()then
   local info=installed[current:GetAddress()]
   for i,b in ipairs(info.buttons)do if valid(b)then
    local h=hitArea(b)
    local hovered=b:IsHovered()or(valid(h)and h:GetOnHoveredSignal(false))
    if hovered and sel~=i then from=current.DMCursor;select(i)end
    if valid(h)and h:GetOnClickedSignal(true)then pending={mode=i-1,fromPause=true}end
   end end
  end
  local save,load=pressed(keys.save),pressed(keys.load)
  if save and not lastSave then open({mode=0,quick=true})elseif load and not lastLoad then open({mode=1,quick=true})end
  lastSave,lastLoad=save,load
 end)
 if not ok and err~=lastError then lastError=err;log(tostring(err))end
end)
