package.path = "/engine/?.lua"
require "bootstrap"

dofile "/engine/ltask.lua" {
    bootstrap = {
        ["test|main"] = {
            unique = false,
        }
    }
}
