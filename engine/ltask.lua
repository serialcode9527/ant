local boot = require "ltask.bootstrap"
local ltask = require "ltask"
local vfs = require "vfs"

local SERVICE_ROOT <const> = 1
local MESSSAGE_SYSTEM <const> = 0

local CoreConfig <const> = 0
local RootConfig <const> = 1
local BootConfig <const> = 1

local ConfigCatalog <const> = {
	worker = CoreConfig,
	queue = CoreConfig,
	queue_sending = CoreConfig,
	max_service = CoreConfig,
	crashlog = CoreConfig,
	debuglog = CoreConfig,
	worker_bind = RootConfig,
	preload = RootConfig,
	lua_path = RootConfig,
	lua_cpath = RootConfig,
	service_path = RootConfig,
	exclusive = RootConfig,
	preinit = RootConfig,
	logger = RootConfig,
	bootstrap = RootConfig,
	mainthread = BootConfig
}

local coreConfig
local rootConfig
local bootConfig

local function new_service(label, id)
	local sid = assert(boot.new_service(label, rootConfig.init_service, id))
	assert(sid == id)
	return sid
end

local function root_thread()
	assert(boot.new_service("root", rootConfig.init_service, SERVICE_ROOT))
	boot.init_root(SERVICE_ROOT)
	-- send init message to root service
	local init_msg, sz = ltask.pack("init", {
		lua_path = rootConfig.lua_path,
		lua_cpath = rootConfig.lua_cpath,
		service_path = "/engine/service/root.lua",
		name = "root",
		args = {rootConfig}
	})
	-- self bootstrap
	boot.post_message {
		from = SERVICE_ROOT,
		to = SERVICE_ROOT,
		session = 0,	-- 0 for root init
		type = MESSSAGE_SYSTEM,
		message = init_msg,
		size = sz,
	}
end

local function exclusive_thread(label, id)
	local sid = new_service(label, id)
	boot.new_thread(sid)
end

local function io_thread(label, id)
	local sid = assert(boot.new_service_preinit(label, id, vfs.iothread))
	boot.new_thread(sid)
end

local function toclose(f)
	return setmetatable({}, {__close=f})
end

local function readall(path)
	local fastio = require "fastio"
	local mem = vfs.read(path)
	return fastio.tostring(mem)
end

local function init(c)
	coreConfig = {}
	rootConfig = {}
	bootConfig = {}
	for k, v in pairs(c) do
		if ConfigCatalog[k] == CoreConfig then
			coreConfig[k] = v
		elseif ConfigCatalog[k] == RootConfig then
			rootConfig[k] = v
		elseif ConfigCatalog[k] == BootConfig then
			bootConfig[k] = v
		else
			assert(false, k)
		end
	end

	local directory = require "directory"
	local log_path = directory.app_path()
	if not coreConfig.debuglog then
		coreConfig.debuglog = (log_path / "debug.log"):string()
	end
	if not coreConfig.crashlog then
		coreConfig.crashlog = (log_path / "crash.log"):string()
	end
	if not coreConfig.worker then
		coreConfig.worker = 4
	end

	if not rootConfig.logger then
		rootConfig.logger = { "logger" }
	end
	if rootConfig.worker_bind then
		local map = {}
		for i = #rootConfig.worker_bind, 1, -1 do
			local name = rootConfig.worker_bind[i]
			map[name] = coreConfig.worker
			coreConfig.worker = coreConfig.worker + 1
		end
		rootConfig.worker_bind = map
	end
	if bootConfig.mainthread == "worker" then
		bootConfig.mainthread = coreConfig.worker - 1
	else
		bootConfig.mainthread = nil
	end

	rootConfig.lua_path = nil
	rootConfig.lua_cpath = ""
	rootConfig.service_path = "${package}/service/?.lua;/engine/service/?.lua"

	local servicelua = readall "/engine/service/service.lua"

	local initstr = ""

	local dbg = debug.getregistry()["lua-debug"]
	if dbg then
		dbg:event("setThreadName", "Thread: Bootstrap")
		initstr = [[
local ltask = require "ltask"
local name = ("Service:%d <%s>"):format(ltask.self(), ltask.label() or "unk")
assert(loadfile '/engine/debugger.lua')()
	: event("setThreadName", name)
	: event "wait"
]]
	end

rootConfig.init_service = initstr .. servicelua

	rootConfig.preload = [[
package.path = "/engine/?.lua"
local ltask = require "ltask"
local vfs = require "vfs"
local thread = require "bee.thread"
local ServiceIO = ltask.uniqueservice "io"
local function call(...)
	return ltask.call(ServiceIO, ...)
end
local function send(...)
	return ltask.send(ServiceIO, ...)
end
vfs.call = call
vfs.send = send
function vfs.read(path)
	return call("READ", path)
end
function vfs.list(path)
	return call("LIST", path)
end
function vfs.type(path)
	return call("TYPE", path)
end
function vfs.resource_setting(setting)
	return send("RESOURCE_SETTING", setting)
end
function vfs.version()
	return call("VERSION")
end
local rawsearchpath = package.searchpath
package.searchpath = function(name, path, sep, dirsep)
	local package, file = name:match "^([^|]*)|(.*)$"
	if package and file then
		path = path:gsub("%$%{([^}]*)%}", {
			package = "/pkg/"..package,
		})
		name = file
	else
		path = path:gsub("%$%{([^}]*)%}[^;]*;", "")
	end
	return rawsearchpath(name, path, sep, dirsep)
end

local rawloadfile = loadfile
function loadfile(filename, mode, env)
	if env == nil then
		local package, file = filename:match "^/pkg/([^/]+)/(.+)$"
		if package and file then
			local pm = require "packagemanager"
			return rawloadfile(filename, mode or "bt", pm.loadenv(package))
		end
		return rawloadfile(filename, mode)
	end
	return rawloadfile(filename, mode, env)
end
]]
end

local function io_switch()
	local servicelua = "/engine/service/service.lua"
	local mem = vfs.read(servicelua)
	vfs.send("SWITCH", servicelua, mem)
end

return function (c)
	init(c)
	boot.init(coreConfig)
	local _ <close> = toclose(boot.deinit)
	boot.init_timer()
	for i, t in ipairs(rootConfig.exclusive) do
		local label = type(t) == "table" and t[1] or t
		local id = i + 1
		exclusive_thread(label, id)
	end
	rootConfig.preinit = { "io" }
	root_thread()
	io_switch()
	io_thread("io", 2 + #rootConfig.exclusive)
	boot.run(bootConfig.mainthread)
end
