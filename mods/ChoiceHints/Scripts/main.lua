-- Optional choice-result spoilers. Disabled by default in the shipped mods.txt.
-- Steam v1.61 / UE4SS. All UObject access stays on the game thread.
local directory=debug.getinfo(1,'S').source:gsub('^@',''):match('^(.*[/\\])')
local analyze=dofile(directory..'analyze.lua')
local function valid(o)return o and o:IsValid()end
local function str(v)return type(v)=='string'and v or v:ToString()end
local function unbox(v)local ok,x=pcall(function()return v:get()end);return ok and x or v end
local function log(s)print('[ChoiceHints] '..s..'\n')end
RegisterCustomProperty({Name='CHActive',Type=PropertyTypes.ByteProperty,BelongsToClass='/Script/imal.CommuScriptSelect',OffsetInternal=0x230})
local changed={}
local function restore()
 for _,e in ipairs(changed)do
  if valid(e.widget)and e.widget:GetText():ToString()==e.decorated then e.widget:SetText(FText(e.original))end
 end
 changed={}
end
local function walk(x,out)
 if not valid(x)then return end
 if x:IsA('/Script/UMG.TextBlock')and x:GetFName():ToString():match('^font_text_%d+$')then out[#out+1]=x end
 if x:IsA('/Script/UMG.UserWidget')then walk(x.WidgetTree.RootWidget,out)
 elseif x:IsA('/Script/UMG.PanelWidget')then for i=0,x:GetChildrenCount()-1 do walk(x:GetChildAt(i),out)end end
end
local function shown(x)
 while valid(x)do
  local v=x:GetVisibility();if v==1 or v==2 then return false end
  x=x:GetParent()
 end
 return true
end
local cache,cacheKey=nil,nil
local function readGroups(parser)
 local loader=parser._AssetLoader;if not valid(loader)then return end
 local script,localized=nil,{}
 local name=str(parser._CommuScriptName)
 loader._CommuScriptFileMap:ForEach(function(k,v)
  local t=unbox(v)
  if valid(t)and t:IsA('/Script/Engine.DataTable')then
   local struct=t.RowStruct:GetFName():ToString()
   if struct=='MD_CommuScript'and str(unbox(k))==name then script=t
   elseif struct=='MD_CommuScriptLocalize'then
    for key,row in pairs(t:GetRowMap())do
     local texts={}
     for _,lang in ipairs({'Japanese','TraditionalChinese','SimplifiedChinese','Korean'})do
      local s=str(row[lang]);if s~=''then texts[#texts+1]=s end
     end
     localized[str(key)]=texts
    end
   end
  end
 end)
 if not script then return end
 local rows={}
 for key,r in pairs(script:GetRowMap())do
  local n=tonumber(str(key));if not n then return end
  local row={order=n,Label=str(r.Label),Command=str(r.Command),TextID=str(r.TextID)}
  for j=1,5 do row['Value'..j]=str(r['Value'..j])end
  rows[#rows+1]=row
 end
 table.sort(rows,function(a,b)return a.order<b.order end)
 return analyze.groups(rows,localized)
end
local lastSignature,lastError=nil,nil
local function tick()
 local parser,w
 for _,p in ipairs(FindAllOf('CommuScriptParser')or{})do
  if valid(p)and valid(p:GetWorld())then
   local select=p.CommuScriptSelect
   if valid(select)and select.CHActive~=0 and valid(select._WidgetSelect)and select._WidgetSelect:IsInViewport()then
    parser=p;w=select._WidgetSelect;break
   end
  end
 end
 if not parser then restore();lastSignature=nil;cache=nil;cacheKey=nil;return end
 local key=tostring(parser:GetAddress())..str(parser._CommuScriptPath)
 if key~=cacheKey then restore();cache=readGroups(parser);cacheKey=cache and key or nil end
 if not cache then return end
 local widgets,visible,texts={},{},{}
 walk(w,widgets)
 for _,t in ipairs(widgets)do if shown(t)then
  local text=t:GetText():ToString()
  for _,e in ipairs(changed)do if e.widget:GetAddress()==t:GetAddress()and text==e.decorated then text=e.original;break end end
  visible[#visible+1]=t;texts[#texts+1]=text
 end end
 local signature=key..table.concat(texts,'|')
 if signature==lastSignature then return end
 restore();lastSignature=signature
 local results=analyze.match(cache,texts);if not results then return end
 for i,t in ipairs(visible)do
  local decorated=texts[i]..'\n['..results[i]..']'
  t:SetText(FText(decorated))
  changed[#changed+1]={widget=t,original=texts[i],decorated=decorated}
 end
 log('Showing '..table.concat(results,' / '))
end
LoopInGameThreadWithDelay(50,function()
 local ok,err=pcall(tick)
 if not ok and err~=lastError then lastError=err;restore();log(tostring(err))end
end)
log('Enabled: show confirmed, differing dialogue evaluations')
