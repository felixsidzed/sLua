local lstate = require("lstate.luau")
local lapi = require("lapi.luau")

function luaB_print(L: lstate.lua_State): number
	local argc = lapi.gettop(L)

	local result = ""
	for i = -argc, -1 do
		result ..= lapi.tostring(L, i) .. " "
	end
	print(result)
	lapi.pop(L, argc)

	return 1
end

function luaB_tonumber(L: lstate.lua_State): number
	local argc = lapi.gettop(L)
	if argc == 0 then
		error("missing argument #1", 0)
		return 0
	end

	local value = L.stack[L.top - 1]
	if argc == 1 then
		lapi.pop(L, argc)
		L.stack[L.top + 1] = tonumber(value, 10) :: any
	elseif argc == 2 then
		local radix = lapi.tointeger(L, -1)
		lapi.pop(L, argc)
		L.stack[L.top + 1] = tonumber(value, radix) :: any
	end

	return 1
end

function openlibs(L: lstate.lua_State)
	lapi.pushcfunction(L, luaB_print, "print")
	lapi.setglobal(L, "print")

	lapi.pushcfunction(L, luaB_tonumber, "tonumber")
	lapi.setglobal(L, "tonumber")
end

return {
	["openlibs"] = openlibs
}
