local sLua = require("../sLua.luau")

-- include all the necessary libraries
sLua.use("state")   -- luaL_newstate
sLua.use("api")     -- lua_call, lua_getglobal, lua_pushfstring
sLua.use("baselib") -- lua_openlibs

-- create a new state and include the built-in library
local L = sLua.luaL_newstate()
sLua.lua_openlibs(L)

sLua.lua_getglobal(L, "print") -- push the print function onto the stack
sLua.lua_pushfstring(L, "Hello, %s!", "World") -- pass "Hello, World!" as an argument
sLua.lua_call(L, 1, 0) -- call print
                       -- first arg:  nparams
					   -- second arg: nresults
