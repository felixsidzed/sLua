local sLua = require("../sLua.luau")

-- include all the necessary libraries
sLua.use("state")   -- luaL_newstate
sLua.use("api")     -- lua_watchstack, lua_newcclosure, lua_pushcfunction, lua_call, lua_unwatchstack
sLua.use("typeh")   -- luaT_isclosure

-- create a new state
local L = sLua.luaL_newstate()

-- montior values pushed onto the stack
sLua.lua_watchstack(L, function(L, idx, value)
	-- check if the value is a closure(function)
	if sLua.luaT_isclosure(value) then
		-- check if the function is a "c" function
		if value.isC then
			-- get the name of the function
			local name = value.c.debugname

			-- sometimes functions are missing debugnames, but thats ok because we can use debug.info(..., "n")
			if name == nil then
				name = debug.info(value.c.f, "n")
			end

			-- if the name is "maliciousFunction", replace it
			if name == "maliciousFunction" then
				local safeFunction = sLua.lua_newcclosure(L, 0, {})
				safeFunction.c.f = function(...)
					print("Malicious function call stopped!")

					return 0
				end
				safeFunction.c.upvals = {}

				L.stack[idx] = safeFunction
			end
		end
	end
end)

-- define our malicious function
local function maliciousFunction(L)
	-- placeholder
	warn("Malicious function called!")

	-- 0 results
	return 0
end

-- push our function onto the stack
sLua.lua_pushcfunction(L, maliciousFunction, "maliciousFunction")
sLua.lua_call(L, 0, 0)

-- stop monitoring the stack
sLua.lua_unwatchstack(L)
