--!strict
--!optimize 2

local lstate = require("lstate")

type lua_State = lstate.lua_State
type Closure = lstate.Closure
type TValue = lstate.TValue

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

	assert(not L.ci[L.cip].func.isC)
	assert(L.isactive)
	assert(bit32.band(L.marked, 4) ~= 0)

	assert(not L.ci[L.cip].func.isC)

	pc = L.ci[L.cip].savedpc
    cl = L.ci[L.cip].func
    base = L.base
    k = (cl.l :: any).p.k
	code = (cl.l :: any).p.code

	local function VM_REG(reg: number): number
		return base + reg
	end

	local function VM_KV(kv: number): TValue
		return k[kv + 1]
	end

	local function VM_NEXT()
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
