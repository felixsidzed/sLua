--!strict
--!optimize 2

local sLua = require("sLua.luau")

sLua.use("compiler")
sLua.use("string") -- lstate depends on lstring
sLua.use("table")  --               and ltable
sLua.use("state")
sLua.use("vm") -- fuck u im making vm before api -- nvm
sLua.use("api")

local L = sLua.luaL_newstate()

local src: string = [[
print("sybau vro ts js pmo icl")
]]
local bbc: string = sLua.luau_compile(src, { 0, 1, 2 })
if bbc:sub(1, 1) ~= "\0" then
	if sLua.luau_load(L, "=", bbc, #bbc) == 0 then
		sLua.lua_call(L, -1) -- TODO
	end
else
	error(bbc:sub(1))
end
