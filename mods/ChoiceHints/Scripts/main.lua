-- Optional choice-result spoilers. Disabled by default in the shipped mods.txt.
-- Steam v1.61 / UE4SS. All UObject access stays on the game thread.
local directory=debug.getinfo(1,'S').source:gsub('^@',''):match('^(.*[/\\])')
local analyze=dofile(directory..'analyze.lua')
local function valid(o)return o and o:IsValid()end
local function str(v)return type(v)=='string'and v or v:ToString()end
local function unbox(v)local ok,x=pcall(function()return v:get()end);return ok and x or v end
local function log(s)print('[ChoiceHints] '..s..'\n')end
RegisterCustomProperty({Name='CHActive',Type=PropertyTypes.ByteProperty,BelongsToClass='/Script/imal.CommuScriptSelect',OffsetInternal=0x230})
-- Each hint is a separate label on the choice plate, so the choice text and its layout
-- stay untouched however long the text is.
local COLORS={PERFECT={1,0.82,0.25},GOOD={0.5,0.92,0.55},NORMAL={0.62,0.82,1},BAD={1,0.45,0.45}}
local badges={}
local textBlock
local function restore()
 for _,b in ipairs(badges)do if valid(b)then b:RemoveFromParent()end end
 badges={}
end
local function badge(owner,text,result)
 local plate=text:GetParent();plate=valid(plate)and plate:GetParent()
 if not(valid(plate)and plate:IsA('/Script/UMG.CanvasPanel'))then error('choice plate not found')end
 textBlock=valid(textBlock)and textBlock or StaticFindObject('/Script/UMG.TextBlock')
 local b=StaticConstructObject(textBlock,owner.WidgetTree)
 b:SetFont(text.Font)
 local font=b.Font;font.Size=math.max(12,math.floor(font.Size*0.85));b:SetFont(font)
 local c=COLORS[result]
 b:SetColorAndOpacity({SpecifiedColor={R=c[1],G=c[2],B=c[3],A=1},ColorUseRule=0})
 b:SetShadowOffset({X=1.5,Y=1.5});b:SetShadowColorAndOpacity({R=0,G=0,B=0,A=0.85})
 b:SetText(FText(result))
 b:SetVisibility(3) -- HitTestInvisible: never takes a click from the choice button
 -- Sit on the top edge of the visible plate image (normal_plate_NN), which is smaller
 -- than its canvas; fall back to the canvas top if the plate image is not found.
 local anchorX,anchorY,x,y=0.5,0,0,-2
 local id=text:GetFName():ToString():match('(%d+)$')
 for i=0,plate:GetChildrenCount()-1 do
  local c=plate:GetChildAt(i)
  if c:GetFName():ToString()=='normal_plate_'..id then
   local cs=c.Slot;local a=cs:GetAnchors();local al=cs:GetAlignment();local p=cs:GetPosition();local sz=cs:GetSize()
   if a.Minimum.X==a.Maximum.X and a.Minimum.Y==a.Maximum.Y then
    anchorX,anchorY=a.Minimum.X,a.Minimum.Y
    x=p.X+(0.5-al.X)*sz.X;y=p.Y-al.Y*sz.Y+4
   end
   break
  end
 end
 local slot=plate:AddChildToCanvas(b)
 slot:SetAutoSize(true);slot:SetZOrder(100)
 local anchors=slot:GetAnchors();anchors.Minimum.X=anchorX;anchors.Maximum.X=anchorX;anchors.Minimum.Y=anchorY;anchors.Maximum.Y=anchorY
 local align=slot:GetAlignment();align.X=0.5;align.Y=1
 local pos=slot:GetPosition();pos.X=x;pos.Y=y
 slot:SetAnchors(anchors);slot:SetAlignment(align);slot:SetPosition(pos)
 badges[#badges+1]=b
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
 for _,t in ipairs(widgets)do if shown(t)then visible[#visible+1]=t;texts[#texts+1]=t:GetText():ToString()end end
 local signature=key..table.concat(texts,'|')
 if signature==lastSignature then return end
 restore();lastSignature=signature
 local results=analyze.match(cache,texts);if not results then return end
 for i,t in ipairs(visible)do badge(w,t,results[i])end
 log('Showing '..table.concat(results,' / '))
end
LoopInGameThreadWithDelay(50,function()
 local ok,err=pcall(tick)
 if not ok and err~=lastError then lastError=err;restore();log(tostring(err))end
end)
log('Enabled: show confirmed, differing dialogue evaluations')
