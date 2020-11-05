local imgui     = require "imgui"
local assetmgr  = import_package "ant.asset"
local uiconfig  = require "widget.config"
local fs        = require "filesystem"
local lfs       = require "filesystem.local"
local allclass = {}

function class(classname, ...)
    local cls = {__cname = classname}
    local supers = {...}
    for _, super in ipairs(supers) do
        local superType = type(super)
        if superType == "table" then
            cls.__supers = cls.__supers or {}
            cls.__supers[#cls.__supers + 1] = super
            if not cls.super then
                cls.super = super
            end
        end
    end
    cls.__index = cls
    local mt
    if not cls.__supers or #cls.__supers == 1 then
        mt = {__index = cls.super}
    else
        mt = {__index = function(_, key)
                            local supers = cls.__supers
                            for i = 1, #supers do
                                local super = supers[i]
                                if super[key] then return super[key] end
                            end
                        end}
    end
    mt.__call = function(cls, ...)
        local instance = setmetatable({}, cls)
        instance.class = cls
        instance:_init(...)
        return instance
    end
    setmetatable(cls, mt)
    return cls
end

local PropertyBase = class("PropertyBase")

function PropertyBase._init(self, label, setter, getter, dim, speed)
    self.label = label
    self.setter = setter
    self.getter = getter
    self.dim = dim or 1
    local sp = speed or 1
    if self.dim == 1 then
        self.uidata = {0, speed = sp}
    elseif self.dim == 2 then
        self.uidata = {0, 0, speed = sp}
    elseif self.dim == 3 then
        self.uidata = {0, 0, 0, speed = sp}
    elseif self.dim == 4 then
        self.uidata = {0, 0, 0, 0, speed = sp}
    end
end

function PropertyBase:update()
    local value = self.getter()
    if type(value) == "table" then
        for i = 1, #value do
            self.uidata[i] = value[i]
        end
    else
        self.uidata[1] = value
    end
end

function PropertyBase:show()
    imgui.widget.Text(self.label)
    imgui.cursor.SameLine(uiconfig.PropertyIndent)
    if self.imgui_func("##" .. self.label, self.uidata) then
        if self.dim == 1 then
            self.setter(self.uidata[1])
        elseif self.dim == 2 then
            self.setter(self.uidata[1], self.uidata[2])
        elseif self.dim == 3 then
            self.setter(self.uidata[1], self.uidata[2], self.uidata[3])
        elseif self.dim == 4 then
            self.setter(self.uidata[1], self.uidata[2], self.uidata[3], self.uidata[4])
        end
    end
end

local IntPro = class("IntPro", PropertyBase)

function IntPro:_init(label, setter, getter, dim, speed)
    PropertyBase._init(self, label, setter, getter, dim, speed)
    self.imgui_func = imgui.widget.DragInt
end

local FloatPro = class("FloatPro", PropertyBase)

function FloatPro:_init(label, setter, getter, dim, speed)
    PropertyBase._init(self, label, setter, getter, dim, speed)
    self.imgui_func = imgui.widget.DragFloat
end

local EditTextPro = class("EditTextPro", PropertyBase)

function EditTextPro:_init(label, setter, getter)
    PropertyBase._init(self, label, setter, getter)
    self.imgui_func = imgui.widget.InputText
    self.uidata = {text = ""}
end

function EditTextPro:show()
    imgui.widget.Text(self.label)
    imgui.cursor.SameLine(uiconfig.PropertyIndent)
    if self.imgui_func("##" .. self.label, self.uidata) then
        self.setter(tostring(self.uidata.text))
    end
end

function EditTextPro:update()
    self.uidata.text = self.getter()
end

local ResourcePathPro = class("ResourcePathPro", EditTextPro)
local utils     = require "common.utils"
function ResourcePathPro:update()
    self.uidata.text = self.getter()
    if not self.uidata2 then
        self.uidata2 = {text = ""}
    end
    local path = self.uidata.text
    if string.sub(path, -8) == ".texture" then
        self.tdata = utils.readtable(path)
        local t = assetmgr.resource(path)
        local s = t.sampler
        self.texture_handle = t._data.handle
        self.uidata2.text = self.tdata.path
    end
end

local rhwi      = import_package 'ant.render'.hwi
local datalist  = require "datalist"
local stringify = import_package "ant.serialize".stringify
local filedialog = require 'filedialog'
local filter_type = {"POINT", "LINEAR", "ANISOTROPIC"}
local address_type = {"WRAP", "MIRROR", "CLAMP", "BORDER"}

function ResourcePathPro:show()
    imgui.widget.Text(self.label)
    imgui.cursor.SameLine(uiconfig.PropertyIndent)
    if self.imgui_func("##" .. self.label, self.uidata) then
        self.setter(tostring(self.uidata.text))
    end
    
    local function on_dragdrop_texture()
        if imgui.widget.BeginDragDropTarget() then
            local payload = imgui.widget.AcceptDragDropPayload("DragFile")
            if payload then
                local rp = lfs.relative(lfs.path(payload), fs.path "":localpath())
                local pkg_path = "/pkg/ant.tools.prefab_editor/" .. tostring(rp)
                self.setter(pkg_path)
                if string.sub(pkg_path, -8) == ".texture" then
                    self.tdata = utils.readtable(pkg_path)
                    local t = assetmgr.resource(pkg_path)
                    local s = t.sampler
                    self.texture_handle = t._data.handle
                    self.uidata.text = pkg_path
                elseif string.sub(pkg_path, -4) == ".png"
                    or string.sub(pkg_path, -4) == ".dds" then
                    local t = assetmgr.resource(pkg_path, { compile = true })
                    self.texture_handle = t.handle
                    tp.tdata.path = pkg_path
                end
                self.uidata2.text = tp.tdata.path
            end
            imgui.widget.EndDragDropTarget()
        end
    end

    on_dragdrop_texture()

    -- texture detail
    if self.texture_handle then
        imgui.cursor.Indent()
        imgui.cursor.Columns(2, self.label, false)
        imgui.cursor.SetColumnOffset(2, uiconfig.PropertyIndent)
        imgui.widget.Image(self.texture_handle, uiconfig.PropertyImageSize, uiconfig.PropertyImageSize)
        imgui.cursor.SameLine(uiconfig.PropertyImageSize * 2)
        imgui.cursor.NextColumn()
        imgui.widget.Text("image")
        imgui.cursor.SameLine()
        imgui.cursor.PushItemWidth(-1)
        if imgui.widget.InputText("##" .. self.tdata.path .. self.label, self.uidata2) then
        end
        imgui.cursor.PopItemWidth()
        on_dragdrop_texture()

        local sampler = self.tdata.sampler
        local function show_filter(ft)
            imgui.widget.Text(ft)
            imgui.cursor.SameLine()
            imgui.cursor.SetNextItemWidth(uiconfig.ComboWidth)
            imgui.util.PushID(ft .. self.label)
            if imgui.widget.BeginCombo("##"..ft, {sampler[ft], flags = imgui.flags.Combo { "NoArrowButton" }}) then
                for i, type in ipairs(filter_type) do
                    if imgui.widget.Selectable(type, sampler[ft] == type) then
                        sampler[ft] = type
                    end
                end
                imgui.widget.EndCombo()
            end
            imgui.util.PopID()
        end
        show_filter("MAG")
        imgui.cursor.SameLine()
        show_filter("MIN")
        imgui.cursor.SameLine()
        show_filter("MIP")

        local function show_uv(uv)
            imgui.widget.Text(uv)
            imgui.cursor.SameLine()
            imgui.cursor.SetNextItemWidth(uiconfig.ComboWidth)
            imgui.util.PushID(uv .. self.label)
            if imgui.widget.BeginCombo("##"..uv, {sampler[uv], flags = imgui.flags.Combo { "NoArrowButton" }}) then
                for i, type in ipairs(address_type) do
                    if imgui.widget.Selectable(type, sampler[uv] == type) then
                        sampler[uv] = type
                    end
                end
                imgui.widget.EndCombo()
            end
            imgui.util.PopID()
        end
        show_uv("U")
        imgui.cursor.SameLine()
        show_uv("V")

        imgui.cursor.SameLine()
        imgui.util.PushID("Save" .. self.label)
        if imgui.widget.Button("Save") then
            utils.write_file(self.texture, stringify(self.tdata))
            assetmgr.unload(self.texture)
        end
        imgui.util.PopID()
        imgui.cursor.SameLine()
        imgui.util.PushID("Save As" .. self.label)
        if imgui.widget.Button("Save As") then
            local dialog_info = {
                Owner = rhwi.native_window(),
                Title = "Save As..",
                FileTypes = {"Texture", "*.texture" }
            }
            local ok, path = filedialog.save(dialog_info)
            if ok then
                path = string.gsub(path, "\\", "/") .. ".texture"
                local pos = string.find(path, "%.texture")
                if #path > pos + 7 then
                    path = string.sub(path, 1, pos + 7)
                end
                utils.write_file(path, stringify(self.tdata))
            end
        end
        imgui.util.PopID()
        imgui.cursor.Unindent()
        imgui.cursor.Columns(1)
    end
end

local ComboPro = class("ComboPro")

function ComboPro._init(self, label, setter, getter, options)
    self.label = label
    self.setter = setter
    self.getter = getter
    self.options = options
    self.current_option = options[1]
end

function ComboPro:update()
    self.current_option = self.getter()
end

function ComboPro:show()
    imgui.widget.Text(self.label)
    imgui.cursor.SameLine(uiconfig.PropertyIndent)
    imgui.util.PushID(tostring(self))
    if imgui.widget.BeginCombo("##"..self.label, {self.current_option, flags = imgui.flags.Combo {}}) then
        for _, option in ipairs(self.options) do
            if imgui.widget.Selectable(option, self.current_option == option) then
                self.current_option = option
                self.setter(option)
            end
        end
        imgui.widget.EndCombo()
    end
    imgui.util.PopID()
end

allclass.ComboPro           = ComboPro
allclass.IntPro             = IntPro
allclass.FloatPro           = FloatPro
allclass.EditTextPro        = EditTextPro
allclass.ResourcePathPro    = ResourcePathPro

return allclass