--!strict
--!optimize 2

local lstate = require("lstate")
local ldebug = require("ldebug")

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
			n.key = table.clone(luaO_nilobject)
			n.key.next = 0
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
		if n.key.next == 0 then
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
			if n.key.next == 0 then
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

local newkey: (L: lua_State, t: LuaTable, key: TValue) -> {TValue}

local function countint(key: number, nums: {number}): number
	local k: number = if key % 1 == 0 then key else -1
	if k > 0 and k <= 67108864 then -- is `key' an appropriate array index?
		nums[ceillog2(k)] += 1
		return 1
	else
		return 0
	end
end

local function numusearray(t: LuaTable, nums: { number }): number
	local lg: number = 0
	local ttlg: number = 1 -- 2^lg
	local ause: number = 0 -- summation of `nums'
	local i: number = 1
	while lg <= 26 do -- for each slice
		local lc: number = 0 -- counter
		local lim: number = ttlg
		if lim > t.sizearray then
			lim = t.sizearray --s adjust upper limit
			if i > lim then
				break -- no more elements to count
			end
		end
		-- count elements in range (2^(lg-1), 2^lg]
		while i <= lim do
			if t.array[i - 1] then
				lc += 1
			end
			i += 1
		end
		nums[lg] += lc
		ause += lc
		lg += 1
		ttlg *= 2
	end
	return ause;
end

local function rehash(L: lua_State, t: LuaTable, ek: TValue): ()
	local nums = table.create(26, 0) -- nums[i] = number of keys between 2^(i-1) and 2^i
	local nasize: number = numusearray(t, nums)        -- count keys in array part
	local totaluse: number = nasize
	totaluse += numusehash(t, nums, {nasize}) -- count keys in hash part

	-- count extra key
	if ek.tt == 3 then
		nasize += countint(ek.value.n :: number, nums)
	end
	totaluse += 1

	-- compute new size for array part
	local na: number = computesizes(nums, {nasize})
	local nh: number = totaluse - na

	-- enforce the boundary invariant for performance, only do hash lookups if we must
	local nadjusted: number = adjustasize(t, nasize, ek)

	-- count how many extra elements belong to array part instead of hash part
	local aextra = nadjusted - nasize

	if aextra ~= 0 then
		-- we no longer need to store those extra array elements in hash part
		nh -= aextra

		-- because hash nodes are twice as large as array nodes, the memory we saved for hash parts can be used by array part
		-- this follows the general sparse array part optimization where array is allocated when 50% occupation is reached
		nasize = nadjusted + aextra

		-- since the size was changed, it's again important to enforce the boundary invariant at the new size
		nasize = adjustasize(t, nasize, ek)
	end

	-- resize the table to new computed sizes
	resize(L, t, nasize, nh)
end

local function arrayornewkey(L: lua_State, t: LuaTable, key: TValue)
	if key.tt == 3 then
		local k: number = key.value.n :: number
		if k % 1 == 0 and math.abs(k) - 1 < math.abs(t.sizearray) then
			return {t.array[k - 1]}
		end
	end

	return newkey(L, t, key)
end

newkey = function(L: lua_State, t: LuaTable, key: TValue): {TValue}
	-- enforce boundary invariant
	if key.tt == 3 and key.value.n == t.sizearray + 1 then
		rehash(L, t, key) -- grow table

		-- after rehash, numeric keys might be located in the new array part, but won't be found in the node part
		return arrayornewkey(L, t, key)
	end

	local pmp: number = mainposition(t, key)
	local mp: LuaNode = t.node[pmp]
	if mp.val.tt ~= 0 or mp == dummynode then
		local pn: number = getfreepos(t) -- get a free place
		local n: LuaNode = t.node[pn]
		if not n then                      -- cannot find a free place?
			rehash(L, t, key) -- grow table

			-- after rehash, numeric keys might be located in the new array part, but won't be found in the node part
			return arrayornewkey(L, t, key)
		end
		assert(n ~= dummynode)
		local mk: TValue = {
			value = mp.key.value,
			extra = mp.key.extra,
			tt = mp.key.tt,
		}
		local pothern: number = mainposition(t, mk)
		local othern: LuaNode = t.node[pothern]
		if othern ~= mp then -- is colliding node out of its main position?
			-- yes move colliding node into free position
			while pothern + othern.key.next ~= pmp do
				pothern += othern.key.next          -- find previous
				othern = t.node[pothern]
			end
			othern.key.next = pn - pothern
			-- copy colliding node into free pos. (mp->next also goes)
			for k,v in mp do n[k] = v end
			if mp.key.next ~= 0 then
				n.key.next += pmp - pn -- correct 'next'
				mp.key.next = 0 -- now 'mp' is free
			end
			mp.val = luaO_nilobject
		else-- colliding node is in its own main position
			-- new node will go into free position
			if mp.key.next ~= 0 then
				n.key.next = (pmp + mp.key.next) - pn -- chain new position
			else
				assert(n.key.next == 0)
			end
			mp.key.next = pn - pmp
			mp = n
		end
	end
	mp.key.value = key.value
	mp.key.extra = key.extra
	mp.key.tt = key.tt
	--luaC_barriert(L, t, key)
	assert(mp.val.tt == nil)
	return {mp.val}
end

function luaH_newkey(L: lua_State, t: LuaTable, key: TValue): {TValue}
	if key.tt == 0 then
		ldebug[1](L, "table index is nil")
	elseif key.tt == 3 and key.value.n ~= key.value.n then
		ldebug[1](L, "table index is NaN")
	end
	return newkey(L, t, key)
end

function luaH_setslot(L: lua_State, t: LuaTable, slot: TValue, key: TValue): {TValue}
	t.tmcache = 0
	if slot == luaO_nilobject then
		return luaH_newkey(L, t, key)
	else
		return slot
	end
end

return {
	luaH_new :: any,
	luaH_get,
	luaH_getstr,
	luaH_getnum,
	luaH_setslot,
	luaH_newkey,

	luaH_dummynode = dummynode
}
