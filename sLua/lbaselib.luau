local lstate = require("lstate.luau")
local lapi = require("lapi.luau")

local function luaB_print(L: lstate.lua_State): number
	local argc = lapi.gettop(L)

	local result = ""
	for i = -argc, -1 do
		result ..= lapi.tostring(L, i) .. " "
	end
	print(result)

	return 1
end

function openlibs(L: lstate.lua_State)
	lapi.pushcfunction(L, luaB_print, "print")
	lapi.setglobal(L, "print")
end

return {
	["openlibs"] = openlibs
}
