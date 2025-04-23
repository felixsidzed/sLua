--!strict
--!optimize 2

local lstate = require("lstate")
local reader = require("reader")
local lgc = require("lgc")
local luaS = require("lstring")
local luaH = require("ltable")
local luaF = require("lfunc")

local LBC_VERSION_MIN = 3
local LBC_VERSION_MAX = 6

local function ScopedSetGCThreshold(global, newThreshold)
    local originalThreshold = global.GCthreshold
    global.GCthreshold = newThreshold

    return function()
        global.GCthreshold = originalThreshold
    end
end

function luau_load(L: lstate.lua_State, chunkname: string, data: string, size: number, env: number): number
	env = env or 0

	local read = reader.new(data:sub(1, size))

	local lbc = read:byte()

	if lbc < LBC_VERSION_MIN or lbc > LBC_VERSION_MAX then
		-- manual pushstring cuz lapi depends on lvm (recursive require)
		L.stack[L.top] = {
			tt = 5, memcat = L.activememcat, marked = 0,
			extra = {},
			value = {
				gc = {
					gch = { tt = 5, memcat = L.activememcat, marked = 0 },
					ts = luaS[1](L, string.format(
						"[string '%s']: bytecode version mismatch (expected [%d..%d], got %d)",
						chunkname,
						LBC_VERSION_MIN, LBC_VERSION_MAX,
						lbc
					))
				}
			}
		}
		L.top += 1
		return 1
	end

	-- we will allocate a fair amount of memory so check GC before we do
	lgc.luaC_checkGC(L)

	-- pause GC for the duration of deserialization - some objects we're creating aren't rooted
	local resumeGC = ScopedSetGCThreshold(L.global, math.huge)

	-- env is 0 for current environment and a stack index otherwise
	local envt: lstate.LuaTable = if (env == 0) then L.gt else (L.stack[L.base + (env - 1)].value.gc :: lstate.GCObject).h :: lstate.LuaTable

	local source: lstate.TString = luaS[1](L, chunkname)

	local typesversion: number = 0

	if lbc >= 4 then
		typesversion = read:byte()
	end

	-- string table
	local stringCount: number = read:number()
	local strings: { lstate.TString } = table.create(stringCount)
	for i=1,stringCount do
		strings[i] = luaS[1](L, read:string())
	end

	-- userdata type remapping table
    -- for unknown userdata types, the entry will remap to common 'userdata' type
	local userdataTypeLimit: number = 32
	local userdataRemapping: { number } = table.create(userdataTypeLimit)

	if typesversion == 3 then
		for i = 1, userdataTypeLimit do
			userdataRemapping[i] = 7
		end

		local index: number = read:byte()
		while index ~= 0 do
			local name: lstate.TString = strings[index - 1]

			if index - 1 < userdataTypeLimit then
				local cb = L.global.ecb.gettypemapping
				if cb then
					userdataRemapping[index - 1] = cb(L, name.data, name.len)
				end
			end

			index = read:byte()
		end
	end

	-- proto table
	local protoCount: number = read:number()
	local protos: { lstate.Proto } = table.create(protoCount)

	for i = 1, protoCount do
		local p: lstate.Proto = {} :: any -- luaF_newproto(L)
		p.source = source
		p.bytecodeid = i

		p.maxstacksize = read:byte()
		p.numparams = read:byte()
		p.nups = read:byte()
		p.is_vararg = read:byte() ~= 0

		if lbc >= 4 then
			p.flags = read:byte()

			if typesversion == 1 then
				-- TODO

			elseif typesversion == 2 or typesversion == 3 then
				local typesize: number = read:number()

				if typesize then
					p.typeinfo = table.create(typesize)
					p.sizetypeinfo = typesize
					for i = 1, typesize do
						p.typeinfo[i] = read:byte()
					end
				end

			end
		end

		local sizecode: number = read:number()
		p.code = table.create(sizecode)
		p.sizecode = sizecode

		for j = 1, sizecode do
			p.code[j] = read:word()
		end

		p.codeentry = p.code

		local sizek: number = read:number()
		p.k = table.create(sizek)
		p.sizek = sizek

		for j = 1, p.sizek do
			local kt: number = read:byte()

			if kt == 0 then
				p.k[j] = lstate.luaO_nilobject

			elseif kt == 1 then
				p.k[j] = {
					value = {
						b = read:byte() ~= 0
					},
					extra = {},
					tt = 1
				}
			
			elseif kt == 2 then
				p.k[j] = {
					value = {
						n = read:double()
					},
					extra = {},
					tt = 3
				}
			
			elseif kt == 7 then
				local x: number = read:float()
				local y: number = read:float()
				local z: number = read:float()
				local w: number = read:float()
				p.k[j] = {
					value = {
						v = { x, y, z }
					},
					extra = { w },
					tt = 4
				}
			
			elseif kt == 3 then
				p.k[j] = {
					value = {
						gc = {
							gch = {
								memcat = L.activememcat,
								marked = 0,
								tt = 5
							},
							ts = strings[read:number()]
						}
					},
					extra = {},
					tt = 5
				}
			
			elseif kt == 4 then
				-- TODO
			
			elseif kt == 5 then
				local keys: number = read:number()
				local h: lstate.LuaTable = luaH[1](L, 0, keys)
				for i = 0, keys do
					local key: number = read:number()
					local val: lstate.TValue = luaH[2](L, h, p.k[key])
					val.value.n = 0.0
				end
				(p.k[j].value.gc :: lstate.GCObject).h = h

			elseif kt == 6 then
				-- TODO

			else
				assert(false)

			end
		end

		local sizep: number = read:number()
		p.p = table.create(sizep)
		p.sizep = sizep

		for j = 1, sizep do
			p.p[j] = protos[read:number()]
		end

		p.linedefined = read:number()
		p.debugname = strings[read:number()]

		local lineinfo: number = read:byte()
		if lineinfo == 1 then
			p.linegaplog2 = read:byte()

			local intervals: number = bit32.rshift((p.sizecode - 1), p.linegaplog2) + 1
			local absoffset: number = bit32.band((p.sizecode + 3), 4294967292)

			local sizelineinfo: number = absoffset + intervals * 4
			p.lineinfo = table.create(sizelineinfo)
			p.sizelineinfo = sizelineinfo

			p.abslineinfo = absoffset

			local lastoffset: number = 0
			for j = 1, p.sizecode do
				lastoffset += read:byte()
				p.lineinfo[j] = lastoffset
			end

			local lastline: number = 0
			for j = 1, intervals do
				lastline += read:sword()
				p.lineinfo[absoffset + j] = lastline
			end
		else
			p.lineinfo = {}
			p.sizelineinfo = 0
			p.abslineinfo = 0
		end

		local debuginfo: number = read:byte()
		if debuginfo == 1 then
			local sizelocvars: number = read:number()
			p.locvars = table.create(sizelocvars)
			p.sizelocvars = sizelocvars

			for j = 1, sizelocvars do
				p.locvars[j] = {
					varname = strings[read:number()],
					startpc = read:number(),
					endpc = read:number(),
					reg = read:byte()
				}
			end

			local sizeupvalues: number = read:number()
			assert(sizeupvalues == p.nups)

			p.upvalues = table.create(sizeupvalues)
			p.sizeupvalues = sizeupvalues

			for j = 1, p.sizeupvalues do
				p.upvalues[j] = strings[read:number()]
			end
		end

		protos[i] = p
	end

	local mainid: number = read:number()
	local main: lstate.Proto = protos[mainid + 1]

	resumeGC() -- i think so

	local cl: lstate.Closure = luaF[1](L, 0, envt, main)
	L.stack[L.top] = {
		tt = 7, marked = 0, extra = {},
		value = {
			gc = {
				gch = { tt = 7, marked = 0, memcat = L.activememcat },
				cl = cl
			}
		},
	}
	L.top += 1
	
	return 0
end

return {
	luau_load
}
