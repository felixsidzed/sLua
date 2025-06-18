-- TODO: add gcstats and getheaptrigger shit

--!strict
--!optimize 2

local lstate = require("lstate")

type lua_State = lstate.lua_State
type Udata = lstate.Udata
type GCObject = lstate.GCObject
type TValue = lstate.TValue
type global_State = lstate.global_State
type Closure = lstate.Closure
type UpVal = lstate.UpVal
type LuaTable = lstate.LuaTable
type lua_Page = lstate.lua_Page
type Proto = lstate.Proto

function luaC_needsGC(L: lua_State): boolean
	return L.global.totalbytes >= L.global.GCthreshold
end

local function reallymarkobject(g: global_State, o: GCObject)
	--white2gray(o)
	o.gch.marked = bit32.band(o.gch.marked, bit32.bnot(3))
	if o.gch.tt == 5 then
		return

	elseif o.gch.tt == 8 then
		local mt = (o.u :: Udata).metatable
		o.gch.marked = bit32.bor(o.gch.marked, bit32.lshift(1, 2))
		if mt then
			local mtgc: GCObject = {
				gch = {
					tt = mt.tt,
					marked = mt.marked,
					memcat = mt.memcat
				},
				h = mt
			}
			if bit32.btest(mtgc.gch.marked, 3) then
				reallymarkobject(g, mtgc)
			end
		end

	elseif o.gch.tt == 12 then
		local uv = o.uv :: UpVal
		if bit32.btest(o.gch.marked, 3) then
			local uvgc = setmetatable({}, {
				__index = function(t, k): any
					if k == "gch" then return { tt = uv.tt, marked = uv.marked, memcat = uv.memcat } end
					return uv.v
				end,
				__newindex = uv.v
			})
			reallymarkobject(g, uvgc :: any)
		end

	elseif o.gch.tt == 7 then
		(o.cl :: Closure).gclist = g.gray
		g.gray = o
	
	elseif o.gch.tt == 6 then
		(o.h :: LuaTable).gclist = g.gray
		g.gray = o

	elseif o.gch.tt == 9 then
		(o.th :: lua_State).gclist = g.gray
		g.gray = o
	
	elseif o.gch.tt == 10 then
		o.gch.marked = bit32.bor(o.gch.marked, bit32.lshift(1, 2))
	
	elseif o.gch.tt == 11 then
		(o.p :: Proto).gclist = g.gray
		g.gray = o
	
	else
		assert(false)

	end
end

function sweepgcopage(L: lua_State, page: lua_Page): number
	local start: number = 0
	local end_: number = 0
	local busyBlocks: number = 0
	local blockSize: number = 0
	--luaM_getpagewalkinfo
	do
		local blockCount: number = (page.pageSize - 64 --[[offsetof(lua_Page, data)]]) // page.blockSize
		
		start = page.freeNext + page.blockSize
		end_ = blockCount * page.blockSize
		busyBlocks = page.busyBlocks
		blockSize = page.blockSize
	end

	assert(busyBlocks > 0)

	local g: global_State = L.global

	local deadmask: number = bit32.bxor(g.currentwhite, 7--[[WHITEBITS]]) --otherwhite(g)
	assert(bit32.btest(deadmask, 3--[[FIXEDBIT]]))

	local newwhite: number = bit32.band(g.currentwhite, 7--[[bit2mask(WHITE0BIT, FIXEDBIT)]])--luaC_white(g)

	for pos = start, end_, blockSize do
		local gco: GCObject = page.data[pos]

        if gco.gch.tt == 0--[[LUAT_NIL]] then
            continue
        end

        if bit32.band(bit32.bxor(gco.gch.marked, 3), deadmask) ~= 0 then
            gco.gch.marked = bit32.bor(bit32.band(gco.gch.marked, 248), newwhite)
        else
            page.data[pos] = nil -- freobj(L, gco, page)

            busyBlocks -= 1
            if busyBlocks == 0 then
                return (pos - start) // blockSize + 1
            end
        end
	end

	return (end_ - start) // blockSize
end

function atomic(L: lua_State)
	local g: global_State = L.global
	assert(g.gcstate == 3)

	local work: number = 0

	-- remark occasional upvalues of (maybe) dead threads
	--remarkupvals(g)
	do
		-- for (UpVal* uv = g->uvhead.u.open.next; uv != &g->uvhead; uv = uv->u.open.next)
		local uv = g.uvhead.u.open.next
		while uv ~= g.uvhead do
			work += 40 -- sizeof(UpVal)

			assert(uv.v ~= uv.u.value)
			assert(uv.u.open.next.u.open.prev == uv and uv.u.open.prev.u.open.next == uv)
			--obj2gco(uv)
			local uv_: GCObject = {
				gch = {
					marked = uv.marked,
					memcat = uv.memcat,
					tt = uv.tt
				},
				uv = uv
			}
			assert(bit32.btest(uv_.gch.marked, 2--[[BLACKBIT]]))

			if bit32.btest(uv_.gch.marked, 7--[[WHITEBITS | bitmask(BLACKBIT))]]) then
				if (uv.v:: TValue).tt < 5 and bit32.btest(uv_.gch.marked, 7--[[WHITEBITS]]) then
					reallymarkobject(g, uv_)
				end
			end

			uv = uv.u.open.next
		end
	end
	-- traverse objects caught by write barrier and by 'remarkupvals'
	while #g.gray ~= 0 do
		--work += propagatemark(g) -- TODO
		table.clear(g.gray)
	end

	g.gray = g.weak
	table.clear(g.grayagain)
	while #g.gray ~= 0 do
		--work += propagatemark(g) -- TODO
		table.clear(g.gray)
	end

	-- remove collected objects from weak tables
	table.clear(g.weak)

	-- clearupvals(L)
	do
		-- for (UpVal* uv = g->uvhead.u.open.next; uv != &g->uvhead; uv = uv->u.open.next)
		local uv = g.uvhead.u.open.next
		while uv ~= g.uvhead do
			work += 40 -- sizeof(UpVal)

			assert(uv.v ~= uv.u.value)
			assert(uv.u.open.next.u.open.prev == uv and uv.u.open.prev.u.open.next == uv)
			--obj2gco(uv)
			local uv_: GCObject = {
				gch = {
					marked = uv.marked,
					memcat = uv.memcat,
					tt = uv.tt
				},
				uv = uv
			}
			assert(bit32.btest(uv_.gch.marked, 2--[[BLACKBIT]]))

			if uv.markedopen then
				assert(bit32.btest(uv_.gch.marked, 7--[[WHITEBITS | bitmask(BLACKBIT))]]))
				uv.markedopen = false
				uv = uv.u.open.next
			else
				local next_: UpVal = uv.u.open.next
				uv = nil :: any
				--luaF_closeupval(L, uv, /* dead= */ iswhite(obj2gco(uv)));
				uv = next_
			end
		end
	end

	g.currentwhite = bit32.bxor(g.currentwhite, 7--[[WHITEBITS]]) -- otherwhite(g)
	g.sweepgcopage = g.allgcopages
	g.gcstate = 4 -- GCSsweep

	return work
end

function gcstep(L: lua_State, limit: number): number
	local cost: number = 0
	local g: global_State = L.global

	if g.gcstate == 0 then -- GCSpause
		table.clear(g.gray)
		table.clear(g.grayagain)
		table.clear(g.weak)
		local th: GCObject = {
			gch = {
				tt = g.mainthread.tt,
				marked = g.mainthread.marked,
				memcat = g.mainthread.memcat
			},
			th = g.mainthread
		}
		if bit32.btest(th.gch.marked, 3) then
			reallymarkobject(g, th)
		end

		-- make global table be traversed before main stack
		local h: GCObject = {
			gch = {
				tt = g.mainthread.gt.tt,
				marked = g.mainthread.gt.marked,
				memcat = g.mainthread.gt.memcat
			},
			h = g.mainthread.gt
		}
		if bit32.btest(h.gch.marked, 3) then
			reallymarkobject(g, h)
		end
		
		if g.registry.tt < 5 and bit32.btest((g.registry.value.gc :: GCObject).gch.marked, 7) then
			reallymarkobject(g, (g.registry.value.gc :: GCObject))
		end

		for i = 0, 11 do -- LUA_T_COUNT
			if g.mt[i] then
				local mt = g.mt[i]
				local mtgc: GCObject = {
					gch = {
						tt = mt.tt,
						marked = mt.marked,
						memcat = mt.memcat
					},
					h = mt
				}
				if bit32.btest(mtgc.gch.marked, 3) then
					reallymarkobject(g, mtgc)
				end
			end
		end
		
		g.gcstate = 1 -- GCSpropagate
		--assert(g.gcstate == 1) -- GCSpropagate

	elseif g.gcstate == 1 then -- GCSpropagate
		while #g.gray ~= 0 and cost < limit do
			--cost += propagatemark(g) -- TODO
		end

		if #g.gray == 0 then
			g.gray = g.grayagain
			g.grayagain = {}
			g.gcstate = 2 -- GCSpropagateagain
		end

	elseif g.gcstate == 2 then -- GCSpropagateagain
		while #g.gray ~= 0 and cost < limit do
			--cost += propagatemark(g) -- TODO
		end

		if #g.gray == 0 then -- no more `gray' objects
			g.gcstate = 3 -- GCSatomic
		end

	elseif g.gcstate == 3 then -- GCSatomic
		cost = atomic(L) -- finish mark phase
		assert(g.gcstate == 4) -- GCSsweep

	elseif g.gcstate == 4 then -- GCSsweep
		while g.sweepgcopage and cost < limit do
			local next_: lua_Page = g.sweepgcopage.listnext

			local steps: number = sweepgcopage(L, g.sweepgcopage)

			g.sweepgcopage = next_
			cost += steps * 16 -- GC_SWEEPPAGESTEPCOST

			if g.sweepgcopage == nil then
				--obj2gco(g->mainthread)
				local m = g.mainthread
				local th: GCObject = {
					gch = {
						marked = m.marked,
						memcat = m.memcat,
						tt = m.tt
					},
					th = m
				}
				--makewhite(g, th)
				th.gch.marked = bit32.bor(
					bit32.band(th.gch.marked, 248--[[maskmarks]]),
					bit32.band(g.currentwhite, 7--[[bit2mask(WHITE0BIT, FIXEDBIT)]])--luaC_white(g)
				)

				--shrinkbuffers(L)

				g.gcstate = 0 -- GCSpause
			end
		end

	else
		error("Unexpected GC state")

	end

	return cost
end

function luaC_step(L: lua_State): number
	local g: global_State = L.global

	local lim: number = g.gcstepsize * g.gcstepmul // 100 -- how much to work
	assert(g.totalbytes >= g.GCthreshold)
	local debt: number = g.totalbytes - g.GCthreshold

	if g.cb.interrupt then
		g.cb.interrupt(L, 0)
	end

	local lastgcstate: number = g.gcstate
	local work: number = gcstep(L, lim)

	local actualstepsize: number = work * 100 // g.gcstepmul

	if g.gcstate == 0 then
		--local heapgoal: number = (g.totalbytes // 100) * g.gcgoal
		--local heaptrigger: number = getheaptrigger(g, heapgoal)

		--g.GCthreshold = heaptrigger
	else
		g.GCthreshold = g.totalbytes + actualstepsize

		-- compensate if GC is "behind schedule" (has some debt to pay)
		if g.GCthreshold >= debt then
			g.GCthreshold -= debt
		end
	end

	if g.cb.interrupt then
		g.cb.interrupt(L, lastgcstate)
	end

	return actualstepsize
end

return {
	luaC_needsGC :: any,
	luaC_step,
	luaC_checkGC = function(L: lua_State)
		if luaC_needsGC(L) then
			luaC_step(L)
		end
	end
} :: any
