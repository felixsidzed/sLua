--!strict
--!optimize 2

local lstate = require("lstate.luau")
local LUA = require("lconf.luau")
local typehelp = require("ltypeh.luau")
local lvm: any = {}

export type StackWatchFunction = (L: lstate.lua_State, idx: number, value: lstate.StkId?) -> ()

local stackWriteHooks: { [lstate.lua_State]: StackWatchFunction } = {}

local function setsvalue(L: lstate.lua_State, idx: number, value: lstate.StkId?)
	local changed = L.stack[idx + 1] == nil

	L.stack[idx + 1] = value :: any

	if changed then
		local hook = stackWriteHooks[L]
		if hook then
			hook(L, idx + 1, value)
		end
	end
end

local function getsvalue(L: lstate.lua_State, idx: number)
	return L.stack[idx]
end

function watchstack(L: lstate.lua_State, callback: StackWatchFunction)
	stackWriteHooks[L] = callback
end

function unwatchstack(L: lstate.lua_State)
	stackWriteHooks[L] = nil
end

local function pseudo2addr(L: lstate.lua_State, idx: number): lstate.StkId
	if idx == LUA.GLOBALSINDEX then
		L.global.pseudotemp = L.gt
		return L.global.pseudotemp
	elseif idx == LUA.ENVIRONINDEX then
		L.global.pseudotemp = getcurrenv(L)
		return L.global.pseudotemp
	end
	return 0
end

local function index2addr(L: lstate.lua_State, idx: number): lstate.StkId
	if idx > 0 then
		local o: lstate.TValue = getsvalue(L, L.base + idx)
		
		return o
	elseif idx > LUA.REGISTRYINDEX then
		return getsvalue(L, L.top + idx + 1)
	else
		return pseudo2addr(L, idx)
	end
end

function getglobal(L: lstate.lua_State, name: string): lstate.TValue
	return getfield(L, LUA.GLOBALSINDEX, name)
end

function setglobal(L: lstate.lua_State, name: string)
	setfield(L, LUA.GLOBALSINDEX, name)
end

function getfield(L: lstate.lua_State, idx: number, k: string): string
	local t: lstate.StkId = index2addr(L, idx)

	setsvalue(L, L.top, (t :: { [any]: any })[k])
	L.top += 1
	return type(L.stack[L.top - 1])
end

function setfield(L: lstate.lua_State, idx: number, k: string)
	local t: any = index2addr(L, idx) 

	t[k] = getsvalue(L, L.top)
	setsvalue(L, L.top - 1, nil)
	L.top -= 1
end

function pushstring(L: lstate.lua_State, str: string)
	setsvalue(L, L.top, str)
	L.top += 1
end

function pushfstring(L: lstate.lua_State, str: string, ...)
	pushstring(L, string.format(str, ...))
end

function pushinteger(L: lstate.lua_State, num: number)
	setsvalue(L, L.top, num)
	L.top += 1
end

function pushboolean(L: lstate.lua_State, b: boolean)
	setsvalue(L, L.top, b)
	L.top += 1
end

function pushvalue(L: lstate.lua_State, idx: number)
	local o: lstate.StkId = index2addr(L, idx)
	setsvalue(L, L.top, o)
	L.top += 1
end

function pushnil(L: lstate.lua_State)
	--setsvalue(L, L.top, LUA.NILOBJ)
	setsvalue(L, L.top, nil)
	L.top += 1
end

function gettop(L: lstate.lua_State)
	return L.top - L.base
end

function settop(L: lstate.lua_State, idx: number)
	if idx >= 0 then
		while L.top < L.base + idx do
			L.top += 1
			L.stack[L.top] = nil
		end
		
		for i = L.base + idx + 1, L.top do
			L.stack[i] = nil
		end

		L.top = L.base + idx
	else
		L.top += idx + 1
	end
end

function newtable(L: lstate.lua_State)
	createtable(L, 0, 0)
end

function createtable(L: lstate.lua_State, narray: number, nrec: number)
	setsvalue(L, L.top, table.create(narray))
	L.top += 1
end

function settable(L: lstate.lua_State, idx: number)
	local t: any = index2addr(L, idx)
	local key: string = getsvalue(L, L.top - 1) :: string
	local value: lstate.StkId = getsvalue(L, L.top) :: lstate.StkId

	t[key] = value
	L.top -= 2
	setsvalue(L, L.top, nil)
	setsvalue(L, L.top + 1, nil)
end

function gettable(L: lstate.lua_State, idx: number)
	local t: any = index2addr(L, idx)
	local key: string = getsvalue(L, L.top) :: string

	setsvalue(L, L.top - 1, nil)
	setsvalue(L, L.top + idx, t[key])
	L.top -= 1
end

function lua_tostring(L: lstate.lua_State, idx: number)
	return tostring(index2addr(L, idx))
end

function tointeger(L: lstate.lua_State, idx: number)
	return tonumber(index2addr(L, idx))
end

function toboolean(L: lstate.lua_State, idx: number)
	return if index2addr(L, idx) == 0 then false else true
end

function getcurrenv(L: lstate.lua_State): { [string]: any }
	if L.ci == L.base_ci then
		return L.gt
	else
		return L.ci.func.env
	end
end

function pushcfunction(L: lstate.lua_State, func: lstate.lua_CFunction, debugname: string)
	pushcclosurek(L, func, debugname, 0, nil)
end

function pushcclosurek(L: lstate.lua_State, func: lstate.lua_CFunction, debugname: string, nup: number, cont: lstate.lua_Continuation?)
	local cl: lstate.lua_Closure = newcclosure(L, nup, getcurrenv(L));
	(cl.c :: lstate.CClosure).f = func;
	(cl.c :: lstate.CClosure).cont = cont;
	(cl.c :: lstate.CClosure).debugname = debugname;
	(cl.c :: lstate.CClosure).upvals = {}

	while nup ~= 0 do
		(cl.c :: lstate.CClosure).upvals[nup] = getsvalue(L, L.top + nup)
		nup -= 1
	end

	setsvalue(L, L.top, cl)
	L.top += 1
end

function newcclosure(L: lstate.lua_State, nup: number, env: { [string]: any }): lstate.lua_Closure
	-- OMG TYPE CHECK BYPASS V2 OMG OMG
	local cl: lstate.lua_Closure = {} :: any
	cl.isC = true
	cl.env = env
	cl.safeenv = false
	cl.nupvalues = nup
	cl.stacksize = LUA.MINSTACK
	cl.preload = 0
	-- WOAH WOAH WOAH STOP BYPASSING TYPE CHECK
	cl.c = {} :: any
	cl.l = nil
	return cl
end

function call(L: lstate.lua_State, nargs: number, nresults: number)
	if luau_precall(L, nargs, nresults) == LUA.PCRLUA then
		L.ci.flags = bit32.bor(L.ci.flags, LUA.CALLINFO_RETURN)

		lvm.execute(L)
	end

	if nresults == LUA.MULTRET then
		L.ci.top = L.top
	end
end

function luau_precall(L: lstate.lua_State, nargs: number, nresults: number)
	-- omg pointer real
	local pFunc = L.top - nargs

	local func: lstate.lua_Closure = getsvalue(L, pFunc) :: lstate.lua_Closure
	assert(typehelp.luaT_isclosure(func), "attempt to call a non-closure value", 2)

	L.cip = L.ci
	L.ci = {
		func = func,
		base = L.top - nargs,
		top = L.top + func.stacksize,
		savedpc = {},
		flags = 0,
		nresults = nresults
	}
	L.base = L.ci.base

	if func.isC then
		local c: lstate.CClosure = func.c :: lstate.CClosure
		local n = c.f(L)
		if n < 0 then
			return LUA.PCRYIELD
		end

		-- copy return values into parent stack (but only up to nresults!), fill the rest with nil
        -- TODO: it might be worthwhile to handle the case when nresults==b explicitly?
		local vali = L.top - n
		local valend = L.top

		local i = nresults
		while i ~= 0 and vali < valend do
			pFunc += 1
			vali += 1
			setsvalue(L, pFunc, L.stack[vali])
			
			i -= 1
		end
		while i > 0 do
			setsvalue(L, pFunc, nil)
			pFunc += 1
			i -= 1
		end

		L.ci = L.cip
		L.base = L.cip.base
		L.top = pFunc + 1

		return LUA.PCRC
	else
		local p: lstate.Proto = (func.l :: lstate.LClosure).p

		local argi = L.top
		local argend = L.base + p.numparams
		while argi < argend do
			argi += 1
			setsvalue(L, pFunc, nil)
		end
		L.top = if p.is_vararg then argi else L.ci.top

		L.ci.savedpc = p.code

		return LUA.PCRLUA
	end
end

function pop(L: lstate.lua_State, n: number)
	settop(L, -(n)-1)
	for i = 0, n do
		setsvalue(L, L.top + i, nil)
	end
end

function clonefunction(L: lstate.lua_State, idx: number)
	local o: lstate.lua_Closure = index2addr(L, idx) :: lstate.lua_Closure
	setsvalue(L, L.top, table.clone(o))
end

local lapif: { (L: lstate.lua_State, ...any) -> ...any } = {
	getglobal,
	setglobal,

	pushstring,
	pushfstring,
	pushinteger,
	pushboolean,
	pushvalue,
	pushnil,

	gettop,
	settop,

	pop,

	newtable,
	createtable,
	settable,
	gettable,

	lua_tostring,
	tointeger,
	toboolean,

	pushcfunction,
	pushcclosurek,
	newcclosure,

	clonefunction,

	call,
	luau_precall,

	watchstack,
	unwatchstack
}
local lapi = {}

for _, f in ipairs(lapif) do
	lapi[debug.info(f, "n"):gsub("lua_", "")] = f
end

lapi._setsvalue = setsvalue
lapi._init = function(lvmModule)
	lvm = lvmModule
end

return lapi
