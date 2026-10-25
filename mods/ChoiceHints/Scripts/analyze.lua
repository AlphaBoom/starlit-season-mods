-- Pure script analysis. Never invokes a game command or changes a script row.
local M={}
local ratings={perfect='PERFECT',good='GOOD',normal='NORMAL',bad='BAD'}
function M.normalize(s)return (s:gsub('%s+',''):gsub('　',''))end
local function condition(r,choice)
 if r.Value1~='0'or r.Value2~='select'then return nil end
 if r.Value3=='=='then return choice==r.Value4 end
 if r.Value3=='!='then return choice~=r.Value4 end
end
local function outcome(rows,start,choice,labels)
 local i,stack,visited=start,{},{}
 while rows[i]and not visited[i]do
  visited[i]=true
  local r=rows[i];local c=r.Command
  local top=stack[#stack];local active=not top or top.active
  if c=='if'then
   local yes=false;if active then yes=condition(r,choice)end
   if active and yes==nil then return end
   stack[#stack+1]={parent=active,active=yes,taken=yes}
  elseif c=='elseIf'or c=='else'then
   if not top then return end
   local yes=false
   if top.parent and not top.taken then
    if c=='else'then yes=true else yes=condition(r,choice)end
    if yes==nil then return end
   end
   top.active=yes;top.taken=top.taken or yes
  elseif c=='endIf'then
   if not top then return end
   stack[#stack]=nil
  elseif active then
   if c=='uiResult'then return ratings[r.Value1=='select'and choice or r.Value1]end
   if c=='select'or r.Label=='end'then return end
   if c=='label'then
    local target=labels[r.Value1];if not target then return end
    i=target-1;stack={}
   end
  end
  i=i+1
 end
end
function M.groups(rows,localized)
 local labels,groups,buttons={},{},{}
 for i,r in ipairs(rows)do if r.Label~=''then labels[r.Label]=i end end
 for i,r in ipairs(rows)do
  if r.Command=='selectButton'then buttons[#buttons+1]=r
  elseif r.Command=='select'then
   local g={};local distinct={};local complete=#buttons>1
   for _,b in ipairs(buttons)do
    local result=outcome(rows,i+1,b.Value5,labels)
    local texts=localized[b.TextID]
    if not result or not texts then complete=false;break end
    g[#g+1]={texts=texts,result=result};distinct[result]=true
   end
   local n=0;for _ in pairs(distinct)do n=n+1 end
   if complete and n>1 then groups[#groups+1]=g end
   buttons={}
  end
 end
 return groups
end
-- Require the complete group to match the current, localized on-screen choices.
-- Ambiguous text or an unsupported result suppresses the entire group.
function M.match(groups,texts)
 local answer
 for _,g in ipairs(groups)do
  if #g==#texts then
   local mapping,used={},{};local good=true
   for n,text in ipairs(texts)do
    local found
    for j,b in ipairs(g)do
     for _,candidate in ipairs(b.texts)do
      if M.normalize(text)==M.normalize(candidate)then
       if found and found~=j then good=false end
       found=j
      end
     end
    end
    if not found or used[found]then good=false;break end
    used[found]=true;mapping[n]=g[found].result
   end
   if good then
    if answer and table.concat(answer,'|')~=table.concat(mapping,'|')then return end
    answer=mapping
   end
  end
 end
 return answer
end
return M
