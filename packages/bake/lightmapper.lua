local ecs = ...
local world = ecs.world
require "bake_mathadapter"

local renderpkg = import_package "ant.render"
local viewidmgr = renderpkg.viewidmgr
local declmgr   = renderpkg.declmgr

local math3d    = require "math3d"
local bgfx      = require "bgfx"
local bake      = require "bake"

local ipf       = world:interface "ant.scene|iprimitive_filter"
local irender   = world:interface "ant.render|irender"
local imaterial = world:interface "ant.asset|imaterial"
local icp       = world:interface "ant.render|icull_primitive"

local lm_trans = ecs.transform "lightmap_transform"
function lm_trans.process_entity(e)
    e._lightmap = {}
end

local lightmap_sys = ecs.system "lightmap_system"

local context_setting = {
    size = 64,
    z_near = 0.1, z_far = 1,
    rgb = {1.0, 1.0, 1.0},
    interp_pass_count = 2, interp_threshold = 0.001,
    cam2surf_dis_modifier = 0.0,
}

local weight_downsample_material
local downsample_material

local shading_info

local bake_ctx

local viewids<const> = {
    viewidmgr.generate "weight_ds",
    viewidmgr.generate "ds",
}

local bake_viewid<const> = viewids[1]

function lightmap_sys:init()
    weight_downsample_material = imaterial.load "/pkg/ant.bake/materials/weight_downsample.material"
    downsample_material = imaterial.load "/pkg/ant.bake/materials/downsample.material"

    local wds_fx = weight_downsample_material.fx
    local ds_fx = downsample_material.fx

    local function find_uniform_handle(uniforms, name)
        for _, u in ipairs(uniforms) do
            if u.name == name then
                return u.handle
            end
        end
    end

    local function touint16(h) return 0xffff & h end

    shading_info = {
        viewids = viewids,
        weight_downsample = {
            prog        = touint16(wds_fx.prog),
            hemispheres = touint16(find_uniform_handle(wds_fx.uniforms,  "hemispheres")),
            weights     = touint16(find_uniform_handle(wds_fx.uniforms,  "weights")),
        },
        downsample = {
            prog        = touint16(ds_fx.prog),
            hemispheres = touint16(find_uniform_handle(ds_fx.uniforms, "hemispheres"))
        }
    }

    world:create_entity {
        policy = {
            "ant.bake|lightmap_baker",
            "ant.general|name",
        },
        data = {
            primitive_filter = {
                filter_type = "lightmap",
            },
            lightmap_baker = {},
        }
    }

    world:create_entity {
        policy = {
            "ant.bake|scene_watcher",
            "ant.general|name",
        },
        data = {
            primitive_filter = {
                filter_type = "visible",
            },
            scene_watcher = {},
        }
    }
end

local function load_geometry_info(item)
    local e = world[item.eid]
    local m = e.mesh
    local function get_type(t)
        local types<const> = {
            u = "B", i = "I", f = "f",
        }

        local tt = types[t]
        assert(tt, "invalid type")
        return types[tt]
    end
    local function get_attrib_item(name)
        for _, vb in ipairs(m.vb) do
            local offset = 0
            local declname = vb.declname
            local stride = declmgr.layout_stride(declname)
            for d in declname:gmatch "%w+" do
                if d:sub(1, 3):match(name) then
                    return {
                        offset = offset,
                        stride = stride,
                        memory = bgfx.memory_buffer(table.unpack(vb.memory)),
                        type   = get_type(d:sub(6, 6)),
                    }
                end
                offset = offset + declmgr.elem_size(d)
            end
        end

        error(("not found attrib name:%s"):format(name))
    end

    local ib = m.ib
    local index
    if ib then
        local function is_uint32(f)
            if f then
                return f:match "d"
            end
        end
        local t<const> = is_uint32(ib.flag) and "I" or "H"
        index = {
            offset = 0,
            stride = t == "I" and 4 or 2,
            memory = bgfx.memory_buffer(table.unpack(ib.memory)),
            type = t,
        }
    end

    return {
        worldmat= math3d.value_ptr(item.worldmat),
        num     = math.tointeger(m.vb.num),
        pos     = get_attrib_item "p",
        normal  = get_attrib_item "n",
        uv      = get_attrib_item "t21",
        index   = index,
    }
end

local function draw_scene(pf)
    for _, result in ipf.iter_filter(pf) do
        for _, item in ipf.iter_target(result) do
            irender.draw(bake_viewid, item)
        end
    end
end

local function bake_entity(eid, scene_pf)
    local e = world[eid]
    if e == nil then
        return log.warn(("invalid entity:%d"):format(eid))
    end

    if e._lightmap == nil then
        return log.warn(("entity %s not set any lightmap info will not be baked"):format(e.name or ""))
    end

    log.info(("baking entity:[%d-%s]"):format(eid, e.name or ""))
    local lm = e.lightmap
    log.info(("set baking entity lightmap:[%d-%s], w:%d, h:%d, channels:%d"):format(eid, e.name or "", lm.width, lm.height, lm.channels))
    e._lightmap.data = bake_ctx:set_target_lightmap(e.lightmap)

    local g = load_geometry_info(e._rendercache)
    bake_ctx:set_geometry(g)
    log.info(("begin bake entity:[%d-%s]"):format(eid, e.name or ""))
    while true do
        local haspatch, vp, view, proj = bake_ctx:begin_patch()
        if not haspatch then
            break
        end

        vp = math3d.tovalue(vp)
        bgfx.set_view_rect(bake_viewid, vp[1], vp[2], vp[3], vp[4])
        bgfx.set_view_transform(bake_viewid, view, proj)
        icp.cull(scene_pf, math3d.mul(proj, view))
        draw_scene(scene_pf)
        bake_ctx:end_patch()
        log.info(("%d-%s process:%2f"):format(eid, e.name or "", bake_ctx:process()))
    end

    log.info(("bake finish for entity: %d-%s"):format(eid, e.name or ""))

    e._lightmap.data:postprocess()
    e._lightmap.data:save "d:/work/ant/tools/lightmap_baker/lm.tga"
    log.info(("postprocess entity finish: %d-%s"):format(eid, e.name or ""))
end

local function bake_all()
    local lm_e = world:singleton_entity "lightmap_baker"
    local se = world:singleton_entity "scene_watcher"
    for _, result in ipf.iter_filter(lm_e.primitive_filter) do
        for _, item in ipf.iter_target(result) do
            bake_entity(item.eid, se.primitive_filter)
        end
    end
end

local bake_mb = world:sub{"bake"}
local lm_mb = world:sub{"component_register", "lightmap_baker"}

local function init_bake_context(s)
    bake_ctx = bake.create_lightmap_context(s)
    bake_ctx:set_shadering_info(shading_info)
end

function lightmap_sys:end_frame()
    for msg in lm_mb:each() do
        init_bake_context(context_setting)
    end
    for msg in bake_mb:each() do
        assert(bake_ctx, "invalid bake context, need check")
        local eid = msg[2]
        if eid then
            local se = world:singleton_entity "scene_watcher"
            bake_entity(eid, se.primitive_filter)
        else
            log.info("bake entity scene with lightmap setting")
            bake_all()
        end
    end
end

