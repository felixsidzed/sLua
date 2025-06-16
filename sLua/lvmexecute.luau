--!strict
--!optimize 2

local lstate = require("lstate")

type lua_State = lstate.lua_State
type Closure = lstate.Closure
type TValue = lstate.TValue
type LuaTable = lstate.LuaTable
type LuaNode = lstate.LuaNode
type GCObject = lstate.GCObject
type TString = lstate.TString
type UpVal = lstate.UpVal

local luaO_nilobject = lstate.luaO_nilobject

local function LUAU_INSN_OP(insn: number): number
	return bit32.band(insn, 0xFF)
end

local function LUAU_INSN_A(insn: number): number
	return bit32.band(bit32.rshift(insn, 8), 0xFF)
end
local function LUAU_INSN_B(insn: number): number
	return bit32.band(bit32.rshift(insn, 24), 0xFF)
end
local function LUAU_INSN_C(insn: number): number
	return bit32.band(bit32.rshift(insn, 16), 0xFF)
end
local function LUAU_INSN_D(insn: number): number
	return bit32.rshift(insn, 16)
end

function luau_execute(L: lua_State)
	-- the critical interpreter state, stored in locals for performance
	-- the hope is that these map to registers without spilling (which is not true for x86 :/)
	local cl: Closure
	local base: number
	local k: TValue -- TValue*
	local pc: number
	local code: { number }
	local sizecode: number

	assert(not L.ci[L.cip].func.isC)
	assert(L.isactive)
	assert(bit32.band(L.marked, 4) ~= 0)

	assert(not L.ci[L.cip].func.isC)

	pc = L.ci[L.cip].savedpc
    cl = L.ci[L.cip].func
    base = L.base
    k = (cl.l :: any).p.k
	code = (cl.l :: any).p.code
	sizecode = (cl.l :: any).p.sizecode

	local function VM_REG(reg: number): number
		return base + reg
	end

	local function VM_KV(i: number): TValue
		return k[i + 1]
	end

	local function VM_UV(i: number): TValue
		return (cl.l :: any).uprefs[i]
	end

	local function VM_PATCH_C(pc: number, slot: number)
		code[pc] = (bit32.bor(bit32.lshift(slot, 24), bit32.band(0x00ffffff, code[pc])))
	end

	local function VM_NEXT()
		if pc > sizecode then
			return
		end
		local insn = code[pc]
		local dispatchOp: number = LUAU_INSN_OP(insn)
		
		if dispatchOp == 0 then
			assert(insn == 0)

		elseif dispatchOp == 2 then
			local ra: number = VM_REG(LUAU_INSN_A(insn))
			L.stack[ra] = luaO_nilobject

		elseif dispatchOp == 3 then
			local ra: number = VM_REG(LUAU_INSN_A(insn))
			L.stack[ra] = {
				tt = 1,
				marked = L.marked,
				memcat = L.activememcat,
				extra = {},
				value = {
					b = LUAU_INSN_B(insn) == 1
				}
			}

			pc += LUAU_INSN_C(insn)
			--LUAU_ASSERT(unsigned(pc - cl->l.p->code) < unsigned(cl->l.p->sizecode))

		elseif dispatchOp == 4 then
			pc += 1
			local ra: number = VM_REG(LUAU_INSN_A(insn))

			L.stack[ra] = {
				tt = 3,
				marked = L.marked,
				memcat = L.activememcat,
				extra = {},
				value = {
					n = LUAU_INSN_D(insn)
				}
			}

		elseif dispatchOp == 5 then
			local ra: number = VM_REG(LUAU_INSN_A(insn))
			local kv: TValue = VM_KV(LUAU_INSN_D(insn))
			
			L.stack[ra] = kv

		elseif dispatchOp == 6 then
			local ra: number = VM_REG(LUAU_INSN_A(insn))
			local rb: number = VM_REG(LUAU_INSN_B(insn))

			L.stack[ra] = L.stack[rb]

		elseif dispatchOp == 7 then
			local ra: number = VM_REG(LUAU_INSN_A(insn))
			pc += 1
			local aux: number = code[pc]
			local kv: TValue = VM_KV(aux)
			assert(kv.tt == 5)

			-- fast-path: value is in expected slot
			local h: LuaTable = cl.env
			local slot: number = bit32.band(LUAU_INSN_C(insn), h.nodemask8)
			local n: LuaNode = h.node[slot]

			if n.key.tt == 5 and ((n.key.value.gc :: GCObject).ts :: TString) == ((kv.value.gc :: GCObject).ts :: TString) and n.val.tt ~= 0 then
				L.stack[ra] = n.val
			else
				-- slow-path, may invoke Lua calls via __index metamethod
				-- local g: TValue = {
				-- 	tt = 6, marked = 0, memcat = 0,
				-- 	value = {
				-- 		gc = {
				-- 			gch = {tt = 6, marked = 0, memcat = 0},
				-- 			h = h
				-- 		}
				-- 	},
				-- 	extra = {}
				-- }
				L.cachedslot = slot
				-- TODO<luaV>
				--luaV_gettable(L, g, kv, L.stack[ra]) -- VM_PROTECT
				-- save cachedslot to accelerate future lookups; patches currently executing instruction since pc-2 rolls back two pc++
				VM_PATCH_C(pc - 2, slot)
			end

		elseif dispatchOp == 8 then
			local ra: number = VM_REG(LUAU_INSN_A(insn));
			pc += 1
			local aux: number = code[pc]
			local kv: TValue = VM_KV(aux)
			assert(kv.tt == 5)
			
			-- fast-path: value is in expected slot
			local h: LuaTable = cl.env
			local slot: number = bit32.band(LUAU_INSN_C(insn), h.nodemask8)
			local n: LuaNode = h.node[slot]

			if n.key.tt == 5 and ((n.key.value.gc :: GCObject).ts :: TString).data == ((kv.value.gc :: GCObject).ts :: TString).data and n.val.tt ~= 0 and not h.readonly then
				n.val = L.stack[ra]
				--luaC_barriert(L, h, ra) -- TODO
			else
				-- slow-path, may invoke Lua calls via __newindex metamethod
				-- local g: TValue = {
				-- 	tt = 6, marked = 0, memcat = 0,
				-- 	value = {
				-- 		gc = {
				-- 			gch = {tt = 6, marked = 0, memcat = 0},
				-- 			h = h
				-- 		}
				-- 	},
				-- 	extra = {}
				-- }
				L.cachedslot = slot
				-- TODO<luaV>
				--luaV_settable(L, g, kv, L.stack[ra]) -- VM_PROTECT
				-- save cachedslot to accelerate future lookups; patches currently executing instruction since pc-2 rolls back two pc++
				VM_PATCH_C(pc - 2, slot)
			end

		elseif dispatchOp == 9 then
			local ra: number = VM_REG(LUAU_INSN_A(insn))
			local ur: TValue = VM_UV(LUAU_INSN_B(insn))
			
			L.stack[ra] = if ur.tt == 12 then ((ur.value.gc :: GCObject).uv :: UpVal).v :: any else ur

		else
			print(`unsupported opcode: {dispatchOp} (pc: {pc})`)
		end

		pc += 1
		VM_NEXT()
	end

	VM_NEXT()
end

return {
	luau_execute
}
