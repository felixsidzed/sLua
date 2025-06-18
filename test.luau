--!strict
--!optimize 2

local sLua = require("sLua.luau")

sLua.use("compiler")
sLua.use("string") -- lstate depends on lstring
sLua.use("table")  --               and ltable
sLua.use("state")
sLua.use("api")
sLua.use("vmload")
sLua.use("vmexecute")

local L = sLua.luaL_newstate()

local src: string = [[
a = 5
]]
local bbc: string = sLua.luau_compile(src, { 0, 1, 2 })
if bbc:sub(1, 1) ~= "\0" then
	if sLua.luau_load(L, "=", bbc, #bbc, 0) == 0 then
		sLua.lua_call(L, 0, 0)
		print(L.gt.node)
	end
else
	error(bbc:sub(1))
end
