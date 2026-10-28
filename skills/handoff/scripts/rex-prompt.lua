-- Deliver a handoff prompt to an agent in a Rex pane and confirm that it started.
--
--   rex do rex-prompt.lua -s SESSION -b CALLER_BLOCK --json \
--     (block=ID | direction=left|right|up|down) text=PROMPT [launch=COMMAND] [settle=SECONDS]
--
-- direction picks the pane beside the caller. launch types COMMAND into a shell pane first and
-- waits for the agent it starts to report idle. Agents report state through program status
-- (OSC 7501); the script returns { ok, block, app, state, reason? } as JSON.

local terminal = "com.superlogical.terminal"
local shells = { zsh = true, bash = true, fish = true, sh = true }
local args = rex.args
local eps = 1e-6

local function call(block, method, extra)
	local a = extra or {}
	a.block_id = block
	return rex.block.call(terminal, method, a)
end

local function foreground(block)
	local p = call(block, "process")
	return p and p.foreground and p.foreground.name
end

-- The root record is the program's own status; child records belong to its workers.
local function root_record(block)
	local r = call(block, "program_status")
	if not r or not r.records then
		return nil
	end
	for _, rec in ipairs(r.records) do
		if rec.id == nil or rec.id == "" then
			return rec
		end
	end
	return r.records[1]
end

local function type_line(block, text)
	call(block, "write", { data = text })
	rex.sleep(0.3)
	call(block, "write", { data = "\r" })
end

-- Waits for the block's next status report whose state passes accept(state).
local function wait_state(block, accept, seconds)
	local ev = rex.wait("terminal.program_status_changed", function(e, ctx)
		return ctx.block_id == block and e.record ~= nil and accept(e.record.state)
	end, seconds)
	return ev and ev.record
end

local function collect(node, out)
	if node.block_id then
		out[#out + 1] = { id = node.block_id, rect = node.rect }
	elseif node.split then
		collect(node.split.before, out)
		collect(node.split.after, out)
	end
end

-- Finds the one tiled pane that shares an edge with the caller on the given side.
local function neighbor(direction)
	local view, err = rex.session.view({})
	if not view then
		return nil, err
	end
	for _, w in ipairs(view.windows) do
		local panes = {}
		for _, layer in ipairs(w.layers) do
			if layer.kind == "tiled" then
				collect(layer.layout, panes)
			end
		end
		local me
		for _, p in ipairs(panes) do
			if p.id == rex.block_id then
				me = p.rect
			end
		end
		if me then
			local x, y, wd, h = me[1], me[2], me[3], me[4]
			local found = {}
			for _, p in ipairs(panes) do
				local r = p.rect
				local beside_v = r[2] < y + h - eps and r[2] + r[4] > y + eps
				local beside_h = r[1] < x + wd - eps and r[1] + r[3] > x + eps
				local hit = (direction == "right" and beside_v and math.abs(r[1] - (x + wd)) < eps)
					or (direction == "left" and beside_v and math.abs(r[1] + r[3] - x) < eps)
					or (direction == "down" and beside_h and math.abs(r[2] - (y + h)) < eps)
					or (direction == "up" and beside_h and math.abs(r[2] + r[4] - y) < eps)
				if hit then
					found[#found + 1] = p.id
				end
			end
			if #found == 1 then
				return found[1]
			end
			local what = #found == 0 and "no pane " or "several panes "
			return nil, what .. tostring(direction) .. " of the caller", found
		end
	end
	return nil, "the caller is not in a tiled layout; pass -b with its block ID"
end

local block = args.block
if not block then
	if not args.direction then
		return { ok = false, reason = "pass block= or direction=" }
	end
	local err, candidates
	block, err, candidates = neighbor(args.direction)
	if not block then
		return { ok = false, reason = err, candidates = candidates }
	end
end
if type(args.text) ~= "string" or args.text == "" then
	return { ok = false, block = block, reason = "pass text=" }
end

local rec
if args.launch then
	local fg = foreground(block)
	if not shells[fg] then
		return { ok = false, block = block, reason = "launch needs a shell at its prompt; foreground is " .. tostring(fg) }
	end
	type_line(block, args.launch)
	rec = wait_state(block, function(s)
		return s == "idle"
	end, 60)
	if not rec then
		return { ok = false, block = block, foreground = foreground(block), reason = "the agent did not report idle within 60s" }
	end
else
	local fg = foreground(block)
	rec = root_record(block)
	if shells[fg] or not rec then
		return { ok = false, block = block, foreground = fg, reason = "no agent is running in this pane" }
	end
end

if rec.state == "working" or rec.state == "blocked" then
	return { ok = false, block = block, app = rec.app, state = rec.state, reason = "the agent is busy; nothing was sent" }
end

type_line(block, args.text)
local started = wait_state(block, function(s)
	return s ~= "idle"
end, 10)
if not started then
	local now = root_record(block)
	return {
		ok = false,
		block = block,
		app = rec.app,
		state = now and now.state,
		reason = "no status change within 10s of sending; read the pane before re-sending",
	}
end

local state = started.state
if state == "working" then
	local settled = wait_state(block, function(s)
		return s ~= "working"
	end, tonumber(args.settle) or 15)
	if settled then
		state = settled.state
	end
end

local reasons = { blocked = "the agent is waiting on the user", error = "the agent reported an error" }
return { ok = reasons[state] == nil, block = block, app = started.app or rec.app, state = state, reason = reasons[state] }
