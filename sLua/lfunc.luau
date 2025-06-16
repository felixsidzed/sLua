--!strict
--!optimize 2

local lstate = require("lstate")

type lua_State = lstate.lua_State
type LuaTable = lstate.LuaTable
type Proto = lstate.Proto
type Closure = lstate.Closure

local luaO_nilobject = lstate.luaO_nilobject

function luaF_newLclosure(L: lua_State, nelems: number, e: LuaTable, p: Proto): Closure
	local c: Closure = {
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
		c.l.uprefs[i] = luaO_nilobject
	end
	return c
end

return {
	luaF_newLclosure :: any
}
