--!strict
--!optimize 2

local sLua = require("../sLua.luau")

export type Value = {
	gc: GCObject?,
	p: any?,
	n: number?,
	b: boolean?,
	v: { number }? -- v[0], v[1] live here; v[2] lives in TValue::extra
}

export type TValue = {
	value: Value,
	extra: { number },
	tt: number
}

export type TString = {
	tt: number, marked: number, memcat: number,
	-- 1 byte padding

	atom: number,

	-- 2 byte padding

	next: TString, -- next string in the hash table bucket

	hash: number,
	len: number,

	data: string
}

local luaO_nilobject: TValue = {
	value = {},
	extra = {},
	tt = 0
}

export type lua_Callbacks = {
	userdata: any?, -- arbitrary userdata pointer that is never overwritten by Luau
	
	interrupt: (L: lua_State, gc: number) -> (),
	panic: (L: lua_State, errcode: number) -> (),

	userthread: (LP: lua_State, L: lua_State) -> (),

	useratom: (s: string, l: number) -> number,

	debugbreak: (L: lua_State) -> (),
	debugstep: (L: lua_State) -> (),
	debuginterrupt: (L: lua_State) -> (),
	debugprotectederror: (L: lua_State) -> (),
}

export type lua_ExecutionCallbacks = {
	context: any?,
	close: (L: lua_State) -> (),
	destroy: (L: lua_State, p: Proto) -> (),
	enter: (L: lua_State, p: Proto) -> number,
	disable: (L: lua_State, p: Proto) -> (),
	getmemorysize: (L: lua_State, proto: Proto) -> number,
	gettypemapping: (L: lua_State, str: string, len: number) -> number,
}

export type stringtable = {
	hash: { TString },
	nuse: number, -- number of elements
	size: number
}

export type global_State = {
	strt: stringtable,

    currentwhite: number,
	gcstate: number, -- state of garbage collector

    gray: { GCObject }, -- list of gray objects
	grayagain: { GCObject }, -- list of objects to be traversed atomically
	weak: { GCObject }, -- list of weak tables (to be cleared)

    GCthreshold: number, -- when totalbytes > GCthreshold, run GC step
    totalbytes: number, -- number of bytes currently allocated
    gcgoal: number,
	gcstepmul: number,
    gcstepsize: number,

    freepages: lua_Page?, -- free page linked list for each size class for non-collectable objects
    freegcopages: lua_Page?, -- free page linked list for each size class for collectable objects
    allpages: lua_Page?, -- page linked list with all pages for all non-collectable object classes (available with LUAU_ASSERTENABLED)
    allgcopages: lua_Page?, -- page linked list with all pages for all collectable object classes
    sweepgcopage: lua_Page?, -- position of the sweep in 'allgcopages'

    memcatbytes: { number }, -- total amount of memory used by each memory category

    mainthread: lua_State,
    uvhead: UpVal,                                    -- head of double-linked list of all open upvalues
    mt: { LuaTable },                   -- metatables for basic types
    ttname: { TString },       -- names for basic types
    tmname: { TString },             -- array with tag-method names

    pseudotemp: TValue, -- storage for temporary values used in pseudo2addr

    registry: TValue, -- registry table, used by lua_ref and LUA_REGISTRYINDEX
    registryfree: number, -- next free slot in registry

    rngstate: number, -- PCG random number generator state
    ptrenckey: { number }, -- pointer encoding key for display

    cb: lua_Callbacks,
    ecb: lua_ExecutionCallbacks,
	
    udatamt: { LuaTable }, -- metatables for tagged userdata

    lightuserdataname: { TString }, -- names for tagged lightuserdata
}

export type lua_Page = {
	prev: lua_Page,
	next: lua_Page,

	listprev: lua_Page,
	listnext: lua_Page,

	pageSize: number,
	blockSize: number,

	freeList: any?,
	freeNext: number,
	busyBlocks: number,

	data: { GCObject }, -- since we cant cast char* to GCObject*, we will have to use an array of GCObjects directly
	align1: number,
	align2: any?
}

export type CallInfo = {
	base: number,
	func: Closure,
	pfunc: number,
	top: number,
	savedpc: number,

	nresults: number,
	flags: number
}

export type TKey = {
	value: Value,
	extra: { number },
	tt: number,
	next: number
}

export type LuaNode = {
	val: TValue,
	key: TKey
}

export type LuaTable = {
	tt: number, marked: number, memcat: number,

	tmcache: number,    -- 1<<p means tagmethod(p) is not present
    readonly: boolean,   -- sandboxing feature to prohibit writes to table
    safeenv: boolean,    -- environment doesn't share globals with other scripts
    lsizenode: number,  -- log2 of size of `node' array
    nodemask8: number, -- (1<<lsizenode)-1, truncated to 8 bits

    sizearray: number, -- size of `array' array
    u: {
        lastfree: number,  -- any free position is before this position
        aboundary: number, -- negated 'boundary' of `array' array; iff aboundary < 0
    },

	metatable: LuaTable?,
    array: { TValue },  -- array part
    node: { LuaNode }, -- LuaNode*
    gclist: { GCObject }
}

export type UpVal = {
	tt: number, marked: number, memcat: number,

	markedopen: boolean, -- uint8_t -- set if reachable from an alive thread (only valid during atomic)

	v: TValue | number, -- points to stack or to its own value
	u: {
		value: TValue, -- the value (when closed)
		open: {
			-- global double linked list (when open)
			prev: UpVal, -- UpVal*
			next: UpVal, -- UpVal*

			-- thread linked list (when open)
			threadnext: UpVal -- UpVal*
		}
	}
}

export type GCHeader = {
	tt: number, marked: number, memcat: number,
}

export type Buffer = {
	tt: number, marked: number, memcat: number,

	len: number,

	data: { number }
}

export type Udata = {
	tt: number, marked: number, memcat: number,
	
	tag: number,

	len: number,

	metatable: LuaTable?,

	data: { number }
}

export type LocVar = {
	varname: TString,
	startpc: number,
	endpc: number,
	reg: number
}

export type Proto = {
    tt: number, marked: number, memcat: number,

	nups: number,
    numparams: number,
    is_vararg: boolean,
    maxstacksize: number,
    flags: number,


    k: { TValue },
    code: { number },
    p: { Proto },
    codeentry: { number },

    --void* execdata;
	execdata: any?,
	exectarget: number,

    lineinfo: { number },
    abslineinfo: number,
    locvars: { LocVar },
    upvalues: { TString },
    source: TString,

    debugname: TString,
    debuginsn: { number },

    typeinfo: { number },

    userdata: any?,

    gclist: { GCObject },

    sizecode: number,
    sizep: number,
    sizelocvars: number,
    sizeupvalues: number,
    sizek: number,
    sizelineinfo: number,
    linegaplog2: number,
    linedefined: number,
    bytecodeid: number,
    sizetypeinfo: number
}

export type lua_CFunction = (lua_State) -> number

export type Closure = {
	tt: number, marked: number, memcat: number,

	isC: boolean,
	nupvalues: number,
	stacksize: number,
	preload: boolean, -- uint8_t

	gclist: { GCObject },
	env: LuaTable,

	c: {
		f: lua_CFunction,
		--cont: lua_Continuation,
		debugname: string,
		upvals: { TValue }
	}?,
	l: {
		p: Proto,
		uprefs: { TValue }
	}?
}

export type GCObject = {
	gch: GCHeader,
	ts: TString?,
	u: Udata?,
	cl: Closure?,
	h: LuaTable?,
	p: Proto?,
	uv: UpVal?,
	th: lua_State?, -- thread
	buf: Buffer?
}

export type lua_State = {
	tt: number, marked: number, memcat: number,
	status: number,

	activememcat: number,

	isactive: boolean,
	singlestep: boolean,

	top: number,
	base: number,
	global: global_State,
	ci: { CallInfo },
	cip: number,
	stack_last: { TValue },
	stack: { TValue },

	end_ci: number,
	base_ci: number,
	size_ci: number,

	stacksize: number,
	
	nCcalls: number,
	baseCcalls: number,
	cachedslot: number,
	gt: LuaTable,
	upval: { UpVal },
	gclist: { GCObject },

	namecall: TString?,

	userdata: any
}

local luaT_typenames = {
	-- ORDER TYPE
    "nil",
    "boolean",

    
    "userdata",
    "number",
    "vector",

    "string",

    
    "table",
    "function",
    "userdata",
    "thread",
    "buffer",
}

local luaT_eventname = {
	-- ORDER TM
    
    "__index",
    "__newindex",
    "__mode",
    "__namecall",
    "__call",
    "__iter",
    "__len",

    "__eq",

    
    "__add",
    "__sub",
    "__mul",
    "__div",
    "__idiv",
    "__mod",
    "__pow",
    "__unm",

    
    "__lt",
    "__le",
    "__concat",
    "__type",
    "__metatable",
}

local function nocollect(x)
	x.marked = bit32.bor(x.marked, bit32.lshift(1, 3))
	return x
end

local function stack_init(L1: lua_State, L: lua_State)
	L1.base_ci = 0
	L1.ci = { {} :: any }
	L1.cip = 1
	L1.size_ci = 8
	L1.end_ci = L1.base_ci + L1.size_ci - 1

	L1.stack = {}
	L1.stacksize = 45
	for i = 1, 45 do
		L1.stack[i] = luaO_nilobject
	end
	L1.top = 1
	L1.stack_last = L1.stack

	L1.ci[L.cip].func = nil :: any
	L1.ci[L.cip].base = L1.top
	L1.ci[L.cip].top = L1.top + 20
	L1.base = L1.ci[L.cip].base
end

local function f_luaopen(L: lua_State, userdata: any)
	local g : global_State = L.global
	stack_init(L, L)
	L.gt = sLua.luaH_new(L, 0, 2)
	local i_o: TValue = L.global.registry
	i_o.value.gc = sLua.luaH_new(L, 0, 2)
	i_o.tt = 6 -- LUA_TTABLE
	--checkliveness(L->globa, i_o)
	--luaS_resize(L, 32)
	for i = 1, #luaT_typenames do
		L.global.ttname[i] = nocollect(sLua.luaS_new(L, luaT_typenames[i]))
	end
	for i = 1, #luaT_eventname do
		L.global.tmname = nocollect(sLua.luaS_new(L, luaT_eventname[i]))
	end
	g.GCthreshold = 4 * g.totalbytes
end

function lua_newstate(userdata: any): lua_State
	local L = {}
	local g = ({} :: any) :: global_State

	L.tt = 9 -- LUA_TTHREAD
	L.marked = 7 -- bit2mask(WHITE0BIT, FIXEDBIT)
	g.currentwhite = L.marked
	L.memcat = 0

	L.global = g
	L.stack = {}
	L.stacksize = 0
	L.gt = nil
	L.openupval = {}
	L.size_ci = 0
	L.nCcalls = 0
	L.baseCcalls = 0
	L.status = 0
	L.base_ci = 0
	L.end_ci = 0
	L.ci = {}
	L.cip = 0
	L.namecall = nil
	L.singlestep = false
	L.isactive = false
	L.activememcat = 0
	L.userdata = userdata
	L.base = 0
	L.gclist = {}

	g.mainthread = (L :: any) :: lua_State
	g.uvhead = {
		u = {
			open = {
				prev = g.uvhead,
				next = g.uvhead
			}
		}
	} :: any
	g.GCthreshold = 0 -- mark it as unfinished state
	g.registryfree = 0
	g.rngstate = 0
	g.ptrenckey = { 1, 0, 0, 0 }
	g.strt = {
		hash = {},
		size = 0,
		nuse = 0
	}
	g.pseudotemp = luaO_nilobject
	L.global.registry = luaO_nilobject
	g.gcstate = 0 -- GCSpause
	g.gray = {}
	g.grayagain = {}
	g.weak = {}
	g.totalbytes = 6816 -- sizeof(LG)
	g.gcgoal = 200 -- LUAI_GCGOAL
	g.gcstepmul = 200 -- LUAI_GCSTEPMUL
	g.gcstepsize = 1 -- LUAI_GCSTEPSIZE
	g.freepages = nil
	g.freegcopages = nil
	g.allpages = nil
	g.allgcopages = nil
	g.sweepgcopage = nil
	g.udatamt = table.create(11) -- LUA_T_COUNT
	g.lightuserdataname = table.create(128) -- LUA_LUTAG_LIMIT
	g.memcatbytes = table.create(256, 0) -- LUA_MEMORY_CATEGORIES
	g.memcatbytes[1] = 6816 -- sizeof(LG)
	g.cb = {} :: any
	g.ecb = {} :: any

	g.ttname = {}
	g.tmname = {}

	f_luaopen(L :: any, userdata)

	-- TYPE CHECK BYPASS UD AS FUCKKKK
	return L :: any
end

return {
	lua_newstate,
	luaL_newstate = lua_newstate, -- no lua_Alloc
	luaO_nilobject = luaO_nilobject :: any
}
