--!strict
--!optimize 2

local luau = require("@lune/luau")

local sLua = {
	luau_compile = function(source: string, compileOptions: { number }): string
		local success: boolean, result: any = pcall(function()
			return luau.compile(source, {
				optimizationLevel = compileOptions[1] or 2,
				coverageLevel = compileOptions[2] or 1, -- NOTE: Luau::compile second option is types info level, not coverage
				debugLevel = compileOptions[3] or 2,
			})
		end)
		if not success then
			return "\0" .. tostring(result):match("runtime error:%s*([^%s].-)%s*stack traceback:") :: string
		end
		return result
	end
}

function sLua.use(name: string, hidden: boolean?): { [string]: any }
	local module = require("sLua/l"..name..".luau")

	for key, value in module do
		if key:sub(1, 1) == "_" and hidden then
			continue
		end

		if type(value) == "function" and key:sub(1, 3) ~= "lua" then
			key = "lua_" .. key
		end
		sLua[key] = value
	end

	-- hard coded :(
	if name == "api" then
		if not sLua.luau_load then
			sLua.use("vm")
		end

		module._init({
			execute = sLua.luau_execute,
			load = sLua.luau_load
		})
	end

	return module
end

return sLua
