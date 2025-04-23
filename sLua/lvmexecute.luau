--!strict
--!optimize 2

local lstate = require("lstate")

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

function luau_execute(L: lstate.lua_State)
	-- the critical interpreter state, stored in locals for performance
	-- the hope is that these map to registers without spilling (which is not true for x86 :/)
	local cl: lstate.Closure
	local base: number
	local k: lstate.TValue -- TValue*
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

	local function VM_KV(kv: number): lstate.TValue
		return k[kv + 1]
	end

	local VM_NEXT; VM_NEXT = function()
		local dispatchOp: number = LUAU_INSN_OP(code[pc])
		print(dispatchOp)
		
		if dispatchOp == 0 then
			pc += 1
			local insn = code[pc - 1]
			assert(insn == 0)
			VM_NEXT()

		elseif dispatchOp == 2 then
			pc += 1
			local insn = code[pc - 1]
			local ra: number = VM_REG(LUAU_INSN_A(insn))

			L.stack[ra] = lstate.luaO_nilobject
			VM_NEXT()

		elseif dispatchOp == 3 then
			pc += 1
			local insn = code[pc - 1]
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
			VM_NEXT()

		elseif dispatchOp == 4 then
			pc += 1
			local insn = code[pc - 1]
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
			VM_NEXT()

		elseif dispatchOp == 5 then
			pc += 1
			local insn = code[pc - 1]
			local ra: number = VM_REG(LUAU_INSN_A(insn))
			local kv: lstate.TValue = VM_KV(LUAU_INSN_D(insn))
			
			L.stack[ra] = kv
			VM_NEXT()

		else
			print(`unsupported opcode: {dispatchOp} (pc: {pc})`)

			if pc < #code then
				pc += 1
				VM_NEXT()
			end
		end
	end

	VM_NEXT()
end

return {
	luau_execute
}
