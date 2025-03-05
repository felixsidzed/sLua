local sLua = require("../sLua.luau")

-- include all the necessary libraries
sLua.use("state")   -- luaL_newstate
sLua.use("api")     -- lua_pushfstring, lua_setglobal, lua_getglobal

-- create a new state and include the built-in library
local L = sLua.luaL_newstate()

-- push the value on the stack
sLua.lua_pushfstring(L, "Hello from %s!", "globals")

-- set the global to the globals table
sLua.lua_setglobal(L, "myGlobalVariable")

-- get the global
sLua.lua_getglobal(L, "myGlobalVariable")

-- print the global's value to console
print(sLua.lua_tostring(L, -1))
