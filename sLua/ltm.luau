--!strict
--!optimize 2

local lstate = require("lstate")
local luaH = require("ltable")

type lua_State = lstate.lua_State
type LuaTable = lstate.LuaTable
type TValue = lstate.TValue
type TString = lstate.TString

function luaT_gettm(events: LuaTable, event: number, ename: TString): TValue?
	local tm: TValue = luaH[3](events, ename)
    assert(event <= 8) -- TM_EQ
    if tm.tt == nil then -- no tag method?
		events.tmcache = bit32.bor(events.tmcache, bit32.lshift(1, event))
        return nil
    else
        return tm
	end
end

function fasttm(L: lua_State, et: LuaTable, e: number): TValue?
	return if bit32.band(et.tmcache, bit32.lshift(1, e)) then nil else luaT_gettm(et, e, L.global.tmname[e])
end

return {
	luaT_gettm :: any,
	fasttm
}
