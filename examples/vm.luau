local sLua = require("../sLua.luau")

-- include all the necessary libraries
sLua.use("state")   -- luaL_newstate
sLua.use("api")     -- lua_call, lua_tostring
sLua.use("vm")      -- luau_load
sLua.use("baselib") --

local L = sLua.luaL_newstate()
sLua.lua_openlibs(L)

-- luau_compile uses lune's luau library and is "builtin" in sLua (no .use needed)
local btc = sLua.luau_compile("print('Hello, World!')", { 0, 1, 2 })
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
