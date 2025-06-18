--!strict
--!optimize 2

local lstate = require("lstate")

type lua_State = lstate.lua_State
type LuaNode = lstate.LuaNode
type TValue = lstate.TValue
type LuaTable = lstate.LuaTable
type TString = lstate.TString
type GCObject = lstate.GCObject

local luaO_nilobject = lstate.luaO_nilobject

local dummynode: LuaNode = {
	key = {
		extra = {},
		next = 0,
		tt = 0,
		value = luaO_nilobject
	},
	val = luaO_nilobject
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
	return l + log_2[x + 1]
end

local function ceillog2(x: number): number
	return luaO_log2(x - 1) + 1
end

local function hashnum(t: LuaTable, n: number): number
	-- mask out sign bit to make sure -0 and 0 hash to the same value
	local scaled = math.floor(n * 1e6) -- scale to make decimals significant
	local h1 = bit32.band(scaled, 0xffffffff)
	local h2 = bit32.band(bit32.rshift(scaled, 32), 0x7fffffff)

	-- finalizer from MurmurHash64B
    local m: number = 0x5bd1e995

    h1 = bit32.bxor(h1, bit32.rshift(h2, 18))
    h1 *= m
	h2 = bit32.bxor(h2, bit32.rshift(h1, 22))
    h2 *= m
	h1 = bit32.bxor(h1, bit32.rshift(h2, 17))
    h1 *= m
    h2 = bit32.bxor(h2, bit32.rshift(h1, 19))
    h2 *= m

    -- ... truncated to 32-bit output (normally hash is equal to (uint64_t(h1) << 32) | h2, but we only really need the lower 32-bit half)
    return  bit32.band(h2, t.lsizenode-1)
end

function luaH_new(L: lua_State, narray: number, nhash: number): LuaTable
	local t: LuaTable = {
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
		local array: { TValue } = t.array
		for i = t.sizearray, narray do
			array[i] = luaO_nilobject
		end
		t.sizearray = narray
	end
	if nhash > 0 then
		local lsize = ceillog2(nhash)
		nhash = bit32.rshift(1, nhash)
		t.node = table.create(nhash)
		for i = 0, nhash do
			local n: LuaNode = table.clone(dummynode)
			n.key.next = 0
			n.key = luaO_nilobject
			n.val = luaO_nilobject
			t.node[i] = n
		end
		t.lsizenode = lsize
		t.nodemask8 = bit32.rshift(1, lsize) - 1
		t.u.lastfree = nhash
	end

	return t
end

-- search function for strings
function luaH_getstr(t: LuaTable, key: TString): TValue
	local pn = bit32.band(key.hash, t.lsizenode-1)
	while true do -- check whether `key' is somewhere in the chain
		local n: LuaNode = t.node[pn]
		if n.key.tt == 5 and ((n.key.value.gc :: GCObject).ts :: TString).data == key.data then
			return n.val -- that's it
		end
		if (n.key.next == 0) then
			break
		end
		pn += n.key.next
	end
	return luaO_nilobject
end

function luaH_getnum(t: LuaTable, key: number): TValue
	-- (1 <= key && key <= t.sizearray)
	if math.abs(key) - 1 < t.sizearray then
		return t.array[key - 1]
	elseif t.node ~= dummynode then
		local pn: number = hashnum(t, key)
		while true do -- check whether `key' is somewhere in the chain
			local n: LuaNode = t.node[pn]
			if n.key.tt == 3 and n.key.value.n == key then
				return n.val -- that's it
			end
			if (n.key.next == 0) then
				break
			end
			pn += n.key.next
		end
		return luaO_nilobject
	else
		return luaO_nilobject
	end
end

function luaH_get(t: LuaTable, key: TValue): TValue?
	if key.tt == 0 then
		return luaO_nilobject
	elseif key.tt == 5 then
		return luaH_getstr(t, (key.value.gc :: GCObject).ts :: TString)
	elseif key.tt == 3 then
		local k: number = key.value.n :: number
		if k % 1 == 0 then -- index is int?
			return luaH_getnum(t, k)
		end
		-- else fall through
	end

	assert("NotImplementedYet")
	return nil
end

return {
	luaH_new :: any,
	luaH_get,
	luaH_getstr,
	luaH_dummynode = dummynode
}
