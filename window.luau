--!strict
-- Path Favorites · window half

local KIND = "path-favorites.favorites"

local function current_cwd(cx): string
	local focused = cx.session:focused()
	local any: string? = nil
	for _, p in cx.session:panes() do
		local cwd = p.cwd
		if cwd and cwd ~= "" and p.kind ~= "plugin" then
			if p.pane == focused then return cwd end
			if any == nil then any = cwd end
		end
	end
	return any or (tern.getenv("HOME") or "/")
end

local function publish_cwd(cx)
	tern.kv.set("current_cwd", current_cwd(cx))
end

local function open_list(cx)
	publish_cwd(cx)
	for _, p in cx.session:panes() do
		if p.block == KIND then
			cx.layout:focus(p.pane)
			return
		end
	end
	local pane = cx:new_block(KIND, { current_cwd(cx) }, "beside", { ratio = 0.32 })
	if pane == nil then
		cx:toast("error", "路径收藏", "无法打开路径收藏面板")
	end
end

local last_terminal: number? = nil
local function update_active_cwd(cx)
	local focused = cx.session:focused()
	local p = if focused then cx.session:pane(focused) else nil
	if p and p.kind ~= "plugin" and p.cwd and p.cwd ~= "" then
		last_terminal = p.pane
		tern.kv.set("current_cwd", p.cwd)
	end
end

tern.on("focus", function(_ev, cx)
	update_active_cwd(cx)
end)
tern.on("cwd", function(ev, cx)
	if ev.pane == last_terminal then update_active_cwd(cx) end
end)



tern.command({
	id = "open",
	title = "路径收藏：打开列表",
	icon = "star",
	keys = { "ctrl+alt+shift+f" },
	run = open_list,
})

tern.command({
	id = "save-current",
	title = "路径收藏：收藏当前工作路径",
	icon = "star",
	run = function(cx)
		local cwd = current_cwd(cx)
		local list = tern.kv.get("paths")
		if type(list) ~= "table" then
			list = {}
		end
		for _, path in list do
			if path == cwd then
				cx:toast("info", "路径收藏", "该路径已经收藏")
				return
			end
		end
		table.insert(list, cwd)
		tern.kv.set("paths", list)
		cx:toast("success", "路径收藏", "已收藏 " .. cwd)
	end,
})

local function parent_dir(path: string): string
	local clean = string.gsub(path, "/+$", "")
	local parent = string.match(clean, "^(.*)/[^/]+$")
	return if not parent or parent == "" then "/" else parent
end

local function browse_directory(cx, path: string)
	local ok, names = pcall(tern.fs.list, path)
	if not ok or type(names) ~= "table" then
		cx:toast("error", "路径收藏", "无法读取目录：" .. path)
		return
	end
	local items = { { label = "收藏此目录", detail = path, action = "save", path = path } }
	local parent = parent_dir(path)
	if parent ~= path then
		table.insert(items, { label = "..（上级目录）", detail = parent, action = "enter", path = parent })
	end
	for _, name in names do
		local child = string.gsub(path, "/+$", "") .. "/" .. name
		local is_dir = pcall(tern.fs.list, child)
		if is_dir then table.insert(items, { label = name, detail = child, action = "enter", path = child }) end
	end
	cx:pick({ items = items, placeholder = "选择目录；搜索可筛选", icon = "folder", action = "打开目录或收藏" }):next(function(chosen, _err, next_cx)
		if not chosen then return end
		if chosen.action == "save" then
			local paths = tern.kv.get("paths")
			if type(paths) ~= "table" then paths = {} end
			for _, existing in paths do
				if existing == chosen.path then
					next_cx:toast("info", "路径收藏", "该路径已经收藏")
					return
				end
			end
			table.insert(paths, chosen.path)
			tern.kv.set("paths", paths)
			next_cx:toast("success", "路径收藏", "已收藏 " .. chosen.path)
		else
			browse_directory(next_cx, chosen.path)
		end
	end)
end

tern.route.link(function(link, cx)
	if link.url == "path-favorites://pick" then
		local request = tern.kv.get("pick_directory")
		tern.kv.set("pick_directory", nil)
		local path = if type(request) == "table" and type(request.path) == "string" then request.path else current_cwd(cx)
		browse_directory(cx, path)
		return { handled = true }
	end
	if link.url ~= "path-favorites://open" then
		return nil
	end
	local job = tern.kv.get("open")
	tern.kv.set("open", nil)
	if type(job) ~= "table" or type(job.path) ~= "string" or job.path == "" then
		return { handled = true }
	end
	if not tern.fs.exists(job.path) then
		cx:toast("error", "路径收藏", "目录不存在：" .. job.path)
		return { handled = true }
	end
	local pane = cx.layout:new_tab({ cwd = job.path })
	if pane then
		cx.layout:focus(pane)
	else
		cx:toast("error", "路径收藏", "无法打开新 tab")
	end
	return { handled = true }
end)

tern.chrome.status(function(_pane)
	return { { text = "收藏", icon = "star", tone = "accent", command = "plugin.path-favorites.open" } }
end)
