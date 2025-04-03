local luau = (require)("@lune/luau")

return {
	luau_compile = function(source: string, compileOptions: { number }): string
		compileOptions = compileOptions or {}
		local success: boolean, result: any = pcall(function()
			return luau.compile(source, {
				optimizationLevel = compileOptions[1] or 2,
				coverageLevel = compileOptions[2] or 1, -- NOTE: Luau::compile second option is types info level, not coverage
				debugLevel = compileOptions[3] or 2,
			})
		end)
		if not success then
			return "\0"..tostring(result):match("runtime error:%s*([^%s].-)%s*stack traceback:") :: string
		end
		return result
	end
}
