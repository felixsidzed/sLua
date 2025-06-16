--!strict
--!optimize 2

local lstate = require("lstate")

type lua_State = lstate.lua_State
type TString = lstate.TString

function luaS_hash(str)
	local len = #str
	local a, b = 0, 0
	local h = len

	local function rol(x, s)
		return bit32.bor(bit32.rshift(x, s), bit32.lshift(x, 32 - s))
	end

	local function mix(u, v, w)
		a = bit32.bxor(a, h)
		a = a - rol(h, u)
		b = bit32.bxor(b, a)
		b = b - rol(a, v)
		h = bit32.bxor(h, b)
		h = h - rol(b, w)
	end

	local index = 1

	while len >= 32 do
		local block = {
			string.unpack("<I4I4I4", str, index)
		}

		a = a + block[1]
		b = b + block[2]
		h = h + block[3]
		mix(14, 11, 25)

		index = index + 12
		len = len - 12
	end

	for i = len, 1, -1 do
		local byte = string.byte(str, index + i - 1)
		h = bit32.bxor(h, bit32.lshift(h, 5) + bit32.rshift(h, 2) + byte)
	end

	return h
end

local function lmod(s: number, size: number): number
	assert(bit32.band(size, size - 1) == 0)
	return bit32.band(s, size - 1)
end

function luaS_new(L: lua_State, data: string): TString
	local h: number = luaS_hash(data)
	local ts: TString = {
		atom = -32768,
		hash = h,
		len = string.len(data),
		data = data,
		marked = 0,
		tt = 5,
		memcat = L.activememcat,
		next = nil :: any
	}

	local tb = L.global.strt
	h = lmod(h, tb.size)
	ts.next = tb.hash[h] -- chain new entry
	tb.hash[h] = ts

	tb.nuse += 1
	if tb.nuse > tb.size and tb.size <= 1073741823 then
		--luaS_resize(L, tb.size * 2) -- too crowded
	end

	return ts
end

return {
	luaS_new :: any,
	luaS_hash
}
