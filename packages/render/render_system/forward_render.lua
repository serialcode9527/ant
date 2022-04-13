local ecs = ...
local world = ecs.world
local w = world.w

local default	= import_package "ant.general".default
local icamera	= ecs.import.interface "ant.camera|icamera"
local irender	= ecs.import.interface "ant.render|irender"

local mathpkg	= import_package "ant.math"
local mu		= mathpkg.util

local fr_sys = ecs.system "forward_render_system"

function fr_sys:init()
	local ratio = world.args.framebuffer.scene_ratio
	local vr = mu.calc_viewport(world.args.viewport, ratio)
	if ratio then
		vr.ratio = ratio
	end
	local camera = icamera.create{
		name = "default_camera",
		frustum = default.frustum(vr.w/vr.h),
		exposure = {
			type 			= "manual",
			aperture 		= 16.0,
			shutter_speed 	= 0.008,
			ISO 			= 100,
		}
	}

	if irender.use_pre_depth() then
		irender.create_pre_depth_queue(vr, camera)
	end
	irender.create_main_queue(vr, camera)
end

local function update_pre_depth_queue()
	for de in w:select "pre_depth_queue render_target:in camera_ref:out" do
		for me in w:select "main_queue render_target:in camera_ref:in" do
			de.camera_ref = me.camera_ref
			local vr = me.render_target.view_rect
			local dvr = de.render_target.view_rect
			dvr.x, dvr.y, dvr.w, dvr.h = vr.x, vr.y, vr.w, vr.h
		end
	end
end

function fr_sys:data_changed()
	--TODO: need sub a event
	update_pre_depth_queue()
end