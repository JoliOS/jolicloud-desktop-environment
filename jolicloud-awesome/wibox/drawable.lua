---------------------------------------------------------------------------
-- @author Uli Schlachter
-- @copyright 2012 Uli Schlachter
-- @release v3.4-799-g4711354
---------------------------------------------------------------------------

local drawable = {}
local capi = {
    awesome = awesome,
    root = root
}
local beautiful = require("beautiful")
local cairo = require("lgi").cairo
local color = require("gears.color")
local object = require("gears.object")
local sort = require("gears.sort")
local surface = require("gears.surface")

local drawables = setmetatable({}, { __mode = 'k' })

local util = require("awful.util")

local function do_redraw(self)
    local cr = cairo.Context(surface(self.drawable.surface))
    local geom = self.drawable:geometry();
    local x, y, width, height = geom.x, geom.y, geom.width, geom.height

    -- Draw the background
    cr:save()
    -- This is pseudo-transparency: We draw the wallpaper in the background
    local wallpaper = surface(capi.root.wallpaper())
    if wallpaper then
        cr.operator = cairo.Operator.SOURCE
        cr:set_source_surface(wallpaper, -x, -y)
        cr:paint()
    end

    cr.operator = cairo.Operator.OVER
    cr:set_source(self.background_color)
    cr:paint()
    if self._redraw_hook then self._redraw_hook(cr, geom) end
    cr:restore()

    -- Draw the widget
    self._widget_geometries = {}
    if self.widget then
        cr:set_source(self.foreground_color)
        self.widget:draw(self.widget_arg, cr, width, height)
        self:widget_at(self.widget, 0, 0, width, height)
    end

    self.drawable:refresh()
end

--- Register a widget's position.
-- This is internal, don't call it yourself! Only wibox.layout.base.draw_widget
-- is allowed to call this.
function drawable:widget_at(widget, x, y, width, height)
    local t = {
        widget = widget,
        x = x, y = y,
        width = width, height = height
    }
    table.insert(self._widget_geometries, t)
end

--- Find a widget by a point.
-- The drawable must have drawn itself at least once for this to work.
-- @param x X coordinate of the point
-- @param y Y coordinate of the point
-- @return A sorted table with all widgets that contain the given point. The
--         widgets are sorted by relevance.
function drawable:find_widgets(x, y)
    local matches = {}
    -- Find all widgets that contain the point
    for k, v in pairs(self._widget_geometries) do
        local match = true
        if v.x > x or v.x + v.width <= x then match = false end
        if v.y > y or v.y + v.height <= y then match = false end
        if match then
            table.insert(matches, v)
        end
    end

    -- Sort the matches by area, the assumption here is that widgets don't
    -- overlap and so smaller widgets are "more specific".
    local function cmp(a, b)
        local area_a = a.width * a.height
        local area_b = b.width * b.height
        return area_a < area_b
    end
    sort(matches, cmp)

    return matches
end


--- Set the widget that the drawable displays
function drawable:set_widget(widget)
    if self.widget then
        -- Disconnect from the old widget so that we aren't updated due to it
        self.widget:disconnect_signal("widget::updated", self.draw)
    end

    self.widget = widget
    if widget then
        widget:connect_signal("widget::updated", self.draw)
    end

    -- Make sure the widget gets drawn
    self.draw()
end

--- Set the background of the drawable
-- @param drawable The drawable to use
-- @param c The background to use. This must either be a cairo pattern object,
--          nil or a string that gears.color() understands.
function drawable:set_bg(c)
    local c = c or "#000000"
    if type(c) == "string" or type(c) == "table" then
        c = color(c)
    end
    self.background_color = c
    self.draw()
end

--- Set the foreground of the drawable
-- @param drawable The drawable to use
-- @param c The foreground to use. This must either be a cairo pattern object,
--          nil or a string that gears.color() understands.
function drawable:set_fg(c)
    local c = c or "#FFFFFF"
    if type(c) == "string" or type(c) == "table" then
        c = color(c)
    end
    self.foreground_color = c
    self.draw()
end

local function emit_difference(name, list, skip)
    local function in_table(table, val)
        for k, v in pairs(table) do
            if v == val then
                return true
            end
        end
        return false
    end

    for k, v in pairs(list) do
        if not in_table(skip, v) then
            v:emit_signal(name)
        end
    end
end

local function handle_leave(_drawable)
    emit_difference("mouse::leave", _drawable._widgets_under_mouse, {})
    _drawable._widgets_under_mouse = {}
end

local function handle_motion(_drawable, x, y)
    if x < 0 or y < 0 or x > _drawable.drawable:geometry().width or y > _drawable.drawable:geometry().height then
        return handle_leave(_drawable)
    end

    -- Build a plain list of all widgets on that point
    local widgets_list = _drawable:find_widgets(x, y)
    local widgets = {}
    for k, v in pairs(widgets_list) do
        widgets[#widgets + 1] = v.widget
    end

    -- First, "leave" all widgets that were left
    emit_difference("mouse::leave", _drawable._widgets_under_mouse, widgets)
    -- Then enter some widgets
    emit_difference("mouse::enter", widgets, _drawable._widgets_under_mouse)

    _drawable._widgets_under_mouse = widgets
end

local function setup_signals(_drawable)
    local d = _drawable.drawable

    local function clone_signal(name)
        _drawable:add_signal(name)
        -- When "name" is emitted on wibox.drawin, also emit it on wibox
        d:connect_signal(name, function(_, ...)
            _drawable:emit_signal(name, ...)
        end)
    end
    clone_signal("button::press")
    clone_signal("button::release")
    clone_signal("mouse::enter")
    clone_signal("mouse::leave")
    clone_signal("mouse::move")
    clone_signal("property::surface")
    clone_signal("property::width")
    clone_signal("property::height")
    clone_signal("property::x")
    clone_signal("property::y")
end

function drawable.new(d, widget_arg, redraw_hook)
    local ret = object()
    ret.drawable = d
    ret.widget_arg = widget_arg or ret
    setup_signals(ret)

    for k, v in pairs(drawable) do
        if type(v) == "function" then
            ret[k] = v
        end
    end

    -- Only redraw a drawable once, even when we get told to do so multiple times.
    ret._redraw_pending = false
    ret._redraw_hook = redraw_hook
    ret._do_redraw = function()
        ret._redraw_pending = false
        capi.awesome.disconnect_signal("refresh", ret._do_redraw)
        do_redraw(ret)
    end

    -- Connect our signal when we need a redraw
    ret.draw = function()
        if not ret._redraw_pending then
            capi.awesome.connect_signal("refresh", ret._do_redraw)
            ret._redraw_pending = true
        end
    end
    drawables[ret.draw] = true
    d:connect_signal("property::surface", ret.draw)

    -- Set the default background
    ret:set_bg(beautiful.bg_normal)
    ret:set_fg(beautiful.fg_normal)

    -- Initialize internals
    ret._widget_geometries = {}
    ret._widgets_under_mouse = {}

    local function button_signal(name)
        d:connect_signal(name, function(d, x, y, ...)
            local widgets = ret:find_widgets(x, y)
            for k, v in pairs(widgets) do
                -- Calculate x/y inside of the widget
                local lx = x - v.x
                local ly = y - v.y
                v.widget:emit_signal(name, lx, ly, ...)
            end
        end)
    end
    button_signal("button::press")
    button_signal("button::release")

    d:connect_signal("mouse::move", function(_, x, y) handle_motion(ret, x, y) end)
    d:connect_signal("mouse::leave", function() handle_leave(ret) end)

    -- Make sure the drawable is drawn at least once
    ret.draw()

    return ret
end

-- Redraw all drawables when the wallpaper changes
capi.awesome.connect_signal("wallpaper_changed", function()
    local k
    for k in pairs(drawables) do
        k()
    end
end)

--- Handling of drawables. A drawable is something that can be drawn to.
-- @class table
-- @name drawable

return setmetatable(drawable, { __call = function(_, ...) return drawable.new(...) end })

-- vim: filetype=lua:expandtab:shiftwidth=4:tabstop=8:softtabstop=4:textwidth=80
