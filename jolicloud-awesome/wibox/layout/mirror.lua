---------------------------------------------------------------------------
-- @author dodo
-- @copyright 2012 dodo
-- @release v3.4-799-g4711354
---------------------------------------------------------------------------

local type = type
local error = error
local pairs = pairs
local ipairs = ipairs
local setmetatable = setmetatable
local base = require("wibox.layout.base")
local widget_base = require("wibox.widget.base")

-- wibox.layout.mirror
local mirror = { mt = {} }

--- Draw this layout
function mirror.draw(layout, wibox, cr, width, height)
    if not layout.widget then return { width = 0, height = 0 } end
    if not layout.horizontal and not layout.vertical then
        layout.widget:draw(wibox, cr, width, height)
        return -- nothing changed
    end

    cr:save()

    local t = { x = 0, y = 0 } -- translation
    local s = { x = 1, y = 1 } -- scale
    if layout.horizontal then
        t.y = height
        s.y = -1
    end
    if layout.vertical then
        t.x = width
        s.x = -1
    end
    cr:translate(t.x, t.y)
    cr:scale(s.x, s.y)

    layout.widget:draw(wibox, cr, width, height)

    -- Undo the scale and translation from above.
    cr:restore()
end

--- Fit this layout into the given area
function mirror.fit(layout, ...)
    if not layout.widget then
        return 0, 0
    end
    return layout.widget:fit(...)
end

--- Set the widget that this layout mirrors.
-- @param layout The layout
-- @param widget The widget to mirror
function mirror.set_widget(layout, widget)
    if layout.widget then
        layout.widget:disconnect_signal("widget::updated", layout._emit_updated)
    end
    if widget then
        widget_base.check_widget(widget)
        widget:connect_signal("widget::updated", layout._emit_updated)
    end
    layout.widget = widget
    layout._emit_updated()
end

--- Reset this layout. The widget will be removed and the axes reset.
-- @param layout The layout
function mirror.reset(layout)
    layout.horizontal = false
    layout.vertical = false
    layout:set_widget(nil)
end

--- Set the reflection of this mirror layout.
-- @param layout The layout
-- @param reflection a table which contains new values for horizontal and/or vertical (booleans)
function mirror.set_reflection(layout, reflection)
    if type(reflection) ~= 'table' then
        error("Invalid type of reflection for mirror layout: " ..
              type(reflection) .. " (should be a table)")
    end
    for _, ref in ipairs({"horizontal", "vertical"}) do
        if reflection[ref] ~= nil then
            layout[ref] = reflection[ref]
        end
    end
    layout._emit_updated()
end

--- Get the reflection of this mirror layout.
--  @param layout The layout
--  @return a table of booleans with the keys "horizontal", "vertical".
function mirror.get_reflection(layout)
    return { horizontal = layout.horizontal, vertical = layout.vertical }
end

--- Returns a new mirror layout. A mirror layout mirrors a given widget. Use
-- :set_widget() to set the widget and
-- :set_horizontal() and :set_vertical() for the direction.
-- horizontal and vertical are by default false which doesn't change anything.
local function new()
    local ret = widget_base.make_widget()
    ret.horizontal = false
    ret.vertical = false

    for k, v in pairs(mirror) do
        if type(v) == "function" then
            ret[k] = v
        end
    end

    ret._emit_updated = function()
        ret:emit_signal("widget::updated")
    end

    return ret
end

function mirror.mt:__call(...)
    return new(...)
end

return setmetatable(mirror, mirror.mt)

-- vim: filetype=lua:expandtab:shiftwidth=4:tabstop=8:softtabstop=4:textwidth=80
