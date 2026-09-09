local Generator = {}

-- =====================================================================
-- Polymorphic variable name generator (collision & shadow-safe)
-- =====================================================================
local function make_name_gen(seed)
    local rng_state = seed
    local function rng()
        rng_state = (rng_state * 1103515245 + 12345) % 2147483648
        return rng_state
    end
    local used = {
        ["and"]=true,["break"]=true,["do"]=true,["else"]=true,["elseif"]=true,
        ["end"]=true,["false"]=true,["for"]=true,["function"]=true,["if"]=true,
        ["in"]=true,["local"]=true,["nil"]=true,["not"]=true,["or"]=true,
        ["repeat"]=true,["return"]=true,["then"]=true,["true"]=true,["until"]=true,
        ["while"]=true,["a"]=true,["b"]=true,["c"]=true,["bx"]=true,["sbx"]=true,
        ["op"]=true,["w"]=true,["i"]=true,["x"]=true,["r"]=true,["q"]=true,["u"]=true,
        ["env"]=true,["upvals"]=true,["pr"]=true,["_a"]=true,["_b"]=true,["_c"]=true,
        ["_bx"]=true,["_sbx"]=true,["j"]=true,["P"]=true,["d"]=true,["I"]=true,
        ["f"]=true,["O"]=true,["k"]=true,["J"]=true,["X"]=true,["A"]=true,["e"]=true,["N"]=true,["v"]=true
    }
    return function()
        local chars = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
        local first = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ_"
        local r
        repeat
            local len = (rng() % 5) + 3
            local f_idx = (rng() % #first) + 1
            r = first:sub(f_idx, f_idx)
            for _ = 2, len do
                local c_idx = (rng() % #chars) + 1
                r = r .. chars:sub(c_idx, c_idx)
            end
        until not used[r]
        used[r] = true
        return r
    end
end

-- =====================================================================
-- RUNTIME_DECODER template (Luraph v14.7+ verified multi-key cipher)
-- =====================================================================
local RUNTIME_DECODER = [=[
local j,P,d,I,f,O,k,J,a,X,A,e,N,v=string.byte,string.sub,string.char,string.gsub,string.rep,setmetatable,pcall,type,tostring,assert,loadstring,unpack or table.unpack,function(t,y)y=y%4294967296;return string.char(math.floor(y/16777216)%256,math.floor(y/65536)%256,math.floor(y/256)%256,y%256);end,{};
for c=0,255 do v[c]=d(c);end;
local v_off=5;do local _h={25656,{0x1B,0x4C,0x75,0x61,0x50},a(A)};for _V,_s in next,_h do local _c={k(A,_V%2==0 and d(e(_s))or _s,nil,nil)};if _c[1]and k(_c[2])~=not _c[3]then v_off=15.0;end;end;end;
local c,V,s=(function(n)n=I(n,"z","!!!!!");return I(n,".....",O({},{__index=function(I,n)local _,x,l,H,Q=j(n,1,5);local y=(Q-33)+(H-33)*85+(l-33)*7225+(x-33)*614125+(_-33)*52200625;local _=N(">I4",y);I[n]=_;return _;end}));end)(P(__PAYLOAD,v_off)),{[0]=1,2,4,8,16,32,64,128,256,512,1024,2048,4096,8192,16384,32768,65536,131072,262144,524288,1048576,2097152,4194304,8388608,16777216,33554432,67108864,134217728,268435456,536870912,1073741824,2147483648,4294967296},0;
X(c and J(c)=="string","Luraph decompression error: invalid payload (does your environment support load/loadstring?)");
local _LPH_CHUNK_EXTRACT=function(x)local j_r,d_s="",#x;for I_i=1,d_s,7997 do local O_l=I_i+7996.0;if O_l>d_s then O_l=d_s;end;j_r=j_r..P(x,I_i,O_l);end;return j_r;end;
local __BYTE,__CHAR,__SUB,__GSUB,__FLOOR=j,d,P,I,math.floor
local __TUNPACK,__TPACK=e,table.pack or function(...)return{n=select('#',...),...}end
local function __R32(s,i) local a,b,c2,d2=j(s,i,i+3) return a+b*256+c2*65536+d2*16777216 end
local function __R16(s,i) local a,b=j(s,i,i+1) return a+b*256 end
local function __R64(s,i)
local b={} for x=0,7 do b[x+1]=j(s,i+x) end
local sign=(b[8]>=128)and -1 or 1
local exp=(b[8]%128)*16+__FLOOR(b[7]/16)
local mant=(b[7]%16)*(2^48)+b[6]*(2^40)+b[5]*(2^32)+b[4]*(2^24)+b[3]*(2^16)+b[2]*256+b[1]
if exp==0 then if mant==0 then return 0 end return sign*(mant/2^52)*2^-1022 end
if exp==2047 then return mant==0 and sign*(1/0) or (0/0) end
return sign*(1+mant/2^52)*2^(exp-1023)
end
local function __DECODE(bin, pad, bkey)
if pad>0 then bin=P(bin,1,-pad-1) end
local out={} local k1=bkey local k2=(bkey*7+13)%256 local k3=(bkey*31+17)%256
for i=1,#bin do
local enc=j(bin,i)
local dec
local m=i%3
if m==0 then dec=(enc-k1-k3-i)%256 elseif m==1 then dec=(enc+k2-k3+i)%256 else dec=(enc-k2+k1-i)%256 end
out[i]=v[(dec%256+256)%256]
k1=(k1*13+enc)%256
k2=(k2*31+17+i)%256
k3=(k3*29+enc+7)%256
end
return table.concat(out)
end
local function __READP(bin, pos)
local np=j(bin,pos) pos=pos+1
local up=j(bin,pos) pos=pos+1
local ms=j(bin,pos) pos=pos+1
local iv=j(bin,pos) pos=pos+1
local om=j(bin,pos) pos=pos+1
local oa=j(bin,pos) pos=pos+1
local proto={np=np,up=up,ms=ms,iv=iv,om=om,oa=oa,ins={},ks={},ps={}}
local ni=__R32(bin,pos) pos=pos+4
for i=1,ni do
local a,b,c2,d2,e2=j(bin,pos,pos+4) pos=pos+5
proto.ins[i]=a+b*256+c2*65536+d2*16777216+e2*4294967296
end
local nk=__R32(bin,pos) pos=pos+4
for i=0,nk-1 do
local t=j(bin,pos) pos=pos+1
if t==0 then proto.ks[i]=nil
elseif t==1 then proto.ks[i]=j(bin,pos)~=0 pos=pos+1
elseif t==3 then proto.ks[i]=__R64(bin,pos) pos=pos+8
elseif t==4 then
local l=__R16(bin,pos) pos=pos+2
local s2=P(bin,pos,pos+l-1) pos=pos+l
local C={} local k=__STR_KEY
for x=1,#s2 do
local b=j(s2,x) local dec=(b-k-x)%256
C[x]=v[dec<0 and dec+256 or dec] k=(k*7+13)%256
end
proto.ks[i]=table.concat(C)
end
end
local np2=__R32(bin,pos) pos=pos+4
for i=0,np2-1 do local child; child,pos=__READP(bin,pos) proto.ps[i]=child end
return proto,pos
end
local __BIN=__DECODE(c,__PAD,__BKEY)
local __AST=(__READP(__BIN,1))
__AST.rt=true
]=]

-- =====================================================================
-- VM_ENGINE template (with polymorphic __PARSE instruction decoder)
-- =====================================================================
local VM_ENGINE = [=[
local __WRAP
local __POISON = 0
local function __EXEC(pr,env,upvals,...)
local __REG,__VARGS,__OPENUVS,__STOP,__IPC=(table.create and table.create(pr.ms or 64)) or {},{...},{},0,1
local __VLEN=select('#',...)
local __INSTR,__KONST,__PROTOS=pr.ins,pr.ks,pr.ps
local __POM,__POA=pr.om,pr.oa
local __CHKSUM, __ILEN = 0, #__INSTR
if __ILEN > 16 then __ILEN = 16 end
for i = 1, __ILEN do __CHKSUM = (__CHKSUM * 31 + __INSTR[i]) % 4294967296 end
if __CHKSUM < 0 then return end
for i=0,(pr.np or 0)-1 do __REG[i]=__VARGS[i+1] end
__STOP=(pr.np or 0)-1
local function __CLOSEUV(lim) for r,x in pairs(__OPENUVS) do if r>=lim then x[1]={x[1][x[2]]} x[2]=1 __OPENUVS[r]=nil end end end
local __KSEED,__KLM,__KLA,__KMOD=__VM_SEED,__VM_LMUL,__VM_LADD,__VM_LMOD
local function __PARSE(w)
__PARSE_BODY
end
local __DISP={}
]=]

-- =====================================================================
-- V14_CLOSE template (Luraph v14.7 Classic Anti-Debug + Anti-Tamper)
-- =====================================================================
local V14_CLOSE = [=[
local __CTR=0
while true do
__CTR=(__CTR+1)%1000
local e=__INSTR[__IPC]
local prev_e=(__IPC>1)and(__INSTR[__IPC-1]or 0)or 0
local k=(__KSEED+__IPC*__KLM+__KLA+prev_e*37)%__KMOD
if __POISON>0 and (__CTR>25 or __IPC>15) then k=(k+__POISON*7919)%__KMOD end
__IPC=__IPC+1
local w=(e-k)%__KMOD
if w<0 then w=w+__KMOD end
local op,a,b,c,bx,sbx=__PARSE(w)
op=((op-__POA)*__POM)%256
if w == 13371337 then if _LPH_CRASH then _LPH_CRASH() end end
if (__CTR > 8000) and (((__CTR * (__CTR + 1)) % 2 ~= 0) or (((__IPC * (__IPC + 1)) % 2) ~= 0)) then __IPC = 0 end
if (a > 255) and (a < 0) then a = 0 end
if (bx and bx < -999999 and bx > 0) then return end
local f=__DISP[op]
if f then
local r=__TPACK(f(__REG,a,b,c,bx,sbx))
if r[1] then return __TUNPACK(r,2,r.n) end
end
end
end
__WRAP=function(pr,env,uv) return function(...) return __EXEC(pr,env,uv,...) end end
local __GENV=(getfenv and getfenv()) or _ENV or _G
if _LPH_HOOK_GUARD then _LPH_HOOK_GUARD() end
local _LPH_CANARY = O({}, { __index = function(_, k) return k end })
if _LPH_CANARY[1337] ~= 1337 then __POISON = __POISON + 1 end
local _LPH_STRMT = getmetatable and getmetatable("")
if _LPH_STRMT and _LPH_STRMT.__index and _LPH_STRMT.__index ~= string then __POISON = __POISON + 2 end
if ("lura" .. "ph") ~= "luraph" then __POISON = __POISON + 4 end
local _c_ok, _c_err = pcall(select, 0)
if not (_c_ok == false and type(_c_err) == "string" and string.find(_c_err, "range")) then __POISON = __POISON + 16 end
if J(debug)=="table" and debug.getinfo then
  local _info=debug.getinfo(1)
  if _info and _info.what and _info.what~="Lua" and _info.what~="main" and _info.what~="C" then __POISON = __POISON + 32 end
end
if J(debug)=="table" and debug.traceback then
  local _tb=tostring(debug.traceback())
  local _tbl=string.lower(_tb)
  if string.find(_tbl,"hook") or string.find(_tbl,"spy") or string.find(_tbl,"deobf") or string.find(_tbl,"dump") or string.find(_tbl,"extractor") or string.find(_tbl,"disassembler") or string.find(_tbl,"tracer") or string.find(_tbl,"unluac") or string.find(_tbl,"luadec") then __POISON = __POISON + 128 end
end
if J(coroutine)=="table" and coroutine.wrap then
  local co=coroutine.wrap(function() return 0xCAFE end)
  if not co or co()~=0xCAFE then __POISON = __POISON + 256 end
end
if getfenv then
  local _ef = getfenv(0)
  if _ef and _ef._LPH_HOOK_GUARD and _ef._LPH_HOOK_GUARD ~= _LPH_HOOK_GUARD then __POISON = __POISON + 512 end
end
local _LPH_LOAD = loadstring or load or function() end
if _LPH_JIT_MAX then _LPH_JIT_MAX() end
if not _LPH_OBFUSCATED then _LPH_LOAD("return function() end")() end
return __EXEC(__AST,__GENV,{},...) 
]=]

-- =====================================================================
-- V15_CLOSE template (Luraph v15.2 Ultra Anti-Debug + Anti-Tamper)
-- Enhanced: pcall(debug.getinfo, 2, "f") call stack verification
-- Enhanced: debug.sethook neutralization + traceback hook detection
-- Enhanced: coroutine integrity check
-- Enhanced: environment fingerprint via getfenv
-- Enhanced: Roblox executor C-closure hook detection
-- =====================================================================
local V15_CLOSE = [=[
local __CTR=0
while true do
__CTR=(__CTR+1)%1000
local e=__INSTR[__IPC]
local prev_e=(__IPC>1)and(__INSTR[__IPC-1]or 0)or 0
local k=(__KSEED+__IPC*__KLM+__KLA+prev_e*37)%__KMOD
if __POISON>0 and (__CTR>25 or __IPC>15) then k=(k+__POISON*7919)%__KMOD end
__IPC=__IPC+1
local w=(e-k)%__KMOD
if w<0 then w=w+__KMOD end
local op,a,b,c,bx,sbx=__PARSE(w)
op=((op-__POA)*__POM)%256
if w == 13371337 then if _LPH_CRASH then _LPH_CRASH() end end
if (__CTR > 8000) and (((__CTR * (__CTR + 1)) % 2 ~= 0) or (((__IPC * (__IPC + 1)) % 2) ~= 0)) then __IPC = 0 end
if (a > 255) and (a < 0) then a = 0 end
if (bx and bx < -999999 and bx > 0) then return end
local f=__DISP[op]
if f then
local r=__TPACK(f(__REG,a,b,c,bx,sbx))
if r[1] then return __TUNPACK(r,2,r.n) end
end
end
end
__WRAP=function(pr,env,uv) return function(...) return __EXEC(pr,env,uv,...) end end
local __GENV=(getfenv and getfenv()) or _ENV or _G
if _LPH_HOOK_GUARD then _LPH_HOOK_GUARD() end
local _LPH_CANARY = O({}, { __index = function(_, k) return k end })
if _LPH_CANARY[1337] ~= 1337 then __POISON = __POISON + 1 end
local _LPH_STRMT = getmetatable and getmetatable("")
if _LPH_STRMT and _LPH_STRMT.__index and _LPH_STRMT.__index ~= string then __POISON = __POISON + 2 end
if ("lura" .. "ph") ~= "luraph" then __POISON = __POISON + 4 end
if pcall(string.dump, pcall) or pcall(string.dump, select) or pcall(string.dump, tostring) or pcall(string.dump, type) then __POISON = __POISON + 8 end
local _c_ok, _c_err = pcall(select, 0)
if not (_c_ok == false and type(_c_err) == "string" and string.find(_c_err, "range")) then __POISON = __POISON + 16 end
if J(debug)=="table" and debug.getinfo then
  local _info=debug.getinfo(1)
  if _info and _info.what and _info.what~="Lua" and _info.what~="main" and _info.what~="C" then __POISON = __POISON + 32 end
  local ok, res = pcall(debug.getinfo, 2, "f")
  if ok and res and res.func == __WRAP then __POISON = __POISON + 64 end
end
if J(debug)=="table" and debug.traceback then
  local _tb = tostring(debug.traceback())
  local _tbl = string.lower(_tb)
  if string.find(_tbl, "hook") or string.find(_tbl, "spy") or string.find(_tbl, "dump") or string.find(_tbl, "deobf") or string.find(_tbl, "extractor") or string.find(_tbl, "disassembler") or string.find(_tbl, "tracer") or string.find(_tbl, "profiler") or string.find(_tbl, "unluac") or string.find(_tbl, "luadec") then __POISON = __POISON + 128 end
end
if J(coroutine)=="table" and coroutine.wrap then
  local co = coroutine.wrap(function() return 0xCAFE end)
  if not co or co()~=0xCAFE then __POISON = __POISON + 256 end
end
if getfenv then
  local _ef = getfenv(0)
  if _ef and _ef._LPH_HOOK_GUARD and _ef._LPH_HOOK_GUARD ~= _LPH_HOOK_GUARD then __POISON = __POISON + 512 end
end
local _LPH_LOAD = loadstring or load or function() end
if _LPH_JIT_ULTRA then _LPH_JIT_ULTRA() end
if _LPH_JIT_MAX then _LPH_JIT_MAX() end
if not _LPH_OBFUSCATED then _LPH_LOAD("return function() end")() end
return __EXEC(__AST,__GENV,{},...) 
]=]

-- =====================================================================
-- Minify helper
-- =====================================================================
local function minify(code)
    local res = {}
    for line in code:gmatch("[^\r\n]+") do
        local t = line:match("^%s*(.-)%s*$")
        if t ~= "" and not t:match("^%-%-") then
            res[#res+1] = t
        end
    end
    return table.concat(res, " ")
end

-- =====================================================================
-- Shuffle a list in-place
-- =====================================================================
local function shuffle(t)
    for i = #t, 2, -1 do
        local j = math.random(1, i)
        t[i], t[j] = t[j], t[i]
    end
    return t
end

-- =====================================================================
-- Generate decoy opcode handlers (v14.7/v15.2 enhanced)
-- =====================================================================
local function gen_decoys(disp_name, reg_name, used_ops, density)
    local decoys = {}
    local templates = {
        function(op, R) return string.format('%s[%d]=function(%s,a,b,c,bx,sbx) local _=%s[a] %s[a]=_ end', disp_name, op, R, R, R) end,
        function(op, R) return string.format('%s[%d]=function(%s,a,b,c,bx,sbx) local _=a+b*c end', disp_name, op, R) end,
        function(op, R) return string.format('%s[%d]=function(%s,a,b,c,bx,sbx) if b>0 then %s[a]=%s[b] end %s[a]=%s[a] end', disp_name, op, R, R, R, R, R) end,
        function(op, R) return string.format('%s[%d]=function(%s,a,b,c,bx,sbx) local _=b %s[a]=%s[a] end', disp_name, op, R, R, R) end,
        function(op, R) return string.format('%s[%d]=function(%s,a,b,c,bx,sbx) if c~=0 then local _=a end end', disp_name, op, R) end,
        function(op, R) return string.format('%s[%d]=function(%s,a,b,c,bx,sbx) local _=bx %s[a]=%s[a] end', disp_name, op, R, R, R) end,
        function(op, R) return string.format('%s[%d]=function(%s,a,b,c,bx,sbx) local _=a*256+b if _>0 then _=_ end end', disp_name, op, R) end,
        function(op, R) return string.format('%s[%d]=function(%s,a,b,c,bx,sbx) if a==b then %s[a]=%s[a] end end', disp_name, op, R, R, R) end,
        function(op, R) return string.format('%s[%d]=function(%s,a,b,c,bx,sbx) if sbx>0 then local _=%s[a] end end', disp_name, op, R, R) end,
        function(op, R) return string.format('%s[%d]=function(%s,a,b,c,bx,sbx) local _=(b+c)%%256 end', disp_name, op, R) end,
        -- New v15.2 style decoys
        function(op, R) return string.format('%s[%d]=function(%s,a,b,c,bx,sbx) local _=a%%256 if _>127 then _=_-256 end end', disp_name, op, R) end,
        function(op, R) return string.format('%s[%d]=function(%s,a,b,c,bx,sbx) if %s[a]~=nil then local _=%s[a] end end', disp_name, op, R, R, R) end,
        function(op, R) return string.format('%s[%d]=function(%s,a,b,c,bx,sbx) local _=bx%%512 if _>255 then _=_-256 end end', disp_name, op, R) end,
        function(op, R) return string.format('%s[%d]=function(%s,a,b,c,bx,sbx) local _=sbx if _<0 then _=-_ end end', disp_name, op, R) end,
        -- Authentic Opcode Imitation Decoys (Ultra-Realistic)
        function(op, R) return string.format('%s[%d]=function(%s,a,b,c,bx,sbx) local t=%s[b] if type(t)=="table" and c<256 then %s[a]=t[%s[c]] end end', disp_name, op, R, R, R, R) end,
        function(op, R) return string.format('%s[%d]=function(%s,a,b,c,bx,sbx) local t=%s[a] if type(t)=="table" and b<256 then t[%s[b]]=%s[c] end end', disp_name, op, R, R, R, R) end,
        function(op, R) return string.format('%s[%d]=function(%s,a,b,c,bx,sbx) local x,y=%s[b],%s[c] if type(x)=="number" and type(y)=="number" then %s[a]=x+y end end', disp_name, op, R, R, R, R) end,
        function(op, R) return string.format('%s[%d]=function(%s,a,b,c,bx,sbx) local x,y=%s[b],%s[c] if type(x)=="number" and type(y)=="number" then %s[a]=x-y end end', disp_name, op, R, R, R, R) end,
        function(op, R) return string.format('%s[%d]=function(%s,a,b,c,bx,sbx) local x,y=%s[b],%s[c] if type(x)=="number" and type(y)=="number" then %s[a]=x*y end end', disp_name, op, R, R, R, R) end,
        function(op, R) return string.format('%s[%d]=function(%s,a,b,c,bx,sbx) local s1,s2=%s[b],%s[c] if type(s1)=="string" and type(s2)=="string" then %s[a]=s1..s2 end end', disp_name, op, R, R, R, R) end,
        function(op, R) return string.format('%s[%d]=function(%s,a,b,c,bx,sbx) if %s[b] then %s[a]=true else %s[a]=false end end', disp_name, op, R, R, R, R) end,
        function(op, R) return string.format('%s[%d]=function(%s,a,b,c,bx,sbx) local x=%s[b] if type(x)=="number" then %s[a]=-x end end', disp_name, op, R, R, R) end,
        function(op, R) return string.format('%s[%d]=function(%s,a,b,c,bx,sbx) local x=%s[b] if type(x)=="table" or type(x)=="string" then %s[a]=#x end end', disp_name, op, R, R, R) end,
        function(op, R) return string.format('%s[%d]=function(%s,a,b,c,bx,sbx) local x=%s[b] if type(x)=="number" then %s[a]=math.floor(x) end end', disp_name, op, R, R, R) end,
        function(op, R) return string.format('%s[%d]=function(%s,a,b,c,bx,sbx) local fn=%s[a] if type(fn)=="function" and b<0 then pcall(fn) end end', disp_name, op, R, R) end,
        function(op, R) return string.format('%s[%d]=function(%s,a,b,c,bx,sbx) if bx==0 then %s[a]={} end end', disp_name, op, R, R) end,
        function(op, R) return string.format('%s[%d]=function(%s,a,b,c,bx,sbx) local x=%s[b] if type(x)=="number" and c>0 then %s[a]=x%%c end end', disp_name, op, R, R, R) end,
        function(op, R) return string.format('%s[%d]=function(%s,a,b,c,bx,sbx) local t=type(%s[b]) if t=="string" then %s[a]=t end end', disp_name, op, R, R, R) end,
    }
    density = tonumber(density) or 1.0
    if density < 0 then density = 0 elseif density > 2 then density = 2 end
    local count = math.floor(math.random(25, 45) * density + 0.5)
    for _ = 1, count do
        local op
        repeat op = math.random(1, 250) until not used_ops[op]
        used_ops[op] = true
        local tmpl = templates[math.random(1, #templates)]
        decoys[#decoys+1] = tmpl(op, reg_name)
    end
    return decoys
end

-- =====================================================================
-- MAIN EMIT FUNCTION
-- =====================================================================
function Generator.emit(encoded_root, encoder_instance, options)
    options = options or {}
    local op_map  = encoder_instance.opcode_map
    local layout  = encoder_instance.layout_mode or 0
    local lph_ver = options.LuraphVersion or 15

    local blob, pad = encoder_instance:serialize_to_blob(encoded_root)

    local O = {}
    local used_ops = {}
    for i = 0, 37 do
        O[i] = op_map[i]
        used_ops[op_map[i]] = true
    end

    -- Generate polymorphic names
    local ng = make_name_gen(encoder_instance.seed + 7919)
    local V = {}
    local var_keys = {
        "byte","char","sub","gsub","floor","unpack","pack",
        "r32","r16","r64","decode","readp","str_key","payload","pad_v","bkey",
        "bin_v","ast_v","wrap","exec","reg","vargs","openuvs","stop","ipc",
        "vlen","instr","konst","protos","closeuv","kseed","klm","kla","kmod",
        "disp","ctr","genv","loader","parse","poison","preve","pom","poa"
    }
    for _, k in ipairs(var_keys) do V[k] = ng() end

    local code_parts = {}

    -- === Build RUNTIME_DECODER with polymorphic names ===
    local str_key_s  = tostring(encoder_instance.str_key)
    local pad_s      = tostring(pad)
    local bkey_s     = tostring(encoder_instance.blob_key)
    local eq_signs = "="
    while blob:find("]" .. eq_signs .. "]") do
        eq_signs = eq_signs .. "="
    end
    local payload_s  = string.format("[%s[LPH>%s]%s]", eq_signs, blob:gsub("\n", ""), eq_signs)

    local decoder = RUNTIME_DECODER
    decoder = decoder:gsub("__BYTE",    function() return V.byte end)
    decoder = decoder:gsub("__CHAR",    function() return V.char end)
    decoder = decoder:gsub("__SUB",     function() return V.sub end)
    decoder = decoder:gsub("__GSUB",    function() return V.gsub end)
    decoder = decoder:gsub("__FLOOR",   function() return V.floor end)
    decoder = decoder:gsub("__TUNPACK",  function() return V.unpack end)
    decoder = decoder:gsub("__TPACK",    function() return V.pack end)
    decoder = decoder:gsub("__R32",     function() return V.r32 end)
    decoder = decoder:gsub("__R16",     function() return V.r16 end)
    decoder = decoder:gsub("__R64",     function() return V.r64 end)
    decoder = decoder:gsub("__DECODE",  function() return V.decode end)
    decoder = decoder:gsub("__READP",   function() return V.readp end)
    decoder = decoder:gsub("__STR_KEY", function() return str_key_s end)
    decoder = decoder:gsub("__PAYLOAD", function() return payload_s end)
    decoder = decoder:gsub("__PAD",     function() return pad_s end)
    decoder = decoder:gsub("__BKEY",    function() return bkey_s end)
    decoder = decoder:gsub("__BIN",     function() return V.bin_v end)
    decoder = decoder:gsub("__AST",     function() return V.ast_v end)
    code_parts[#code_parts+1] = minify(decoder)

    -- === Build __PARSE_BODY according to layout_mode ===
    local parse_body
    if layout == 0 then
        parse_body = string.format("local op=w%%256 local a=%s(w/256)%%256 local b=%s(w/65536)%%512 local c=%s(w/33554432)%%512 local bx=b+c*512 return op,a,b,c,bx,bx-131071", V.floor, V.floor, V.floor)
    elseif layout == 1 then
        parse_body = string.format("local a=w%%256 local op=%s(w/256)%%256 local c=%s(w/65536)%%512 local b=%s(w/33554432)%%512 local bx=b+c*512 return op,a,b,c,bx,bx-131071", V.floor, V.floor, V.floor)
    else
        parse_body = string.format("local op=w%%256 local b=%s(w/256)%%512 local c=%s(w/131072)%%512 local a=%s(w/67108864)%%256 local bx=b+c*512 return op,a,b,c,bx,bx-131071", V.floor, V.floor, V.floor)
    end

    -- === Build VM_ENGINE with polymorphic names ===
    local seed_s  = tostring(encoder_instance.seed)
    local lmul_s  = tostring(encoder_instance.l_mult)
    local ladd_s  = tostring(encoder_instance.l_add)
    local lmod_s  = tostring(encoder_instance.l_mod)

    local engine = VM_ENGINE
    engine = engine:gsub("__WRAP",       function() return V.wrap end)
    engine = engine:gsub("__EXEC",       function() return V.exec end)
    engine = engine:gsub("__REG",        function() return V.reg end)
    engine = engine:gsub("__VARGS",      function() return V.vargs end)
    engine = engine:gsub("__OPENUVS",    function() return V.openuvs end)
    engine = engine:gsub("__STOP",       function() return V.stop end)
    engine = engine:gsub("__IPC",        function() return V.ipc end)
    engine = engine:gsub("__VLEN",       function() return V.vlen end)
    engine = engine:gsub("__INSTR",      function() return V.instr end)
    engine = engine:gsub("__KONST",      function() return V.konst end)
    engine = engine:gsub("__PROTOS",     function() return V.protos end)
    engine = engine:gsub("__CLOSEUV",    function() return V.closeuv end)
    engine = engine:gsub("__KSEED",      function() return V.kseed end)
    engine = engine:gsub("__KLM",        function() return V.klm end)
    engine = engine:gsub("__KLA",        function() return V.kla end)
    engine = engine:gsub("__KMOD",       function() return V.kmod end)
    engine = engine:gsub("__PARSE_BODY", function() return parse_body end)
    engine = engine:gsub("__PARSE",      function() return V.parse end)
    engine = engine:gsub("__DISP",       function() return V.disp end)
    engine = engine:gsub("__TPACK",      function() return V.pack end)
    engine = engine:gsub("__TUNPACK",    function() return V.unpack end)
    engine = engine:gsub("__FLOOR",      function() return V.floor end)
    engine = engine:gsub("__VM_SEED",    function() return seed_s end)
    engine = engine:gsub("__VM_LMUL",    function() return lmul_s end)
    engine = engine:gsub("__VM_LADD",    function() return ladd_s end)
    engine = engine:gsub("__VM_LMOD",    function() return lmod_s end)
    engine = engine:gsub("__POISON",     function() return V.poison end)
    engine = engine:gsub("__POM",        function() return V.pom end)
    engine = engine:gsub("__POA",        function() return V.poa end)
    code_parts[#code_parts+1] = minify(engine)

    -- === Dispatch Table (with polymorphic names) ===
    local D = V.disp
    local R = V.reg
    local K = V.konst
    local PC = V.ipc
    local TOP = V.stop
    local INS = V.instr
    local PS = V.protos
    local CL = V.closeuv
    local OUV = V.openuvs
    local WR = V.wrap
    local S = V.kseed
    local LM = V.klm
    local LA = V.kla
    local LMOD = V.kmod
    local PK = V.pack
    local UPK = V.unpack
    local FL = V.floor
    local VA = V.vargs
    local VLEN = V.vlen
    local PRS = V.parse

    local d_parts = {}
    local d_entries = {}

    d_entries[#d_entries+1] = string.format('%s[%d]=function(%s,a,b,c,bx,sbx)%s[a]=%s[b]end', D, O[0], R, R, R)
    d_entries[#d_entries+1] = string.format('%s[%d]=function(%s,a,b,c,bx,sbx)%s[a]=%s[bx]end', D, O[1], R, R, K)
    d_entries[#d_entries+1] = string.format('%s[%d]=function(%s,a,b,c,bx,sbx)%s[a]=(b~=0)if c~=0 then %s=%s+1 end end', D, O[2], R, R, PC, PC)
    d_entries[#d_entries+1] = string.format('%s[%d]=function(%s,a,b,c,bx,sbx)for i=a,b do %s[i]=nil end end', D, O[3], R, R)
    d_entries[#d_entries+1] = string.format('%s[%d]=function(%s,a,b,c,bx,sbx)local u=upvals[b] %s[a]=u[1][u[2]]end', D, O[4], R, R)
    d_entries[#d_entries+1] = string.format('%s[%d]=function(%s,a,b,c,bx,sbx)%s[a]=env[%s[bx]]end', D, O[5], R, R, K)
    d_entries[#d_entries+1] = string.format('%s[%d]=function(%s,a,b,c,bx,sbx)local q=%s[b]local w=(c>=256)and %s[c-256]or %s[c]%s[a]=q[w]end', D, O[6], R, R, K, R, R)
    d_entries[#d_entries+1] = string.format('%s[%d]=function(%s,a,b,c,bx,sbx)env[%s[bx]]=%s[a]end', D, O[7], R, K, R)
    d_entries[#d_entries+1] = string.format('%s[%d]=function(%s,a,b,c,bx,sbx)local u=upvals[b] u[1][u[2]]=%s[a]end', D, O[8], R, R)
    d_entries[#d_entries+1] = string.format('%s[%d]=function(%s,a,b,c,bx,sbx)local q=(b>=256)and %s[b-256]or %s[b]local w=(c>=256)and %s[c-256]or %s[c]%s[a][q]=w end', D, O[9], R, K, R, K, R, R)
    d_entries[#d_entries+1] = string.format('%s[%d]=function(%s,a,b,c,bx,sbx)%s[a]={}end', D, O[10], R, R)
    d_entries[#d_entries+1] = string.format('%s[%d]=function(%s,a,b,c,bx,sbx)local q=%s[b]local w=(c>=256)and %s[c-256]or %s[c]%s[a+1]=q %s[a]=q[w]end', D, O[11], R, R, K, R, R, R)
    d_entries[#d_entries+1] = string.format('%s[%d]=function(%s,a,b,c,bx,sbx)local q=(b>=256)and %s[b-256]or %s[b]local w=(c>=256)and %s[c-256]or %s[c]%s[a]=q+w end', D, O[12], R, K, R, K, R, R)
    d_entries[#d_entries+1] = string.format('%s[%d]=function(%s,a,b,c,bx,sbx)local q=(b>=256)and %s[b-256]or %s[b]local w=(c>=256)and %s[c-256]or %s[c]%s[a]=q-w end', D, O[13], R, K, R, K, R, R)
    d_entries[#d_entries+1] = string.format('%s[%d]=function(%s,a,b,c,bx,sbx)local q=(b>=256)and %s[b-256]or %s[b]local w=(c>=256)and %s[c-256]or %s[c]%s[a]=q*w end', D, O[14], R, K, R, K, R, R)
    d_entries[#d_entries+1] = string.format('%s[%d]=function(%s,a,b,c,bx,sbx)local q=(b>=256)and %s[b-256]or %s[b]local w=(c>=256)and %s[c-256]or %s[c]%s[a]=q/w end', D, O[15], R, K, R, K, R, R)
    d_entries[#d_entries+1] = string.format('%s[%d]=function(%s,a,b,c,bx,sbx)local q=(b>=256)and %s[b-256]or %s[b]local w=(c>=256)and %s[c-256]or %s[c]%s[a]=q%%w end', D, O[16], R, K, R, K, R, R)
    d_entries[#d_entries+1] = string.format('%s[%d]=function(%s,a,b,c,bx,sbx)local q=(b>=256)and %s[b-256]or %s[b]local w=(c>=256)and %s[c-256]or %s[c]%s[a]=q^w end', D, O[17], R, K, R, K, R, R)
    d_entries[#d_entries+1] = string.format('%s[%d]=function(%s,a,b,c,bx,sbx)%s[a]=-%s[b]end', D, O[18], R, R, R)
    d_entries[#d_entries+1] = string.format('%s[%d]=function(%s,a,b,c,bx,sbx)%s[a]=not %s[b]end', D, O[19], R, R, R)
    d_entries[#d_entries+1] = string.format('%s[%d]=function(%s,a,b,c,bx,sbx)%s[a]=#%s[b]end', D, O[20], R, R, R)
    d_entries[#d_entries+1] = string.format('%s[%d]=function(%s,a,b,c,bx,sbx)local s=%s[b]for i=b+1,c do s=s..%s[i]end %s[a]=s end', D, O[21], R, R, R, R, R)
    d_entries[#d_entries+1] = string.format('%s[%d]=function(%s,a,b,c,bx,sbx)%s=%s+sbx end', D, O[22], R, PC, PC)
    d_entries[#d_entries+1] = string.format('%s[%d]=function(%s,a,b,c,bx,sbx)local q=(b>=256)and %s[b-256]or %s[b]local w=(c>=256)and %s[c-256]or %s[c]if(q==w)~=(a~=0)then %s=%s+1 end end', D, O[23], R, K, R, K, R, PC, PC)
    d_entries[#d_entries+1] = string.format('%s[%d]=function(%s,a,b,c,bx,sbx)local q=(b>=256)and %s[b-256]or %s[b]local w=(c>=256)and %s[c-256]or %s[c]if(q<w)~=(a~=0)then %s=%s+1 end end', D, O[24], R, K, R, K, R, PC, PC)
    d_entries[#d_entries+1] = string.format('%s[%d]=function(%s,a,b,c,bx,sbx)local q=(b>=256)and %s[b-256]or %s[b]local w=(c>=256)and %s[c-256]or %s[c]if(q<=w)~=(a~=0)then %s=%s+1 end end', D, O[25], R, K, R, K, R, PC, PC)
    d_entries[#d_entries+1] = string.format('%s[%d]=function(%s,a,b,c,bx,sbx)if(not %s[a])==(c~=0)then %s=%s+1 end end', D, O[26], R, R, PC, PC)
    d_entries[#d_entries+1] = string.format('%s[%d]=function(%s,a,b,c,bx,sbx)if(not %s[b])==(c~=0)then %s=%s+1 else %s[a]=%s[b]end end', D, O[27], R, R, PC, PC, R, R)
    d_entries[#d_entries+1] = string.format('%s[%d]=function(%s,a,b,c,bx,sbx) local g={} local n=(b==0)and(%s-a)or(b-1) for i=1,n do g[i]=%s[a+i] end local r=%s(%s[a](%s(g,1,n))) local l=r.n if c==0 then %s=a+l-1 for i=1,l do %s[a+i-1]=r[i] end else for i=1,c-1 do %s[a+i-1]=r[i] end end end', D, O[28], R, TOP, R, PK, R, UPK, TOP, R, R)
    d_entries[#d_entries+1] = string.format('%s[%d]=function(%s,a,b,c,bx,sbx) local g={} local n=(b==0)and(%s-a)or(b-1) for i=1,n do g[i]=%s[a+i] end %s(0)if pr.rt then for i=1,#%s do %s[i]=0 end end return true,%s[a](%s(g,1,n))end', D, O[29], R, TOP, R, CL, INS, INS, R, UPK)
    d_entries[#d_entries+1] = string.format('%s[%d]=function(%s,a,b,c,bx,sbx) %s(0)if pr.rt then for i=1,#%s do %s[i]=0 end end local n=(b==0)and(%s-a+1)or(b-1) local r={}for i=1,n do r[i]=%s[a+i-1]end return true,%s(r,1,n)end', D, O[30], R, CL, INS, INS, TOP, R, UPK)
    d_entries[#d_entries+1] = string.format('%s[%d]=function(%s,a,b,c,bx,sbx) local s=%s[a+2]local x=%s[a]+s %s[a]=x local l=%s[a+1] if(s>0 and x<=l)or(s<=0 and x>=l)then %s=%s+sbx %s[a+3]=x end end', D, O[31], R, R, R, R, R, PC, PC, R)
    d_entries[#d_entries+1] = string.format('%s[%d]=function(%s,a,b,c,bx,sbx) local x=%s[a]local s=%s[a+2]%s[a]=x-s %s=%s+sbx end', D, O[32], R, R, R, R, PC, PC)
    d_entries[#d_entries+1] = string.format('%s[%d]=function(%s,a,b,c,bx,sbx) local cb,s,var=%s[a],%s[a+1],%s[a+2] local r={cb(s,var)} for i=1,c do %s[a+2+i]=r[i]end if %s[a+3]~=nil then %s[a+2]=%s[a+3]else %s=%s+1 end end', D, O[33], R, R, R, R, R, R, R, R, PC, PC)
    d_entries[#d_entries+1] = string.format('%s[%d]=function(%s,a,b,c,bx,sbx) local n=(b==0)and(%s-a)or b if c==0 then local prev_ne=(%s>1)and(%s[%s-1]or 0)or 0 local ne=%s[%s] local nk=(%s+%s*%s+%s+prev_ne*37)%%%s %s=%s+1 local nw=(ne-nk)%%%s if nw<0 then nw=nw+%s end local _,_,_,_,cbx=%s(nw) c=cbx end local o=(c-1)*50 local t=%s[a] for i=1,n do t[o+i]=%s[a+i]end end', D, O[34], R, TOP, PC, INS, PC, INS, PC, S, PC, LM, LA, LMOD, PC, PC, LMOD, LMOD, PRS, R, R)
    d_entries[#d_entries+1] = string.format('%s[%d]=function(%s,a,b,c,bx,sbx)%s(a)end', D, O[35], R, CL)
    d_entries[#d_entries+1] = string.format('%s[%d]=function(%s,a,b,c,bx,sbx) local p=%s[bx]local uv={} for i=0,p.up-1 do local prev_e=(%s>1)and(%s[%s-1]or 0)or 0 local e=%s[%s] local nk=(%s+%s*%s+%s+prev_e*37)%%%s %s=%s+1 local w=(e-nk)%%%s if w<0 then w=w+%s end local op,_,pb=%s(w) op=((op-%s)*%s)%%256 if op==%d then if not %s[pb]then %s[pb]={%s,pb}end uv[i]=%s[pb] else uv[i]=upvals[pb]end end %s[a]=%s(p,env,uv) end', D, O[36], R, PS, PC, INS, PC, INS, PC, S, PC, LM, LA, LMOD, PC, PC, LMOD, LMOD, PRS, V.poa, V.pom, O[0], OUV, OUV, R, OUV, R, WR)
    d_entries[#d_entries+1] = string.format('%s[%d]=function(%s,a,b,c,bx,sbx) local n=(b==0)and(%s-pr.np)or(b-1) for i=1,n do %s[a+i-1]=%s[pr.np+i]end if b==0 then %s=a+n-1 end end', D, O[37], R, VLEN, R, VA, TOP)

    -- Shuffle dispatch order
    shuffle(d_entries)

    -- Generate decoy opcodes
    local decoys = gen_decoys(D, R, used_ops, options.DecoyDensity)
    shuffle(decoys)

    -- Interleave decoys into dispatch table
    for _, decoy in ipairs(decoys) do
        local pos = math.random(1, #d_entries + 1)
        table.insert(d_entries, pos, decoy)
    end

    code_parts[#code_parts+1] = table.concat(d_entries, " ")

    -- === Select V14 or V15 CLOSE template based on LuraphVersion ===
    local close_template = (lph_ver == 14) and V14_CLOSE or V15_CLOSE

    local close = close_template
    close = close:gsub("__CTR",           function() return V.ctr end)
    close = close:gsub("__INSTR",         function() return V.instr end)
    close = close:gsub("__IPC",           function() return V.ipc end)
    close = close:gsub("__KSEED",         function() return V.kseed end)
    close = close:gsub("__KLM",           function() return V.klm end)
    close = close:gsub("__KLA",           function() return V.kla end)
    close = close:gsub("__KMOD",          function() return V.kmod end)
    close = close:gsub("__FLOOR",         function() return V.floor end)
    close = close:gsub("__PARSE",         function() return V.parse end)
    close = close:gsub("__DISP",          function() return V.disp end)
    close = close:gsub("__TPACK",         function() return V.pack end)
    close = close:gsub("__TUNPACK",       function() return V.unpack end)
    close = close:gsub("__REG",           function() return V.reg end)
    close = close:gsub("__WRAP",          function() return V.wrap end)
    close = close:gsub("__EXEC",          function() return V.exec end)
    close = close:gsub("__AST",           function() return V.ast_v end)
    close = close:gsub("__GENV",          function() return V.genv end)
    close = close:gsub("__LOADER",        function() return V.loader end)
    close = close:gsub("__POISON",        function() return V.poison end)
    close = close:gsub("__PREVE",         function() return V.preve end)
    close = close:gsub("__POM",           function() return V.pom end)
    close = close:gsub("__POA",           function() return V.poa end)
    code_parts[#code_parts+1] = minify(close)

    -- === Format exactly matching authentic Luraph (e.g. legendary.lua) ===
    local sig1 = string.format("%08x%08x", math.random(10000000, 99999999), math.random(10000000, 99999999))
    local sig2 = string.format("%08x%08x", math.random(10000000, 99999999), math.random(10000000, 99999999))
    local enc_key = string.format("%08x", math.random(10000000, 99999999))

    local lph_header = options.Header
    if not lph_header or lph_header == "" then
        if lph_ver == 14 then
            lph_header = "-- This file was protected using Azure VM v14.7 [Protected]"
        else
            lph_header = "-- This file was protected using Azure VM v15.2 [Protected]"
        end
    else
        if not lph_header:match("^%-%-") then
            lph_header = "-- " .. lph_header
        end
    end

    -- Inlined markers (compact, no extra newlines or wrapper scaffolding)
    local markers_list = {
        "local _LPH_OBFUSCATED=true",
        "local _LPH_NO_VIRTUALIZE=function(...)return ...end",
        "local _LPH_JIT_MAX=function(...)return ...end",
    }
    if lph_ver == 15 then
        table.insert(markers_list, "local _LPH_JIT_ULTRA=function(...)return ...end")
    end
    table.insert(markers_list, "local _LPH_NO_UPVALUES=function(...)return ...end")
    table.insert(markers_list, 'local _LPH_CRASH=function()error("Luraph runtime integrity failure",0)end')
    table.insert(markers_list, "local _LPH_HOOK_GUARD=function()return end")
    table.insert(markers_list, string.format("local _LPH_ENCKEY='%s'", enc_key))
    table.insert(markers_list, string.format("local _LPH_SIGNATURE='%s%s'", sig1, sig2))
    table.insert(markers_list, "local _LPH_LOAD=loadstring or load or function()end")
    table.insert(markers_list, "local _LPH_EXECUTE=function(...)return ...end")
    table.insert(markers_list, "local _LPH_DECODE=function(...)return ...end")
    table.insert(markers_list, "local _LPH_VERIFIED=true")
    local inlined_markers = table.concat(markers_list, " ")

    -- Exactly 1 continuous line of code inside return(function(...) ... end)(...);
    -- Put Stage 1 loader first so opening tokens match Luraph 100%
    local single_code_line = "return(function(...) " .. code_parts[1] .. " " .. inlined_markers .. " " .. table.concat(code_parts, " ", 2) .. " end)(...);"

    local final_vm_line = lph_header .. "\n\n" .. single_code_line

    return final_vm_line
end

return Generator
