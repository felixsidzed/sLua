local lstate = require("lstate.luau")
local reader = require("reader.luau")
local LUA = require("lconf.luau")
local lapi = require("lapi.luau")
local typeh = require("ltypeh")

export type OpCodeDecoder = (op: number) -> (number)

local LOP = {
    NOP = 0,
    BREAK = 1,
    LOADNIL = 2,
    LOADB = 3,
    LOADN = 4,
    LOADK = 5,
    MOVE = 6,
    GETGLOBAL = 7,
    SETGLOBAL = 8,
    GETGLOBALUPVAL = 9,
    SETGLOBALUPVAL = 10,
    CLOSEUPVALS = 11,
    GETIMPORT = 12,
    GETGLOBALTABLE = 13,
    SETGLOBALTABLE = 14,
    GETGLOBALTABLEKS = 15,
    SETGLOBALTABLEKS = 16,
    GETGLOBALTABLEN = 17,
    SETGLOBALTABLEN = 18,
    NEWCLOSURE = 19,
    NAMECALL = 20,
    CALL = 21,
    RETURN = 22,
    JUMP = 23,
    JUMPBACK = 24,
    JUMPIF = 25,
    JUMPIFNOT = 26,
    JUMPIFEQ = 27,
    JUMPIFLE = 28,
    JUMPIFLT = 29,
    JUMPIFNOTEQ = 30,
    JUMPIFNOTLE = 31,
    JUMPIFNOTLT = 32,
    ADD = 33,
    SUB = 34,
    MUL = 35,
    DIV = 36,
    MOD = 37,
    POW = 38,
    ADDK = 39,
    SUBK = 40,
    MULK = 41,
    DIVK = 42,
    MODK = 43,
    POWK = 44,
    AND = 45,
    OR = 46,
    ANDK = 47,
    ORK = 48,
    CONCAT = 49,
    NOT = 50,
    MINUS = 51,
    LENGTH = 52,
    NEWTABLE = 53,
    DUPTABLE = 54,
    SETLIST = 55,
    FORNPREP = 56,
    FORNLOOP = 57,
    FORGLOOP = 58,
    FORGPREPINEXT = 59,
    FASTCALL3 = 60,
    FORGPREPNEXT = 61,
    NATIVECALL = 62,
    GETGLOBALVARARGS = 63,
    DUPCLOSURE = 64,
    PREPVARARGS = 65,
    LOADKX = 66,
    JUMPX = 67,
    FASTCALL = 68,
    COVERAGE = 69,
    CAPTURE = 70,
    SUBRK = 71,
    DIVRK = 72,
    FASTCALL1 = 73,
    FASTCALL2 = 74,
    FASTCALL2K = 75,
    FORGPREP = 76,
    JUMPXEQKNIL = 77,
    JUMPXEQKB = 78,
    JUMPXEQKN = 79,
    JUMPXEQKS = 80,
    IDIV = 81,
    IDIVK = 82,
    COUNT = 83
}

function luau_load(L: lstate.lua_State, chunkname: string, data: string, size: number, env: number): number
	local read = reader.new(data:sub(1, size))

	local lbc = read:byte()

	if lbc < LUA.LBC_VERSION_MIN or lbc > LUA.LBC_VERSION_MAX then
		lapi.pushfstring(L, "[string '%s']: bytecode version mismatch (expected [%d..%d], got %d)", chunkname, LUA.LBC_VERSION_MIN, LUA.LBC_VERSION_MAX, lbc)
		return 1
	end

	local envt = if env == 0 then L.gt else L.stack[L.top + env + 1]

	local typesversion = 0
	if lbc >= 4 then
		typesversion = read:byte()
	end
	
	local nstrings = read:number()
	local strings = table.create(nstrings, "")
	for i=1, nstrings do
		strings[i] = read:string()
	end

	local userdataTypes = {}
	if typesversion == 3 then
		while true do
			local index = read:byte()
			if index == 0 then
				break
			end

			local nameRef = read:number()
			userdataTypes[index] = nameRef
		end
	end

	local nproto = read:number()
	local protos = table.create(nproto)

	for i = 1, nproto do
		local p: lstate.Proto = {} :: lstate.Proto

		p.bytecodeid = i
		p.source = chunkname

		p.maxstacksize = read:byte()
		p.numparams = read:byte()
		p.nups = read:byte()
		p.is_vararg = read:byte() ~= 0

		if lbc >= 4 then
			read:byte()

			p.sizetypeinfo = read:number()
			p.typeinfo = {}
			for i = 1, p.sizetypeinfo do
				p.typeinfo[i] = read:byte()
			end
		end

		p.sizecode = read:number()
		p.code = table.create(p.sizecode)
		for i = 1, p.sizecode do
			p.code[i] = read:word()
		end
		
		p.sizek = read:number()
		p.k = table.create(p.sizek)

		for i = 1, p.sizek do
			local T = read:byte()

			if T == 0 then -- nil
				-- All constants have already been pre-initialized to nil
				
			elseif T == 1 then -- boolean
				p.k[i] = read:byte() ~= 0

			elseif T == 2 then -- number
				p.k[i] = read:double()

			elseif T == 3 then -- string
				p.k[i] = strings[read:byte()]

			elseif T == 4 then -- import
				local id = read:word()

				local indexCount = bit32.rshift(id, 30)

				local index1 = bit32.band(bit32.rshift(id, 20), 0x3FF)
				local index2 = bit32.band(bit32.rshift(id, 10), 0x3FF)
				local index3 = bit32.band(bit32.rshift(id, 0), 0x3FF)

				local importTag = ""

				if indexCount == 1 then
					local k1 = p.k[index1 + 1]
					importTag ..= tostring(k1)
				elseif indexCount == 2 then
					local k1 = p.k[index1 + 1]
					local k2 = p.k[index2 + 1]
					importTag ..= tostring(k1) .. "."
					importTag ..= tostring(k2)
				elseif indexCount == 3 then
					local k1 = p.k[index1 + 1]
					local k2 = p.k[index2 + 1]
					local k3 = p.k[index3 + 1]
					importTag ..= tostring(k1) .. "."
					importTag ..= tostring(k2) .. "."
					importTag ..= tostring(k3)
				end

				p.k[i] = importTag

			elseif T == 5 then -- table
				local sizeTable = read:number()
				local tableKeys = {}

				for i = 1, sizeTable do
					local keyStringId = read:number() + 1
					table.insert(tableKeys, keyStringId)
				end

				p.k = {
					size = sizeTable,
					keys = tableKeys
				}
			
			elseif T == 6 then -- closure
				p.k[i] = read:number()

			elseif T == 7 then -- vector
				local x, y, z, w = read:float(), read:float(), read:float(), read:float()
				if w == 0 then
					p.k[i] = Vector3.new(x, y, z)
				else
					--p.k[i] = vector.create(x, y, z, w)
					error("Vector4 is not supported!")
				end

			else
				error(("Unrecognized constant type: %d"):format(T))

			end
		end

		p.sizep = read:number()
		p.p = table.create(p.sizep)

		for i = 1, p.sizep do
			p.p[i] = protos[read:number()]
		end

		p.linedefined = read:number()
		p.debugname = read:string()

		if read:byte() ~= 0 then
			local linegaplog2 = read:byte()

			local baselineSize = bit32.rshift(p.sizecode - 1, linegaplog2) + 1

			local lastOffset = 0
			local lastLine = 0

			local smallineinfo = {}
			local abslineinfo = {}
			local lineinfo = {}

			for i, instruction in p.code do
				-- i don't understand how this works. we mostly need signed, but sometimes we need unsigned?
				-- help please. if you understand
				local byte = read:sbyte()

				local offsetChange = lastOffset + byte
				smallineinfo[i] = offsetChange

				lastOffset = offsetChange
			end

			for i = 1, baselineSize do
				local largeLineChange = lastLine + read:sword()
				abslineinfo[i - 1] = largeLineChange

				lastLine = largeLineChange
			end

			for i, line in smallineinfo do
				local absIndex = bit32.rshift(i - 1, linegaplog2)

				local absLine = abslineinfo[absIndex]
				local resultLine = line + absLine

				if linegaplog2 <= 1 and (-line == absLine) then
					resultLine += abslineinfo[absIndex + 1]
				end

				if resultLine <= 0 then
					resultLine += 0x100
				end

				lineinfo[i] = resultLine
			end

			p.sizelineinfo = #lineinfo
			p.lineinfo = lineinfo
		end

		local debuginfo = read:byte()
		
		if debuginfo ~= 0 then
			p.sizelocvars = read:number()
			p.locvars = table.create(p.sizelocvars)

			for i = 1, p.sizelocvars do
				p.locvars[i] = {
					varname = strings[read:number()],
					startpc = read:number(),
					endpc = read:number(),
					reg = read:byte()
				}
			end

			p.sizeupvalues = read:number()
			p.upvalues = table.create(p.sizeupvalues)

			for i = 1, p.sizeupvalues do
				p.upvalues[i] = read:string()
			end
		end

		protos[i] = p
	end

	local mainid: number = read:byte()
	local main: lstate.Proto = protos[mainid + 1] -- index starts at 1 💔😭

	local cl: lstate.lua_Closure = {} :: any
	cl.isC = false
	cl.env = envt
	cl.nupvalues = 0
	cl.stacksize = main.maxstacksize
	cl.preload = 0
	cl.l = {
		p = main,
		uprefs = table.create(0)
	}

	lapi._setsvalue(L, L.top, cl)
	L.top += 1

	return 0
end

local function LUAU_INSN_OP(insn)
	return bit32.band(insn, 0xFF)
end
local function LUAU_INSN_A(insn)
	return bit32.band(bit32.rshift(insn, 8), 0xFF)
end
local function LUAU_INSN_B(insn)
	return bit32.band(bit32.rshift(insn, 16), 0xFF)
end
local function LUAU_INSN_C(insn)
	return bit32.band(bit32.rshift(insn, 24), 0xFF)
end
local function LUAU_INSN_D(insn)
	return bit32.rshift(insn, 16)
end
local function LUAU_INSN_E(insn)
return bit32.rshift(insn, 8)
end

function luau_execute(L: lstate.lua_State, decodeOp: OpCodeDecoder)
	local pc = L.ci.savedpc
	local ip = 0 -- no pointers so we have to use an instruction pointer (ip)

	local cl = L.ci.func
	local base = L.base
	local k = cl.l.p.k

	local function VM_REG(idx)
		return base + idx
	end

	local function VM_KV(idx)
		return k[idx + 1]
	end

	local function VM_PATCH_E(offset, slot)
		--((uint32_t(slot) << 8) | (0x000000ffu & *(pc)))
		pc[ip + (offset or 0)] = bit32.bor(bit32.lshift(slot, 8), bit32.band(0x000000ff, pc[ip]))
	end

	local VM_NEXT

	local function VM_DISPATCH(): ()
		local insn = pc[ip]
		local op = LUAU_INSN_OP(insn)

		if op == LOP.NOP then
			return VM_NEXT()
		
		elseif op == LOP.PREPVARARGS then
			local nparams = LUAU_INSN_A(insn)

			local fixed = base
			base = L.top

			for i = 1, nparams do
				lapi._setsvalue(L, base + i, L.stack[fixed + i])
				lapi._setsvalue(L, fixed + i, LUA.NILOBJ)
			end

			L.ci.base = base
			L.ci.top = base + cl.stacksize

			L.base = base
			L.top = L.ci.top

			return VM_NEXT()

		elseif op == LOP.GETGLOBAL then
			local ra = VM_REG(LUAU_INSN_A(insn))
			ip += 1
			local aux = pc[ip]
			local kv = VM_KV(aux)

			-- uhhh too lazy to do wtv luau does
			-- maybe ill implement this properly one day
			lapi._setsvalue(L, ra, L.gt[kv])

			return VM_NEXT()

		elseif op == LOP.LOADK then
			local ra = VM_REG(LUAU_INSN_A(insn))
			local kv = VM_KV(LUAU_INSN_D(insn))

			lapi._setsvalue(L, ra, kv)

			return VM_NEXT()

		elseif op == LOP.COVERAGE then
			local hits = LUAU_INSN_E(insn)

			hits = if hits < bit32.lshift(1, 23) - 1 then hits + 1 else hits
			VM_PATCH_E(0, hits)

			return VM_NEXT()

		elseif op == LOP.CALL then
			-- VM_INTERRUPT()
			local ra = VM_REG(LUAU_INSN_A(insn) + 1)

			local nparams = LUAU_INSN_B(insn) - 1
			local nresults = LUAU_INSN_C(insn) - 1

			local argtop = L.top
			argtop = if nparams == LUA.MULTRET then argtop else ra + nparams

			-- slow-path: not a function call
			--if not typeh.luaT_isclosure(L.stack[ra]) then
			--	L.ci.savedpc = pc

			--	luaV_tryfuncTM(L, ra)
			--	argtop += 1 -- __call adds an extra self
			--end

			local ccl = L.stack[ra]
			L.ci.savedpc = pc

			L.cip = L.ci
			L.ci = {
				func = L.stack[ra],
				base = L.top - nparams,
				top = L.top + ccl.stacksize,
				savedpc = {},
				flags = 0,
				nresults = nresults
			}
			L.base = L.ci.base
			L.top = argtop

			if ccl.isC then
				local func = ccl.c.f
				local n = func(L)

				-- yield
				if n < 0 then
					return -- goto exit
				end

				local res = ra --ci.func
				local vali = L.top - n
				local valend = L.top

				local i = nresults
				while i ~= 0 and vali < valend do
					res += 1
					vali += 1
					lapi._setsvalue(L, res, L.stack[vali])
					
					i -= 1
				end
				while i > 0 do
					lapi._setsvalue(L, res, nil)
					res += 1
					i -= 1
				end

				L.ci = L.cip
				L.base = L.cip.base
				L.top = if nresults == LUA.MULTRET then res else L.cip.top

				base = L.base

				return VM_NEXT()
			else
				local p = ccl.l.p

				local argi = L.top
				local argend = L.base + p.numparams
				while argi < argend do
					argi += 1
					lapi._setsvalue(L, ra--[[argi]], nil)
				end
				L.top = if p.is_vararg then argi else L.ci.top

				pc = p.code
				cl = ccl
				base = L.base
				k = p.k

				return VM_NEXT()
			end

		elseif op == LOP.RETURN then
			-- VM_INTERRUPT()
			local ra = VM_REG(LUAU_INSN_A(insn))--&base[LUAU_INSN_A(insn)]
			local b = LUAU_INSN_B(insn) - 1

			local ci = L.ci
			local cip = L.cip

			local res = ci.func

			local vali = ra
			local valend = if b == LUA.MULTRET then L.top else ra + b
			local nresults = ci.nresults

			local i = nresults
			while i ~= 0 and vali < valend do
				res += 1
				vali += 1
				lapi._setsvalue(L, res, L.stack[vali])
				
				i -= 1
			end
			while i > 0 do
				lapi._setsvalue(L, res, nil)
				res += 1
				i -= 1
			end

			L.ci = cip
			L.base = cip.base
			L.top = if nresults == LUA.MULTRET then res else cip.top

			if bit32.band(ci.flags, LUA.CALLINFO_RETURN) ~= 0 then
				return -- goto exit
			end

			local nextcl = cip.func
			local nextproto = nextcl.l.p

			pc = cip.savedpc
			cl = nextcl
			base = L.base
			k = nextproto.k

			return VM_NEXT()

		else
			for k, v in LOP do
				if v == op then 
					print("unsupported opcode:", k)
					return VM_NEXT()
				end
			end
			print("unsupported opcode:", op)
			return VM_NEXT()
		end
	end

	VM_NEXT = function()
		ip += 1
		if ip > #pc then return end

		VM_DISPATCH()
	end

	VM_NEXT() -- starts the interpreter "loop"
end

return {
	luau_load = luau_load,
	luau_execute = luau_execute
}
