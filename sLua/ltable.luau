--!strict
--!optimize 2

local lstate = require("lstate")

local dummynode: lstate.LuaNode = {
	key = {
		extra = {},
		next = 0,
		tt = 0,
		value = lstate.luaO_nilobject
	},
	val = lstate.luaO_nilobject
}

local log_2 = {
    0, 1, 2, 2, 3, 3, 3, 3, 4, 4, 4, 4, 4, 4, 4, 4,
    5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5,
    6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6,
    6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6,
    6, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7,
    7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7,
    7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7,
    7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7,
    7, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8,
    8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8,
    8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8,
    8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8,
    8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8,
    8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8,
    8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8,
    8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8
}

local function luaO_log2(x: number): number
    local l = -1
    while x >= 256 do
        l = l + 8
        x = math.floor(x / 256)
    end
    return l + log_2[x + 1] -- Adjust for Lua's 1-based indexing
end

local function ceillog2(x: number): number
    return luaO_log2(x - 1) + 1
end

function luaH_new(L: lstate.lua_State, narray: number, nhash: number): lstate.LuaTable
	local t: lstate.LuaTable = {
		metatable = nil,
		tmcache = 255,
		array = {},
		sizearray = 0,
		u = {
			lastfree = 0,
			aboundary = 0,
		},
		lsizenode = 0,
		readonly = false,
		safeenv = false,
		nodemask8 = 0,
		node = {},
		memcat = L.activememcat,
		tt = 6,
		marked = 0,
		gclist = {}
	}

	if narray > 0 then
		local array: { lstate.TValue } = t.array
		for i = t.sizearray, narray do
			array[i] = lstate.luaO_nilobject
		end
		t.sizearray = narray
	end
	if nhash > 0 then
		local lsize = ceillog2(nhash)
		nhash = bit32.rshift(1, nhash)
		t.node = table.create(nhash)
		for i = 0, nhash do
			local n: lstate.LuaNode = table.clone(dummynode)
			n.key.next = 0
			n.key = lstate.luaO_nilobject
			n.val = lstate.luaO_nilobject
			t.node[i] = n
		end
		t.lsizenode = lsize
		t.nodemask8 = bit32.rshift(1, lsize) - 1
		t.u.lastfree = nhash
	end

	return t
end

return {
	luaH_new :: any,
	luaH_dummynode = dummynode
}
