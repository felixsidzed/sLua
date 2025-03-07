local sLua = require("../sLua.luau")

-- include all the necessary libraries
sLua.use("state")   -- luaL_newstate
sLua.use("api")     -- lua_call, lua_tostring
sLua.use("vm")      -- luau_load
sLua.use("baselib") -- lua_openlibs

local L = sLua.luaL_newstate()
sLua.lua_openlibs(L)

-- luau_execute will use those callbacks
L.global.cb = {
	-- (nullable) called every time luau_execute encounters a BREAK instruction
	debugbreak = function(L)
		warn("debug break called. waiting 1 second")
	
		local start = os.clock()
		while os.clock() - start <= 1 do end
	end,

	-- (nullable) called every time luau_execute needs to decode an opcode
	decodeOp = function(op: number): number
		-- normal luau
		return op

		-- roblox luau (not sure about this one)
		--return (op * 203 % 256) // 227
	end,

	-- (nullable) called every time luau_execute triggers an interrupt
	interrupt = function(L)
		-- ...
	end
}

-- luau_compile uses lune's luau library and is "builtin" in sLua (no .use needed)
local btc = sLua.luau_compile("print('Hello, World!')", { 2, 1, 2 })
if btc:sub(1, 1) == "\0" then -- everything else is an error
	error(btc:sub(1))
else
	--                               chunkname  bytecode  size  env
	local status = sLua.luau_load(L,    "=",      btc,    #btc,  0 )
	if status ~= 0 then -- an error occured
		error(sLua.lua_tostring(L, -1))
	end

	-- call the closure created by luau_load
	sLua.lua_call(L, 0, 0)
end
