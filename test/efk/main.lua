package.path = "engine/?.lua"
require "bootstrap"
import_package "ant.window".start {
    import = {
        "@ant.test.efk",
    },
    pipeline = {
        "init",
        "update",
        "exit",
    },
    system = {
        "ant.test.efk|init_system",
    },
    policy = {
        "ant.scene|scene_object",
        "ant.render|render",
        "ant.render|render_queue",
    }
}
