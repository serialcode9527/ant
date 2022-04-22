local ecs   = ...
local world = ecs.world
local w     = world.w

local mathpkg   = import_package "ant.math"
local mu        = mathpkg.util

local uiconfig  = require "widget.config"

local imgui = require "imgui"
local irq   = ecs.import.interface "ant.render|irenderqueue"

local function show_main_view()
    local imgui_vp = imgui.GetMainViewport()
    local wp, ws = imgui_vp.WorkPos, imgui_vp.WorkSize

    local posx, posy = wp[1], wp[2]+uiconfig.ToolBarHeight
    local sizew, sizeh = ws[1], ws[2]-uiconfig.ToolBarHeight
    imgui.windows.SetNextWindowPos(posx, posy)
    imgui.windows.SetNextWindowSize(sizew, sizeh)
    imgui.windows.SetNextWindowViewport(imgui_vp.ID)
	imgui.windows.PushStyleVar(imgui.enum.StyleVar.WindowRounding, 0.0);
	imgui.windows.PushStyleVar(imgui.enum.StyleVar.WindowBorderSize, 0.0);
    imgui.windows.PushStyleVar(imgui.enum.StyleVar.WindowPadding, 0.0, 0.0);
    if imgui.windows.Begin("MainView", imgui.flags.Window {
        "NoDocking",
        "NoTitleBar",
        "NoCollapse",
        "NoResize",
        "NoMove",
        "NoBringToFrontOnFocus",
        "NoNavFocus",
        "NoBackground",
    }) then
        imgui.dock.Space("MainViewSpace", imgui.flags.DockNode {
            "NoDockingInCentralNode",
            "PassthruCentralNode",
        })

        local vp = world.args.viewport
        --NOTE: the coordinate reture from BuilderGetCentralRect function is relative to full viewport
        local x, y, ww, hh = imgui.dock.BuilderGetCentralRect "MainViewSpace"
        local mp = imgui_vp.MainPos
        x, y = x - mp[1], y - mp[2]

        if x ~= vp.x or y ~= vp.y or ww ~= vp.w or hh ~= vp.h then
            vp.x, vp.y, vp.w, vp.h = x, y, ww, hh
            world:pub{"world_viewport_changed", vp}
            world:pub{"resize", ww, hh}
        end
    end
    imgui.windows.PopStyleVar(3)
    imgui.windows.End()
end

return {
    show = show_main_view,
    in_view = function(x, y)
        return mu.pt2d_in_rect(x, y, irq.view_rect "tonemapping_queue")
    end
}