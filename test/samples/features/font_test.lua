local ecs = ...
local world = ecs.world
local fonttest_sys = ecs.system "font_test_system"

function fonttest_sys.init()
    --world:instance "/pkg/ant.test.features/assets/entities/fonttest.prefab"
end