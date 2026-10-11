--[[--
Live Light.

KOReader's own edge swipes change the light once, after the finger lifts: it
waits for the whole swipe, measures it, then jumps. This plugin listens to the
"pan" events KOReader sends while the finger is still moving, and nudges the
light on each one, so brightness (left edge) and warmth (right edge) follow
the finger the way they do in Kobo's own software.

It takes over a vertical slide that starts in an edge strip by registering
touch zones that are ordered ahead of the reader's and of the Gestures
plugin's. Nothing in those is changed; anything that is not such a slide is
passed on to them untouched, and turning this plugin off hands the edges back.

While sliding, a small box shows the level. Only the number in it is redrawn
with the screen's fast black-and-white mode, a few times a second at most;
the word beside it is drawn once, cleanly, and the number is redrawn cleanly
whenever the finger pauses or lifts.
]]

local Blitbuffer = require("ffi/blitbuffer")
local CenterContainer = require("ui/widget/container/centercontainer")
local Device = require("device")
local Font = require("ui/font")
local FrameContainer = require("ui/widget/container/framecontainer")
local Geom = require("ui/geometry")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local HorizontalSpan = require("ui/widget/horizontalspan")
local LeftContainer = require("ui/widget/container/leftcontainer")
local Math = require("optmath")
local Size = require("ui/size")
local TextWidget = require("ui/widget/textwidget")
local UIManager = require("ui/uimanager")
local VerticalGroup = require("ui/widget/verticalgroup")
local VerticalSpan = require("ui/widget/verticalspan")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local T = require("ffi/util").template
local _ = require("gettext")

if not (Device:hasFrontlight() and Device:isTouchDevice()) then
    return { disabled = true }
end

local Screen = Device.screen

local SETTINGS_KEY = "livelight"
-- Width of each edge strip, as a share of the screen. Same as the strips
-- KOReader's own edge swipes use.
local EDGE = 1 / 8
-- Share of the screen height a finger travels to go from one end of the
-- range to the other.
local FULL_RANGE_TRAVEL = 0.7
-- The light itself changes on every step; only the box is held back, so
-- the e-ink screen is not asked to redraw faster than it can.
local DRAW_INTERVAL = 0.15
-- How long the level must hold still, finger down, before the number is
-- redrawn cleanly.
local SMOOTH_AFTER = 0.2
local HIDE_AFTER = 1

local function settings()
    local stored = G_reader_settings:readSetting(SETTINGS_KEY)
    if type(stored) ~= "table" then stored = {} end
    if stored.enabled == nil then stored.enabled = true end
    if stored.show_level == nil then stored.show_level = true end
    return stored
end

local function saveSetting(key, value)
    local stored = settings()
    stored[key] = value
    G_reader_settings:saveSetting(SETTINGS_KEY, stored)
end

-- ── The two things a slide can change ───────────────────────────────────────

local brightness = {
    range = function(powerd) return powerd.fl_min, powerd.fl_max end,
    get = function(powerd) return powerd:frontlightIntensity() end,
    set = function(powerd, level)
        -- Same rule as KOReader's own gesture: zero means off.
        if level <= 0 then
            powerd:turnOffFrontlight()
        else
            powerd:setIntensity(level)
        end
    end,
    name = _("Brightness"),
    value = function(powerd, level)
        return T(_("%1%"), Math.round((level - powerd.fl_min) / (powerd.fl_max - powerd.fl_min) * 100))
    end,
}

-- Warmth is handled in the device's own steps (0 to 10 on a Clara BW), as
-- KOReader's gesture and light dialog do, so that every step is a real change.
local warmth = {
    range = function(powerd) return powerd.fl_warmth_min, powerd.fl_warmth_max end,
    get = function(powerd) return powerd:toNativeWarmth(powerd:frontlightWarmth()) end,
    set = function(powerd, level) powerd:setWarmth(powerd:fromNativeWarmth(level)) end,
    name = _("Warmth"),
    value = function(powerd, level) return tostring(level) end,
}

local function controlAt(pos)
    local width = Screen:getWidth()
    if pos.x < width * EDGE then
        return brightness
    elseif pos.x >= width * (1 - EDGE) and Device:hasNaturalLight() then
        return warmth
    end
end

-- ── Level box ───────────────────────────────────────────────────────────────

-- A plain container, not an input one, and a toast: it never takes input, so
-- the slide that is driving it carries on reaching the zones underneath.
local LevelBox = WidgetContainer:extend{
    name = "",
    value = "",
    widest_value = "",
    toast = true,
}

function LevelBox:init()
    local face = Font:getFace("infofont")
    -- The number sits in a slot of fixed width, so that it can be redrawn by
    -- itself without the box or the word beside it ever changing.
    local sample = TextWidget:new{ text = self.widest_value, face = face }
    local slot = sample:getSize()
    sample:free()
    self.number = TextWidget:new{ text = self.value, face = face }
    self.number_slot = LeftContainer:new{
        dimen = Geom:new{ w = slot.w, h = slot.h },
        self.number,
    }
    self.frame = FrameContainer:new{
        background = Blitbuffer.COLOR_WHITE,
        bordersize = Size.border.window,
        radius = Size.radius.window,
        margin = 0,
        padding = Size.padding.large,
        HorizontalGroup:new{
            TextWidget:new{ text = self.name, face = face },
            HorizontalSpan:new{ width = Size.span.horizontal_default },
            self.number_slot,
        },
    }
    self[1] = VerticalGroup:new{
        VerticalSpan:new{ width = math.floor(Screen:getHeight() / 8) },
        CenterContainer:new{
            dimen = Geom:new{ w = Screen:getWidth(), h = self.frame:getSize().h },
            self.frame,
        },
    }
end

-- The fast mode is black and white only, which is what makes text drawn with
-- it look jagged. So it is used for the number alone, while it is changing.
function LevelBox:redrawNumber(value, mode)
    self.number:setText(value)
    UIManager:setDirty(self, function() return mode, self.number_slot.dimen end)
end

function LevelBox:onShow()
    UIManager:setDirty(self, function() return "ui", self.frame.dimen end)
    return true
end

function LevelBox:onCloseWidget()
    UIManager:setDirty(nil, function() return "ui", self.frame.dimen end)
end

-- ── Slide state ─────────────────────────────────────────────────────────────
-- Shared by the file browser's and the reader's instance of the plugin.

local slide = nil         -- { key, control, min, max, start, anchor_y, level }
local passed_on = nil     -- key of a touch that was looked at and left to others
local box = nil
local box_name, box_value = nil, nil
local draw_held = false   -- a redraw happened less than DRAW_INTERVAL ago
local draw_wanted = false -- the level changed while redraws were held
local number_rough = false -- the number on screen was last drawn in the fast mode

local releaseDraw

local function hideBox()
    if box then
        UIManager:close(box)
        box = nil
    end
end

local function drawBox(mode)
    if not (settings().show_level and box_name) then return end
    UIManager:unschedule(hideBox)
    if box and box.name ~= box_name then
        -- Left over from a slide on the other edge a moment ago.
        hideBox()
    end
    if box then
        box:redrawNumber(box_value, mode)
        number_rough = mode == "fast"
    else
        local powerd = Device:getPowerDevice()
        box = LevelBox:new{
            name = box_name,
            value = box_value,
            widest_value = brightness.value(powerd, powerd.fl_max),
        }
        UIManager:show(box)
        number_rough = false
    end
end

local function smoothNumber()
    if number_rough then drawBox("ui") end
end

local function drawBoxFast()
    drawBox("fast")
    draw_held = true
    UIManager:scheduleIn(DRAW_INTERVAL, releaseDraw)
    -- Pushed back by every change, so it only runs once the level holds still.
    UIManager:unschedule(smoothNumber)
    UIManager:scheduleIn(SMOOTH_AFTER, smoothNumber)
end

releaseDraw = function()
    draw_held = false
    if draw_wanted then
        draw_wanted = false
        drawBoxFast()
    end
end

local function drawBoxSoon()
    if draw_held then
        draw_wanted = true
        return
    end
    drawBoxFast()
end

local function begin(key, control, y)
    local powerd = Device:getPowerDevice()
    local min, max = control.range(powerd)
    local level = control.get(powerd)
    slide = {
        key = key,
        control = control,
        min = min,
        max = max,
        start = level,
        -- Measured from here rather than from where the finger landed, so the
        -- light does not jump by the distance it took to be seen as a slide.
        anchor_y = y,
        level = level,
    }
    box_name, box_value = control.name, control.value(powerd, level)
    drawBoxSoon()
end

local function moveTo(y)
    local step = Screen:getHeight() * FULL_RANGE_TRAVEL / (slide.max - slide.min)
    local level = Math.round(slide.start + (slide.anchor_y - y) / step)
    -- Past either end, drag the anchor along with the finger, so that
    -- turning back takes effect at once instead of after retracing the excess.
    if level > slide.max then
        level = slide.max
        slide.anchor_y = y + (level - slide.start) * step
    elseif level < slide.min then
        level = slide.min
        slide.anchor_y = y + (level - slide.start) * step
    end
    if level == slide.level then return end
    slide.level = level
    local powerd = Device:getPowerDevice()
    slide.control.set(powerd, level)
    box_value = slide.control.value(powerd, level)
    drawBoxSoon()
end

local function finish()
    if not slide then return end
    slide = nil
    -- As KOReader's own gesture does, so waking from sleep restores this state.
    Device:getPowerDevice():updateResumeFrontlightState()
    UIManager:unschedule(releaseDraw)
    UIManager:unschedule(smoothNumber)
    draw_held, draw_wanted = false, false
    -- One clean redraw of the final number, clearing what the fast mode left,
    -- unless a pause just before the lift has already done it.
    if number_rough or not box or box.number.text ~= box_value then
        drawBox("ui")
    else
        UIManager:unschedule(hideBox)
    end
    UIManager:scheduleIn(HIDE_AFTER, hideBox)
end

local function abandon()
    slide, passed_on = nil, nil
    UIManager:unschedule(releaseDraw)
    UIManager:unschedule(smoothNumber)
    UIManager:unschedule(hideBox)
    draw_held, draw_wanted = false, false
    hideBox()
end

-- ── Gesture handlers ────────────────────────────────────────────────────────
-- Each returns true to keep the gesture, or false to pass it on unchanged.

local function touchKey(pos)
    return pos.x .. ":" .. pos.y
end

local function onPan(ges)
    if not settings().enabled then return false end
    local key = touchKey(ges.start_pos)
    if slide and slide.key ~= key then
        -- The previous slide's lift never arrived (a second finger joined).
        finish()
    end
    if not slide then
        if passed_on == key then return false end
        local control = controlAt(ges.start_pos)
        if not control or math.abs(ges.relative.y) < math.abs(ges.relative.x) then
            -- Not on an edge, or heading sideways (a page turn): leave this
            -- touch alone until it lifts, even if it later turns vertical.
            passed_on = key
            return false
        end
        begin(key, control, ges.pos.y)
    end
    moveTo(ges.pos.y)
    return true
end

local function onPanRelease(ges)
    passed_on = nil
    if not slide then return false end
    moveTo(ges.pos.y)
    finish()
    return true
end

-- A quick slide ends in a "swipe" rather than a "pan_release", and one that
-- changed direction on the way in a "multiswipe". Both are kept, so the
-- Gestures plugin does not add its own jump on top of what was just set.
local function onSwipe(ges)
    passed_on = nil
    if slide then
        if ges.end_pos then moveTo(ges.end_pos.y) end
        finish()
        return true
    end
    -- A flick too quick to have been seen as a slide first.
    if ges.ges ~= "swipe" or not settings().enabled then return false end
    if ges.direction ~= "north" and ges.direction ~= "south" then return false end
    local control = controlAt(ges.pos)
    if not control then return false end
    begin(touchKey(ges.pos), control, ges.pos.y)
    moveTo(ges.end_pos.y)
    finish()
    return true
end

-- ── Plugin ──────────────────────────────────────────────────────────────────

local LiveLight = WidgetContainer:extend{
    name = "livelight",
    is_doc_only = false,
}

function LiveLight:init()
    self.ui.menu:registerToMainMenu(self)

    local everywhere = { ratio_x = 0, ratio_y = 0, ratio_w = 1, ratio_h = 1 }
    -- The Gestures plugin's edge swipes, and the placeholders it registers
    -- beside each of them.
    local edge_swipes = {
        "one_finger_swipe_left_edge_down",
        "one_finger_swipe_left_edge_up",
        "one_finger_swipe_right_edge_down",
        "one_finger_swipe_right_edge_up",
    }
    local function ahead_of(ids, suffix)
        for _, id in ipairs(edge_swipes) do
            table.insert(ids, id .. suffix)
        end
        return ids
    end
    -- The zones cover the whole screen because a slide is recognised by where
    -- it started, and must be followed wherever the finger wanders after.
    self.ui:registerTouchZones({
        {
            id = "livelight_pan",
            ges = "pan",
            screen_zone = everywhere,
            overrides = ahead_of({
                "rolling_pan",
                "paging_pan",
                "readermenu_pan",
                "readermenu_ext_pan",
                "readerconfigmenu_pan",
                "readerconfigmenu_ext_pan",
            }, "_pan"),
            handler = onPan,
        },
        {
            id = "livelight_pan_release",
            ges = "pan_release",
            screen_zone = everywhere,
            overrides = ahead_of({
                "rolling_pan_release",
                "paging_pan_release",
            }, "_pan_release"),
            handler = onPanRelease,
        },
        {
            id = "livelight_swipe",
            ges = "swipe",
            screen_zone = everywhere,
            overrides = ahead_of({
                "rolling_swipe",
                "paging_swipe",
                "swipe_link",
                "readermenu_swipe",
                "readermenu_ext_swipe",
                "readerconfigmenu_swipe",
                "readerconfigmenu_ext_swipe",
                "filemanager_swipe",
                "filemanager_ext_swipe",
            }, ""),
            handler = onSwipe,
        },
        {
            id = "livelight_multiswipe",
            ges = "multiswipe",
            screen_zone = everywhere,
            overrides = { "multiswipe" },
            handler = onSwipe,
        },
    })
end

function LiveLight:onSuspend()
    abandon()
end

function LiveLight:addToMainMenu(menu_items)
    menu_items.livelight = {
        text = _("Live Light"),
        sorting_hint = "taps_and_gestures",
        sub_item_table = {
            {
                text = _("Change the light while sliding along the screen edges"),
                help_text = _("Slide a finger up or down the left edge for brightness, or the right edge for warmth. The light follows your finger as it moves. When this is off, the edges go back to whatever is set in the gesture manager."),
                checked_func = function() return settings().enabled end,
                callback = function() saveSetting("enabled", not settings().enabled) end,
            },
            {
                text = _("Show the level while sliding"),
                help_text = _("A small box near the top of the screen with the current brightness or warmth. It disappears a moment after you lift your finger."),
                enabled_func = function() return settings().enabled end,
                checked_func = function() return settings().show_level end,
                callback = function() saveSetting("show_level", not settings().show_level) end,
            },
        },
    }
end

return LiveLight
