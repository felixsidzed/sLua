--!strict
--!optimize 2

local lvm = require("lvm")
local lgc = require("lgc")
local ldebug = require("ldebug")
local lstate = require("lstate")

type ptrdiff_t = { any }

local function luau_precall(L: lstate.lua_State, func: number, nresults: number)
	if L.stack[func].tt ~= 7 then
		error("__call not supported yet")
	end

	local ccl: lstate.Closure = (L.stack[func].value.gc :: lstate.GCObject).cl :: lstate.Closure

	L.cip += 1
	L.ci[L.cip] = {
		func = ccl,
		pfunc = func,
		base = func + 1,
		top = L.top + ccl.stacksize,
		savedpc = 1,
		flags = 0,
		nresults = nresults
	}
	local ci = L.ci[L.cip]

	L.base = ci.base
	-- Note: L->top is assigned externally

	--assert(ci.top <= L.stack_last)

	if not ccl.isC then
		local p: lstate.Proto = (ccl.l :: any).p

		-- fill unused parameters with nil
		local argi: number = L.top
		local argend: number = L.base + p.numparams
		while argi < argend do
			L.stack[argi] = lstate.luaO_nilobject
			argi += 1
		end
		L.top = if p.is_vararg then argi else ci.top

		ci.savedpc = 1

		return 0
	else
		local cfunc: (L: lstate.lua_State) -> number = (ccl.c :: any).f
		local n: number = cfunc(L)

		-- yield
		if n < 0 then
			return 2
		end

		-- ci is our callinfo, cip is our parent
		--local ci: lstate.CallInfo = L.ci[L.cip]
		local cip: lstate.CallInfo = L.ci[L.cip - 1]

		-- copy return values into parent stack (but only up to nresults!), fill the rest with nil
		-- TODO: it might be worthwhile to handle the case when nresults==b explicitly?
		local res: number = ci.pfunc
		local vali: number = L.top - n
		local valend: number = L.top

		local i: number = nresults
		while i ~= 0 and vali < valend do
			res += 1
			vali += 1
			L.stack[res] = L.stack[vali]
			i -= 1
		end
		while i > 0 do
			res += 1
			L.stack[res] = lstate.luaO_nilobject
			i -= 1
		end

		-- pop the stack frame
		L.cip -= 1
		L.base = cip.base
		L.top = res

		return 1
	end
end

function lua_call(L: lstate.lua_State, nargs: number, nresults: number)
	local func: number
	assert(nargs + 1 <= L.top - L.base)
	assert(L.status == 0)
	assert(nresults == -1 or (L.ci[L.cip].top - L.top >= nresults - nargs))
	func = L.top - (nargs + 1)

	if L.nCcalls + 1 >= 200 then
		local hardlimit: number = 225

		if L.nCcalls == 200 then
			ldebug[1](L, "C stack overflow")
		elseif L.nCcalls >= hardlimit then
			error("LUA_ERRERR")
		end
	end

	local old_func: ptrdiff_t = { func, L.stack[func] }

	if luau_precall(L, func, nresults) == 0 then
		L.ci[L.cip].flags = bit32.bor(L.ci[L.cip].flags, 1) -- luau_execute will stop after returning from the stack frame

		local oldactive: boolean = L.isactive
		L.isactive = true
		--luaC_threadbarrier(L)

		lvm[2](L) -- call it

		L.isactive = oldactive
	end

	if nresults ~= -1 then
		L.top = old_func[1] + nresults
	end

	L.nCcalls -= 1
	lgc.luaC_checkGC(L)

	if nresults == -1 and L.top >= L.ci[L.cip].top then
		L.ci[L.cip].top = L.top
	end
end

return {
	lua_call = lua_call,
	--
}
