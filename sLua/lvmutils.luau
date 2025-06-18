--!strict
--!optimize 2

local lstate = require("lstate")
local luaH = require("ltable")
local ltm = require("ltm")
local ldebug = require("ldebug")

type lua_State = lstate.lua_State
type TValue = lstate.TValue
type GCObject = lstate.GCObject
type LuaTable = lstate.LuaTable

local luaO_nilobject = lstate.luaO_nilobject

function luaV_gettable(L: lua_State, t: TValue, key: TValue, val: number): ()
	for loop=0,100 do -- MAXTAGLOOP
		local tm: TValue?
		if t.tt == 6 then -- `t' is a table?
			local h: LuaTable = (t.value.gc :: GCObject).h :: LuaTable

			local res: TValue = luaH[2](h, key) -- do a primitive get

			if res ~= luaO_nilobject then
				--L.cachedslot = gval2slot(h, res) -- TODO
			end

			-- result is not nil?
			-- or no TM?
			tm = ltm[2](L, h.metatable, 0)
			if res.tt ~= 0 or not tm then
				L.stack[val] = res
				return
			end
			-- t isn't a table, so see if it has an INDEX meta-method to look up the key with
		else
			tm = assert(false, "luaT_gettmbyobj(L, t, TM_INDEX)") :: any
			if not tm or tm.tt == 0 then
				ldebug[2](L, t, key)
			end
		end
		if tm and tm.tt == 7 then
			assert(false, "callTMres(L, val, tm, t, key)")
			return
		end
		t = assert(tm) -- else repeat with `tm'
	end
	ldebug[1](L, "'__index' chain too long; possible loop")
end

function luaV_settable(L: lua_State, t: TValue, key: TValue, val: number): ()
	local temp: TValue
	for loop=0,100 do -- MAXTAGLOOP
        local tm: TValue
        if t.tt == 6 then -- `t' is a table?
            local h: LuaTable = (t.value.gc :: GCObject).h :: LuaTable

            local oldval: TValue = luaH[2](h, key) -- do a primitive get

            -- should we assign the key? (if key is valid or __newindex is not set)
			tm = ltm[2](L, h.metatable, 1)
			if oldval.tt ~= 0 or not tm then
                if h.readonly then
                    ldebug[3](L)
				end

                -- luaH_set would work but would repeat the lookup so we use luaH_setslot that can reuse oldval if it's safe
                local newval: {TValue} = luaH[5](L, h, oldval, key)

                -- L.cachedslot = gval2slot(h, newval); -- remember slot to accelerate future lookups -- TODO

                newval[1] = L.stack[val]
                return
			end

            -- fallthrough to metamethod
        else
			tm = assert(false, "luaT_gettmbyobj(L, t, TM_NEWINDEX)") :: any
			if not tm or tm.tt == 0 then
				ldebug[2](L, t, key)
			end
		end

        if tm.tt == 7 then
            assert(false, "callTM(L, tm, t, key, val)")
            return
		end
        -- else repeat with `tm'
		temp = tm
		t = temp
    end
    ldebug[1](L, "'__newindex' chain too long; possible loop")
end

return {
	luaV_gettable :: any,
	luaV_settable
}
