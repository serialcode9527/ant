


-- luacheck: globals log bullet
local editor 		= import_package "ant.editor"
local ecs = import_package "ant.ecs"
local task 			= editor.task

--local elog = require "editor.log"
--local db = require "debugger"

-- --windows dir
-- asset.insert_searchdir(1, "D:/Engine/ant/assets")
-- --mac dir
-- asset.insert_searchdir(2, "/Users/ejoy/Desktop/Engine/ant/assets")


local world =  ecs.new_world {
        packages = {"ant.testempty"},
        systems = {"system1"},
        update_order = {},
        args = { 
        },
    }
world.update = function()

end
-- print(world)
task.safe_loop(world.update)
-- print(11)
local mainwin = require "test_connect_win"
-- local mainwin = require "test_tree_window"
mainwin:run {
    fbw=1024, fbh=768,
}



-- mainwin:run {
--     fbw=1024, fbh=768,
-- }

