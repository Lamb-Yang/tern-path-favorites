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
	undo: { path: string, idx: number }?,
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
	if clean == "" then return "/" end
	local name = string.match(clean, "([^/]+)$")
	return name or clean
end

local function utf16_len(text: string): number
	local n = 0
	for _, code in utf8.codes(text) do
		n += if code > 0xFFFF then 2 else 1
	end
	return n
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

local function copy_to_clipboard(path: string, cx)
	cx:copy(path)
	cx:toast("success", "路径收藏", "已复制路径")
end

local function reveal_in_finder(path: string, cx)
	if not valid_path(path) then
		cx:toast("error", "路径收藏", "目录不存在：" .. path)
		return
	end
	local ok = pcall(tern.process.run, { "open", path }, function() end)
	if not ok then
		cx:toast("error", "路径收藏", "无法在 Finder 中打开")
	end
end

local function remove_selected(s: State, cx)
	local selected = visible_paths(s)[s.sel]
	if not selected then return end
	for i, path in s.paths do
		if path == selected then
			table.remove(s.paths, i)
			s.undo = { path = selected, idx = i }
			break
		end
	end
	s.sel = math.min(s.sel, math.max(#visible_paths(s), 1))
	save_paths(s)
	cx:toast("info", "路径收藏", "已移除 " .. path_name(selected), "⌘Z 撤销")
end

local function undo_remove(s: State, cx): boolean
	local undo = s.undo
	if not undo then return false end
	s.undo = nil
	for _, path in s.paths do
		if path == undo.path then return false end
	end
	local idx = math.min(math.max(undo.idx, 1), #s.paths + 1)
	table.insert(s.paths, idx, undo.path)
	s.sel = idx
	save_paths(s)
	cx:toast("success", "路径收藏", "已恢复 " .. path_name(undo.path))
	return true
end

local function row_node(s: State, path: string, idx: number): any
	local is_current = path == s.cwd
	local acts = {
		click = "select",
		dblclick = "open",
		menu = { "在新 tab 打开", "复制路径", "在 Finder 中显示", "删除" },
	}
	local icon = ui.node("text", {
		role = "pf-icon",
		title = if is_current then "当前工作目录" else nil,
		spans = { ui.span(if is_current then "●" else "○") },
	})
	local name = ui.node("text", {
		role = "pf-name",
		grow = 1,
		truncate = "end",
		actions = acts,
		spans = { ui.span(path_name(path)) },
	})
	local full = ui.node("text", {
		role = "pf-path",
		truncate = "middle",
		actions = acts,
		spans = { ui.span(path) },
	})
	return ui.node("col", {
		key = "r" .. idx,
		gap = "xs",
		role = "pf-row",
		tone = if idx == s.sel then "accent" else nil,
		mark = if idx == s.sel then "pick" else nil,
		actions = acts,
	}, { ui.node("row", { gap = "sm", role = "pf-rowhead" }, { icon, name }), full })
end

local favorites: BlockDef<State> = {
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
		-- 输入框在 view 之后才存在：稍等再聚焦，键盘一进来就能搜索。
		tern.timer(60, function()
			pcall(function() cx:frame({ { "focus", "main.head.q" } }) end)
		end)
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
			local msg = if #s.paths == 0
				then "还没有收藏路径\n「收藏当前」保存正在用的目录\n「浏览新增」挑一个别的"
				else "没有匹配「" .. s.filter .. "」的路径"
			table.insert(rows, ui.node("col", { role = "pf-empty" }, { ui.text({ ui.span(msg, "muted") }) }))
		end
		local head = ui.node("col", { key = "head", gap = "sm" }, {
			ui.node("row", { key = "cwdrow", gap = "sm", role = "pf-cwdrow" }, {
				ui.node("text", { role = "pf-cwdlabel", spans = { ui.span("当前", "muted") } }),
				ui.node("text", { role = "pf-current", grow = 1, truncate = "middle", spans = { ui.span(s.cwd) } }),
			}),
			ui.node("input", {
				key = "q",
				text = s.filter,
				cursor = utf16_len(s.filter),
				placeholder = "搜索收藏路径…",
			}),
			ui.node("row", { key = "actions", gap = "sm", role = "pf-head" }, {
				ui.node("text", { role = "pf-count", grow = 1, spans = { ui.span(if s.filter == "" then #s.paths .. " 条" else #vis .. "/" .. #s.paths .. " 条") } }),
				ui.button("收藏当前", { icon = "star", size = "sm", actions = { click = "add-current" } }),
				ui.button("浏览新增", { icon = "folder", size = "sm", actions = { click = "pick-directory" } }),
				ui.button("删除", { size = "sm", variant = "quiet", actions = { click = "delete-selected" } }),
			}),
		})
		local hint = if s.err
			then "视图错误：" .. s.err
			elseif s.undo
			then "已移除 " .. path_name(s.undo.path) .. " · ⌘Z 撤销"
			else "↑↓ 选择 · ⏎ 打开 · ⌘C 复制 · ⇧⏎ Finder"
		return {
			main = ui.col({ head, ui.node("col", { key = "list", gap = "xs", role = "pf-list" }, rows) }),
			dock = ui.col({ ui.text({ ui.span(hint, "muted") }) }),
		}
	end,
	key = function(s, key, cx)
		local cmd = key.meta or key.ctrl
		if key.name == "up" then s.sel = math.max(s.sel - 1, 1)
		elseif key.name == "down" then s.sel = math.min(s.sel + 1, math.max(#visible_paths(s), 1))
		elseif key.name == "enter" then
			local path = visible_paths(s)[s.sel]
			if not path then return true end
			if key.shift then reveal_in_finder(path, cx) else open_path(path, cx) end
		elseif key.name == "delete" then remove_selected(s, cx)
		elseif cmd and key.name == "c" then
			local path = visible_paths(s)[s.sel]
			if path then copy_to_clipboard(path, cx) end
		elseif cmd and key.name == "z" then
			if not undo_remove(s, cx) then return false end
		elseif key.name == "escape" then
			if s.filter == "" then return false end
			s.filter = ""
		elseif key.name == "backspace" then
			if s.filter == "" then return false end
			s.filter = string.gsub(s.filter, "[%z\1-\127\194-\244][\128-\191]*$", "")
		elseif key.text and #key.text > 0 and not key.ctrl and not key.meta and not key.alt then s.filter ..= key.text
		else return false end
		return true
	end,
	event = function(s, ev, cx)
		if ev.ev == "error" then s.err = tostring(ev.msg or "视图错误"); return end
		if ev.ev == "focus" then
			cx:frame({ { "focus", "main.head.q" } })
			return
		end
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
		elseif ev.act == "在新 tab 打开" then s.sel = idx :: number; open_path(path, cx)
		elseif ev.act == "复制路径" then s.sel = idx :: number; copy_to_clipboard(path, cx)
		elseif ev.act == "在 Finder 中显示" then s.sel = idx :: number; reveal_in_finder(path, cx)
		elseif ev.act == "删除" then s.sel = idx :: number; remove_selected(s, cx)
		end
	end,
 	save = function(s) return { sel = s.sel } end,
}

tern.block.define("favorites", favorites)
