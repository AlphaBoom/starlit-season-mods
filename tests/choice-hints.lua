-- Run from the repository root with Lua 5.4.
local M=dofile('mods/ChoiceHints/Scripts/analyze.lua')
local function r(c,a,b,d,e,label,id)
 return {Command=c,Value1=a or '',Value2=b or '',Value3=d or '',Value4=e or '',Value5='',Label=label or '',TextID=id or ''}
end
local function scenario()
 local a=r('selectButton');a.Value5='a';a.TextID='one'
 local b=r('selectButton');b.Value5='b';b.TextID='two'
 return {a,b,r('select'),r('if','0','select','==','a'),r('label','A'),r('else'),r('label','B'),r('endIf'),
  r('','',nil,nil,nil,'A'),r('uiResult','perfect'),r('','',nil,nil,nil,'B'),r('uiResult','normal')}
end
local loc={one={'First','第一项'},two={'Second','第二项'}}
local g=M.groups(scenario(),loc)
assert(#g==1)
assert(table.concat(M.match(g,{'第 二项','第一项'}),'|')=='NORMAL|PERFECT')
assert(not M.match(g,{'First','Missing'}))
assert(not M.match(g,{'First','First'}))
local s=scenario();s[10].Value1='normal';assert(#M.groups(s,loc)==0) -- same results
s=scenario();s[4].Value2='hidden_flag';assert(#M.groups(s,loc)==0) -- unknown condition
s=scenario();s[5].Value1='missing';assert(#M.groups(s,loc)==0) -- unresolved jump
s=scenario();s[10]=r('label','A');assert(#M.groups(s,loc)==0) -- cycle
s=scenario();s[10]=r('select');assert(#M.groups(s,loc)==0) -- next choice
s=scenario();s[10].Value1='unknown';assert(#M.groups(s,loc)==0)
local ambiguous={one={'Same'},two={'Same'}}
assert(not M.match(M.groups(scenario(),ambiguous),{'Same','Same'}))
local reversed=M.groups(scenario(),loc);reversed[1][1].result='BAD'
assert(not M.match({g[1],reversed[1]},{'First','Second'}))
-- elseIf and nested inactive conditions must preserve native branch semantics.
s=scenario();s[4].Value3='!=';assert(M.groups(s,loc)[1][1].result=='NORMAL')
s=scenario();s[6]=r('elseIf','0','select','==','b');assert(#M.groups(s,loc)==1)
print('ChoiceHints analyzer: 13 cases passed')
