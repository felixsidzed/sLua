local sLua = {}

_G.sLuaModuleCache = _G.sLuaModuleCache or {}

function sLua.using(name: string)
	return _G.sLuaModuleCache[name] ~= nil
end

function sLua.use(name: string)
	if _G.sLuaModuleCache[name] then return end
	_G.sLuaModuleCache[name] = {}
	local module = (require)(`sLua/l{name}.luau`)
	for k, v in module do
		if type(v) == "function" and type(k) == "number" then k = debug.info(v, "n") end
		if k:sub(1, 3) ~= "lua" and type(v) == "function" then k = "lua_" .. k end
		sLua[k] = v
	end
	_G.sLuaModuleCache[name] = module
end

return sLua
