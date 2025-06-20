--!strict
--!optimize 2

local lstring = require("lstring")
local lstate = require("lstate")

type lua_State = lstate.lua_State
type CallInfo = lstate.CallInfo
type TString = lstate.TString
type Proto = lstate.Proto
type TValue = lstate.TValue

function luaG_runerror(L: lua_State, fmt: string, ...)
	local ci: CallInfo = L.ci[L.cip]
	if L.ci and not ci.func.isC and ci.func.l then
		local p: Proto = ci.func.l.p
		local source: TString = p.source
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

function luaG_indexerror(L: lua_State, a: TValue, b: TValue): ()
	luaG_runerror(L, "attempt to index %s with %s", L.global.ttname[a.tt], L.global.ttname[b.tt])
end

function luaG_readonlyerror(L: lua_State): ()
	luaG_runerror(L, "attempt to modify a read-only table")
end

return {
	luaG_runerror :: any,
	luaG_indexerror,
	luaG_readonlyerror
}
