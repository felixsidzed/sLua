--!strict
--!optimize 2

local lstate = require("lstate")

function luaF_newLclosure(L: lstate.lua_State, nelems: number, e: lstate.LuaTable, p: lstate.Proto): lstate.Closure
	local c: lstate.Closure = {
		marked = bit32.band(L.global.currentwhite, 7),
		tt = 0,
		memcat = L.activememcat,

		isC = false,
		env = e,
		nupvalues = nelems,
		stacksize = p.maxstacksize,
		preload = false,
		l = {
			p = p,
			uprefs = table.create(nelems)
		},
		gclist = {}
	}
	assert(c.l)
	for i = 1, nelems do
		c.l.uprefs[i] = lstate.luaO_nilobject
	end
	return c
end

return {
	luaF_newLclosure :: any
}
