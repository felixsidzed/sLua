local sLua = require("../sLua.luau")

-- include all the necessary libraries
sLua.use("state")   -- luaL_newstate
sLua.use("api")     -- lua_newtable, lua_settable, lua_gettable, lua_pushinteger, lua_setglobal

-- create a new lua state
local L = sLua.luaL_newstate()

-- create a new table and push it onto the stack
sLua.lua_newtable(L)

-- set the key "x" to be an integer of value 100
sLua.lua_pushstring(L, "x")
sLua.lua_pushinteger(L, 100)
sLua.lua_settable(L, -3)

-- print x multipled by 2
sLua.lua_pushstring(L, "x")
sLua.lua_gettable(L, -2)
print("Value of x multiplied by 2:", sLua.lua_tointeger(L, -1) * 2)
