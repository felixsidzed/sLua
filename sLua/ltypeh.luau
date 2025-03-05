local function ttisclosure(tbl: any): boolean
	if type(tbl) ~= "table" then
		return false
	end

	if type(tbl.isC) ~= "boolean" then
		return false
	end
	if type(tbl.nupvalues) ~= "number" then
		return false
	end
	if type(tbl.stacksize) ~= "number" then
		return false
	end
	if type(tbl.preload) ~= "number" then
		return false
	end
	if type(tbl.env) ~= "table" then
		return false
	end

	if tbl.isC then
		if type(tbl.c) ~= "table" then
			print("c")
			return false
		end
		if type(tbl.c.f) ~= "function" then
			print("c.f", tbl)
			return false
		end
		if tbl.c.cont ~= nil and type(tbl.c.cont) ~= "function" then
			print("c.cont")
			return false
		end
		if tbl.c.debugname ~= nil and type(tbl.c.debugname) ~= "string" then
			print("c.debugname")
			return false
		end
		if type(tbl.c.upvals) ~= "table" then
			print("c.upvals", tbl)
			return false
		end
	else
		if type(tbl.l) ~= "table" then
			return false
		end
		if type(tbl.l.p) ~= "table" then
			return false
		end
		if type(tbl.l.uprefs) ~= "table" then
			return false
		end
	end

	return true
end

return {
	["luaT_isclosure"] = ttisclosure
}
