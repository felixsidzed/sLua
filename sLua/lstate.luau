--!strict
--!optimize 2

local LUA = require("lconf.luau")

export type TValue = number | string | boolean | { any } | { [any]: any } | (...any) -> ...any | thread | vector
export type StkId = TValue

export type lua_Continuation = (L: lua_State, status: number) -> number

export type lua_CFunction = (L: lua_State) -> number

export type CClosure = {
	f: lua_CFunction,
	cont: lua_Continuation?,
	debugname: string,
	upvals: { TValue }
}

export type LClosure = {
	p: Proto,
	uprefs: { TValue }
}

export type lua_Closure = {
	isC: boolean,
	nupvalues: number,
	stacksize: number,
	preload: number,

	env: { [string]: any },
	safeenv: boolean, -- uhhhhhhh

	c: CClosure?,
	l: LClosure?
}

export type global_State = {
	userdata: any,
	mainthread: lua_State,
	pseudotemp: any,
	registry: TValue
}

export type CallInfo = {
	base: number,
	func: lua_Closure,
	top: number,
	savedpc: { number },

	nresults: number,
	flags: number
}

export type UpVal = {
	markedopen: number,

	v: TValue,
	u: {
		value: TValue,
		open: {
			prev: { UpVal },
			next: { UpVal },

			threadnext: { UpVal },
		}?
	}
}

export type lua_State = {
	top: number,
	base: number,
	global: global_State,
	ci: CallInfo,
	stack: { StkId },
	stack_last: { StkId },

	end_ci: CallInfo,
	base_ci: CallInfo,
	cip: CallInfo, -- no pointers so i cant use "L->ci - 1" to get parent :(

	stacksize: number,
	size_ci: number,

	nCcalls: number,
	baseCcalls: number,

	cachedslot: number,

	gt: { [string]: any },
	openupval: { UpVal },

	namecall: string,

	userdata: any,
}

export type LocVar = {
	varname: string,
	startpc: number,
	endpc: number,
	reg: number
}

export type Proto = {
	source: string,
	code: { number },
	sizecode: number,

	bytecodeid: number,

	maxstacksize: number,
	numparams: number,
	nups: number,
	is_vararg: boolean,

	flags: number,

	typeinfo: { any },
	sizetypeinfo: number,

	k: { any },
	sizek: number,

	p: { Proto },
	sizep: number,

	linedefined: number,
	debugname: string,

	linegaplog2: number,
	lineinfo: { number },
	sizelineinfo: number,

	locvars: { LocVar },
	sizelocvars: number,

	upvalues: { string },
	sizeupvalues: number
}

function newstate(userdata: any): lua_State
	-- haha type checking bypass ezzzzz
	local L: lua_State = {} :: lua_State

	L.stacksize = LUA.BASIC_STACK_SIZE + LUA.EXTRA_STACK
	L.stack = table.create(L.stacksize)

	L.top = 0
	L.base = L.top

	L.global = {
		userdata = userdata,
		mainthread = L,
		pseudotemp = {},
		registry = {}
	}
	L.gt = {}

	L.base_ci = {
		base = L.base,
		top = L.top,
		flags = 0,
		func = nil :: any,
		nresults = 0,
		savedpc = {}
	}
	L.ci = L.base_ci

	L.userdata = userdata

	return L
end

return {
	lua_newstate = newstate,
	luaL_newstate = newstate
}
