local ecs = ...
local world = ecs.world

-- runtime
ecs.import "render.camera.camera_component"
ecs.import "render.entity_rendering_system"
ecs.import "render.view_system"


-- lighting
ecs.import "render.light.light"

-- serialize
ecs.import "serialize.serialize_system"

-- scene
ecs.import "scene.cull_system"
ecs.import "scene.filter.filter_system"
ecs.import "scene.filter.lighting_filter"

-- animation
ecs.import "animation.skinning.skinning_system"
ecs.import "animation.animation"
ecs.import "physic.rigid_body"

-- editor
ecs.import "editor.ecs.camera_controller"
ecs.import "editor.ecs.pickup_system"
ecs.import "editor.ecs.render.widget_system"

-- editor elements
ecs.import "editor.ecs.general_editor_entities"
ecs.import "editor.ecs.debug.debug_drawing"
ecs.import "tools.modeleditor.accessory_system"

local ms = require "math.stack"
local util = require "tools.modeleditor.util"
local physicobjs = require "tools.modeleditor.physicobj"
local assetmgr = require "asset"
local path = require "filesystem.path"
local vfsutil = require "vfs.util"
local fu = require "filesystem.util"

ecs.tag "sampleobj"

local model_ed_sys = ecs.system "model_editor_system"
model_ed_sys.singleton "debug_object"
model_ed_sys.singleton "timer"
model_ed_sys.depend "camera_init"

-- luacheck: globals main_dialog
-- luacheck: globals iup
local function get_ani_cursor(slider)
	assert(tonumber(slider.MIN) == 0)
	assert(tonumber(slider.MAX) == 1)
	return tonumber(slider.VALUE)
end

local function update_animation_ratio(eid, cursor_pos)
	local e = world[eid]	
	local anicomp = e.animation
	if anicomp then
		anicomp.ratio = cursor_pos
	end
end

local sample_eid

local function smaple_entity()
	if sample_eid then
		return world[sample_eid]
	end
end

local function dlg_item(name)	
	return iup.GetDialogChild(main_dialog(), name)
end

local function enable_sample_visible()
	if sample_eid then
		local sample = world[sample_eid]
		if sample then
			local sample_shower = dlg_item("SHOWSAMPLE")			
			sample.can_render = sample_shower.VALUE ~= "OFF"
		end
	end
end

local function enable_sample_boundingbox()
	local sample = smaple_entity()
	if sample then
		local bounding = dlg_item("SHOWSAMPLEBOUNDING")
		sample.widget.can_render = bounding.VALUE ~= "OFF"
	end
end

local function enable_bones_visible()
	if sample_eid then
		local sample =world[sample_eid]
		if sample then
			local bone_shower = dlg_item("SHOWBONES")
			if bone_shower.VALUE ~= "OFF" then
				assert(sample.debug_skeleton == nil)
				world:add_component(sample_eid, "debug_skeleton")
			else
				if sample.debug_skeleton then
					world:remove_component(sample_eid, "debug_skeleton")
				end
			end
		end
	end
end

local function check_create_sample_entity(sc, ac, mc)
	local anipath = ac.VALUE
	local skepath = sc.VALUE
	local skinning_meshpath = mc.VALUE

	local function check_path_valid(pp)
		if pp == nil or pp == "" then
			return false
		end

		if not assetmgr.find_valid_asset_path(pp) then
			iup.Message("Error", string.format("invalid path : %s", pp))
			return false
		end

		return true
	end

	-- only skinning meshpath is needed!
	if check_path_valid(skinning_meshpath) then			
		if sample_eid then
			world:remove_entity(sample_eid)
		end

		sample_eid = util.create_sample_entity(world, skepath, anipath, skinning_meshpath)
		enable_sample_visible()
	end
end

local function update_static_duration_value()
	if sample_eid then
		local e = world[sample_eid]
		local ani = e.animation
		if ani then 
			local anihandle = ani.assetinfo.handle
			
			local duration = anihandle:duration()
			local dlg = main_dialog()
			local static_duration_value = iup.GetDialogChild(dlg, "STATIC_DURATION")
			static_duration_value.TITLE = string.format("Time(%.2f ms)", duration * 1000)
		end
	end
end

local function update_duration_text(cursorpos)		
	local dlg = main_dialog()
	local duration_value = iup.GetDialogChild(dlg, "DURATION")
	if duration_value == nil then
		return 
	end

	local sample = smaple_entity()
	if sample == nil then
		return 
	end
	local anicomp = sample.animation
	if anicomp then
		local ani_assetinfo = anicomp.assetinfo
		if ani_assetinfo then
			local ani_handle = ani_assetinfo.handle
			local duration_pos = ani_handle:duration() * cursorpos
			duration_value.VALUE = string.format("%2f", duration_pos)
		end
	end
end

local function slider_value_chaged(slider)
	local cursorpos = get_ani_cursor(slider)
	update_duration_text(cursorpos)
	update_animation_ratio(sample_eid, cursorpos)
end

local function init_paths_ctrl()
	local dlg = main_dialog()
	local skepath_inputer = iup.GetDialogChild(dlg, "SKE_PATH")
	local anipath_inputer = iup.GetDialogChild(dlg, "ANI_PATH")
	local meshpath_inputer = iup.GetDialogChild(dlg, "SM_PATH")

	function skepath_inputer:killfocus_cb()		
		check_create_sample_entity(self, anipath_inputer, meshpath_inputer)
		return 0
	end
	
	function anipath_inputer:killfocus_cb()		
		check_create_sample_entity(skepath_inputer, self, meshpath_inputer)
		return 0
	end

	function meshpath_inputer:killfocus_cb()
		check_create_sample_entity(skepath_inputer, anipath_inputer, self)
		return 0
	end

	local skepath_finder = iup.GetDialogChild(dlg, "SKE_FINDER")
	local function get_file()
		local filename = iup.GetFile("assets/meshes/*.ozz")		
		local vfsfilename = vfsutil.filter_abs_path(filename)		
		if path.is_absolute_path(vfsfilename) then
			iup.Message("Resource Error", string.format("resource: %s should import to project 'assets' folder"))
			return 
		end
		return vfsfilename
	end
	function skepath_finder:action()
		local filename = get_file()
		if filename then
			skepath_inputer.VALUE = filename
			check_create_sample_entity(skepath_inputer, anipath_inputer, meshpath_inputer)
		end
	end

	local anipath_finder = iup.GetDialogChild(dlg, "ANI_FINDER")
	function anipath_finder:action()
		local filename = get_file()
		if filename then
			anipath_inputer.VALUE = filename
			check_create_sample_entity(skepath_inputer, anipath_inputer, meshpath_inputer)
		end
	end

	local smpath_finder = iup.GetDialogChild(dlg, "SM_FINDER")
	function smpath_finder:action()
		local filename = get_file()
		if filename then
			meshpath_inputer.VALUE = filename
			check_create_sample_entity(skepath_inputer, anipath_inputer, meshpath_inputer)
		end
	end

	skepath_inputer.VALUE = "meshes/skeleton/skeleton.ozz"
	anipath_inputer.VALUE = "meshes/animation/animation_base.ozz"
	meshpath_inputer.VALUE = "meshes/mesh.ozz"
	check_create_sample_entity(skepath_inputer, anipath_inputer, meshpath_inputer)
end

local function init_playitme_ctrl()
	local dlg = main_dialog()

	local slider = iup.GetDialogChild(dlg, "ANITIME_SLIDER")

	update_static_duration_value()

	local duration_value = iup.GetDialogChild(dlg, "DURATION")
	function duration_value:killfocus_cb()
		local duration = tonumber(self.VALUE)

		if sample_eid then
			local e = world[sample_eid]
			local anicomp = e.animation
			if anicomp then
				local anihandle = anicomp.assetinfo.handle
				local aniduration = anihandle:duration()
				local ratio = math.min(math.max(0, duration / aniduration), 1)
				anicomp.ratio = ratio
			end
		end
	end
	
	function slider:valuechanged_cb()
		slider_value_chaged(self)
	end

	slider_value_chaged(slider)

	local autoplay = iup.GetDialogChild(dlg, "AUTO_PLAY")
	function autoplay:action()
		local active = self.VALUE == "OFF" and "ON" or "OFF"
		duration_value.ACTIVE = active
		slider.ACTIVE = active
	end
end

local function init_check_shower()
	local checkers = {
		SHOWBONES=enable_bones_visible,
		SHOWSAMPLE=enable_sample_visible,
		SHOWSAMPLEBOUNDING=enable_sample_boundingbox,
	}

	for k, v in pairs(checkers) do
		local checker = dlg_item(k)
		checker.action = function () v() end
	end
end

local function init_res_ctrl()
	local dlg = main_dialog()
	local assetview = assert(iup.GetDialogChild(dlg, "ASSETVIEW").owner)

	assetview:init("project")
end

local function init_control()
	init_paths_ctrl()
	init_playitme_ctrl()
	init_check_shower()
	init_res_ctrl()
	iup.Map(main_dialog())
end

local function init_lighting()
	local lu = require "render.light.util"
	local leid = lu.create_directional_light_entity(world)
	local lentity = world[leid]
	local lightcomp = lentity.light
	lightcomp.color = {1,1,1,1}
	lightcomp.intensity = 2.0
	ms(lentity.rotation, {123.4, -34.22,-28.2}, "=")
end

local function focus_sample()
	if sample_eid then
		local camerautil = require "render.camera.util"
		camerautil.focus_selected_obj(world, sample_eid)		
	end
end

-- luacheck: ignore self
function model_ed_sys:init()	
	init_control()
	init_lighting()

	physicobjs.create_plane_entity(world)

	focus_sample()
end

local function auto_update_ani(deltatimeInSecond)
	local sample = smaple_entity()
	if sample == nil then
		return
	end

	local ani = sample.animation
	if ani == nil then
		return
	end

	local dlg = main_dialog()
	local autoplay = iup.GetDialogChild(dlg, "AUTO_PLAY")
	if autoplay.VALUE ~= "OFF" then
		local durationctrl = iup.GetDialogChild(dlg, "DURATION")
		local duration = tonumber(durationctrl.VALUE)

		local anihandle = assert(ani.assetinfo.handle)
		local aniduration = anihandle:duration()
		

		local function calc_new_duration(duration, aniduration)
			local function is_number_equal(lhs, rhs)
				local delta = lhs - rhs
				local tolerance = 10e-6
				return -tolerance <= delta and delta <= tolerance
			end
			if is_number_equal(duration, aniduration) then
				return 0
			end

			local newduration = duration + deltatimeInSecond
			if newduration > aniduration then
				return aniduration
			end
			return newduration
		end

		local newduration = calc_new_duration(duration, aniduration)
	
		local ratio = math.min(math.max(0, newduration / aniduration), 1)
		ani.ratio = ratio
		durationctrl.VALUE = tostring(newduration)
	end
end

function model_ed_sys:update()
	local timer = self.timer
	auto_update_ani(timer.delta * 0.001)
end