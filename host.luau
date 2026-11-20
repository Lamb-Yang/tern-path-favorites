--!strict
-- Path Favorites · host half

local ui = tern.ui

type State = {
	cwd: string,
	paths: { string },
	sel: number,
	filter: string,
	rev: number,
	err: string?,
}

local function visible_paths(s: State): { string }
	local out: { string } = {}
	local q = string.lower(s.filter)
	for _, path in s.paths do
		if q == "" or string.find(string.lower(path), q, 1, true) then table.insert(out, path) end
	end
	return out
end

local function load_paths(): { string }
	local value = tern.kv.get("paths")
	if type(value) ~= "table" then
		return {}
	end
	local out: { string } = {}
	for _, path in value do
		if type(path) == "string" and path ~= "" then
			table.insert(out, path)
		end
	end
	return out
end

local function save_paths(s: State)
	tern.kv.set("paths", s.paths)
	s.rev += 1
end

local function path_name(path: string): string
	local clean = string.gsub(path, "/+$", "")
	local name = string.match(clean, "([^/]+)$")
	return name or clean
end

local function valid_path(path: string): boolean
	return tern.fs.exists(path)
end

local function open_path(path: string, cx)
	if not valid_path(path) then
		cx:toast("error", "路径收藏", "目录不存在：" .. path)
		return
	end
	tern.kv.set("open", { path = path })
	cx:open("path-favorites://open")
end

local function add_current(s: State, cx)
	for _, path in s.paths do
		if path == s.cwd then
			cx:toast("info", "路径收藏", "该路径已经收藏")
			return
		end
	end
	table.insert(s.paths, s.cwd)
	s.sel = #s.paths
	save_paths(s)
	cx:toast("success", "路径收藏", "已收藏 " .. s.cwd)
end

local function remove_selected(s: State, cx)
	local selected = visible_paths(s)[s.sel]
	if not selected then return end
	for i, path in s.paths do
		if path == selected then table.remove(s.paths, i) break end
	end
	s.sel = math.min(s.sel, math.max(#visible_paths(s), 1))
	save_paths(s)
	cx:toast("info", "路径收藏", "已移除 " .. selected)
end

local function row_node(s: State, path: string, idx: number): any
	local acts = { click = "select", dblclick = "open", menu = { "删除" } }
	local name = ui.node("text", {
		role = "pf-name",
		grow = 1,
		truncate = "end",
		spans = { ui.span(path_name(path)) },
	})
	local full = ui.node("text", {
		role = "pf-path",
		truncate = "middle",
		spans = { ui.span(path, "path") },
	})
	return ui.node("col", {
		key = "r" .. idx,
		gap = "xs",
		role = "pf-row",
		tone = if idx == s.sel then "accent" else nil,
		mark = if idx == s.sel then "pick" else nil,
		actions = acts,
	}, { name, full })
end

local favorites: BlockDef<State> = {
	font = "sans",
	init = function(cx, args, saved)
		local cwd = tern.kv.get("current_cwd")
		if type(cwd) ~= "string" or cwd == "" then
			cwd = (args and args[1] and args[1] ~= "") and args[1] or (cx.cwd or tern.getenv("HOME") or "/")
		end
		local s: State = {
			cwd = cwd,
			paths = load_paths(),
			sel = if saved then math.max(tonumber(saved.sel) or 1, 1) else 1,
			filter = "",
			rev = 0,
			err = nil,
		}
		local function refresh()
			local alive = false
			for _, p in tern.pane.list() do if p.pane == cx.pane then alive = true break end end
			if not alive then return end
			local current = tern.kv.get("current_cwd")
			if type(current) == "string" and current ~= "" and current ~= s.cwd then
				s.cwd = current
				cx:render()
			end
			local paths = load_paths()
			local changed = #paths ~= #s.paths
			if not changed then
				for i, path in paths do
					if path ~= s.paths[i] then changed = true break end
				end
			end
			if changed then
				s.paths = paths
				s.sel = math.min(s.sel, math.max(#paths, 1))
				cx:render()
			end
			tern.timer(500, refresh)
		end
		tern.timer(500, refresh)
		return s
	end,
	title = function(_s)
		return "路径收藏"
	end,
 	view = function(s, _cx)
 		local vis = visible_paths(s)
 		if s.sel > #vis and #vis > 0 then s.sel = #vis end
 		local rows: { any } = {}
 		for i, path in vis do rows[i] = row_node(s, path, i) end
 		if #rows == 0 then
 			table.insert(rows, ui.text({ ui.span(if #s.paths == 0 then "还没有收藏路径" else "没有匹配路径", "muted") }))
 		end
 		local head = ui.node("col", { key = "head", gap = "sm" }, {
 			ui.node("text", { role = "pf-current", truncate = "middle", spans = { ui.span(s.cwd, "path") } }),
 			ui.node("row", { key = "actions", gap = "sm", role = "pf-head" }, {
 				ui.node("text", { role = "pf-count", grow = 1, spans = { ui.span(#vis .. " / " .. #s.paths .. " 条", "mono") } }),
 				ui.button("收藏当前路径", { actions = { click = "add-current" } }),
				ui.button("新增收藏", { actions = { click = "pick-directory" } }),
 				ui.button("删除选中", { variant = "quiet", actions = { click = "delete-selected" } }),
 			}),
 			ui.node("input", { key = "q", text = s.filter, placeholder = "搜索收藏路径…" }),
 		})
 		return {
 			main = ui.col({ head, ui.node("col", { key = "list", gap = "xs" }, rows) }),
 			dock = ui.col({ ui.text({ ui.span("↑↓ 选择    Enter 新 tab 打开    Delete 删除", "muted") }) }),
 		}
 	end,
 	key = function(s, key, cx)
 		if key.name == "up" then s.sel = math.max(s.sel - 1, 1)
 		elseif key.name == "down" then s.sel = math.min(s.sel + 1, math.max(#visible_paths(s), 1))
 		elseif key.name == "enter" then
 			local path = visible_paths(s)[s.sel]
 			if path then open_path(path, cx) end
 		elseif key.name == "delete" then remove_selected(s, cx)
 		elseif key.name == "backspace" then
 			if s.filter ~= "" then s.filter = string.gsub(s.filter, "[%z\1-\127\194-\244][\128-\191]*$", "") end
 		elseif key.text and #key.text > 0 and not key.ctrl and not key.meta and not key.alt then s.filter ..= key.text
 		else return false end
 		return true
 	end,
 	event = function(s, ev, cx)
 		if ev.ev == "error" then s.err = tostring(ev.msg or "视图错误"); return end
 		if ev.ev ~= "action" then return end
 		if ev.act == "add-current" then add_current(s, cx); return end
		if ev.act == "pick-directory" then
			tern.kv.set("pick_directory", { path = s.cwd })
			cx:open("path-favorites://pick")
			return
		end
 		if ev.act == "delete-selected" then remove_selected(s, cx); return end
 		local idx = tonumber(string.match(ev.id or "", "%.r(%d+)"))
 		local path = if idx then visible_paths(s)[idx] else nil
 		if not path then return end
 		if ev.act == "select" then s.sel = idx :: number
 		elseif ev.act == "open" then s.sel = idx :: number; open_path(path, cx)
 		elseif ev.act == "删除" then s.sel = idx :: number; remove_selected(s, cx) end
 	end,
 	save = function(s) return { sel = s.sel } end,
}

tern.block.define("favorites", favorites)
