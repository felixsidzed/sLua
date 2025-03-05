local sLua = require("../sLua.luau")

-- include all the necessary libraries
sLua.use("state")   -- luaL_newstate
sLua.use("api")     -- lua_pushcfunction, lua_pushinteger, lua_call, lua_tointeger

-- create a new state and include the built-in library
local L = sLua.luaL_newstate()

-- define our "c" function
local function square(L)
	local arg = sLua.lua_tointeger(L, -1)

	-- not an integer
	if arg == nil then
		return 0
	end

	-- square the argument and push it into the stack
	sLua.lua_pushinteger(L, arg * arg)

	return 1 -- number of results
end

-- push our function onto the stack
sLua.lua_pushcfunction(L, square)
sLua.lua_pushinteger(L, 6)
sLua.lua_call(L, 1, 1)
print("The square of 6 is:", sLua.lua_tointeger(L, -1))
