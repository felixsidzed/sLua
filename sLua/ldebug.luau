--!strict
--!optimize 2

local lstring = require("lstring")
local lstate = require("lstate")

function pusherror()
end

function luaG_runerror(L: lstate.lua_State, fmt: string, ...)
	local ci: lstate.CallInfo = L.ci[L.cip]
	if L.ci and not ci.func.isC and ci.func.l then
		local p: lstate.Proto = ci.func.l.p
		local source: lstate.TString = p.source
		local line: number = p.lineinfo[p.abslineinfo + bit32.rshift(ci.savedpc, p.linegaplog2)] + p.lineinfo[ci.savedpc]
		-- manual pushstring cuz lapi depends on ldebug (recursive require)
		L.stack[L.top] = {
			tt = 5, memcat = L.activememcat, marked = 0,
			extra = {},
			value = {
				gc = {
					gch = { tt = 5, memcat = L.activememcat, marked = 0 },
					ts = lstring[1](L, string.format("%s:%d: %s", source.data, line, fmt:format(...)))
				}
			}
		}
		L.top += 1
	else
		L.stack[L.top] = {
			tt = 5, memcat = L.activememcat, marked = 0,
			extra = {},
			value = {
				gc = {
					gch = { tt = 5, memcat = L.activememcat, marked = 0 },
					ts = lstring[1](L, fmt:format(...))
				}
			}
		}
		L.top += 1
	end

	error("LUA_ERRRUN")
end

return {
	luaG_runerror :: any
}
