local LUA = {}

LUA.MINSTACK = 20
LUA.BASIC_STACK_SIZE = 2 * LUA.MINSTACK
LUA.EXTRA_STACK = 5

LUA.IMAXCSTACK = 8000

LUA.REGISTRYINDEX = (-LUA.IMAXCSTACK - 2000)
LUA.ENVIRONINDEX = (-LUA.IMAXCSTACK - 2001)
LUA.GLOBALSINDEX = (-LUA.IMAXCSTACK - 2002)

LUA.LBC_VERSION_MIN = 3
LUA.LBC_VERSION_MAX = 6

LUA.MULTRET = -1

local NILOBJ = newproxy(true)
local mt = getmetatable(NILOBJ)

mt.__tostring = function() return "nil" end
mt.__index = function() return nil end
mt.__newindex = function() end
mt.__call = function() error("attempt to call a nil value", 2) end
mt.__eq = function(a, b) return b == nil or b == NILOBJ end
mt.__len = function() error("attempt to get length of a nil value", 2) end
mt.__pairs = function() error("invalid argument #1 to 'pairs' (table expected, got nil)", 2) end
mt.__ipairs = function() error("invalid argument #1 to 'pairs' (table expected, got nil)", 2) end

mt.__metatable = false

LUA.NILOBJ = NILOBJ

LUA.PCRYIELD = 2
LUA.PCRC     = 1
LUA.PCRLUA   = 0

LUA.CALLINFO_RETURN = bit32.lshift(1, 0)

return table.freeze(LUA)
