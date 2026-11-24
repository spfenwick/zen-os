-- common/source_badge.lua
-- The badge a book source gives one of its books (source.badge(path), see
-- common/book_sources.lua): an SVG icon, painted in ZenOS's badge colours
-- in a circle in the cover's bottom-right corner. A series number there
-- moves left of it (shift()).
--
-- Painted by every cover ZenOS draws for a book: the library mosaic and
-- list, Home's strips and its featured book.

local Blitbuffer = require("ffi/blitbuffer")
local Device = require("device")
local utils = require("common/utils")
local logger = require("common/zen_logger").new("source_badge")

local M = {}

-- icon .. "|" .. size -> alpha mask (BB8), or false when it can't be drawn.
local masks = {}
local mask_count = 0
local MAX_MASKS = 64

local function plugin_config()
    local plugin = rawget(_G, "__ZEN_UI_PLUGIN")
    return plugin and type(plugin.config) == "table" and plugin.config or nil
end

--- The badge a source gives this path ({ icon = path }), or nil.
function M.get(path)
    if type(path) ~= "string" or path == "" then return nil end
    local BookSources = package.loaded["common/book_sources"]
    if type(BookSources) ~= "table" or type(BookSources.badge) ~= "function" then return nil end
    local ok, badge = pcall(BookSources.badge, path)
    return ok and badge or nil
end

--- The badge's radius on a cover of this size: the size of ZenOS's other
-- cover badges, but at most about half the cover's shorter side.
function M.radius(width, height, config)
    local base = math.max(Device.screen:scaleBySize(20), math.floor(width * 0.14))
    local size = math.floor(base * utils.getBadgeScale(config or plugin_config()))
    size = math.min(size, math.floor(math.min(width, height) * 0.45))
    return math.max(1, math.floor(size / 2))
end

--- How far left a bottom-right badge (the series number) moves to make
-- room for the source badge on a cover of this size. With series_radius
-- (that badge's radius), nil when it would then stick out past the
-- cover's left edge: the cover is too small for both, so leave it out.
function M.shift(width, height, config, series_radius)
    local r = M.radius(width, height, config)
    local shift = 2 * r + math.max(2, math.floor(r * 0.4))
    if series_radius then
        -- Its centre, from the cover's left edge, less its outlined radius.
        local left = width - series_radius - utils.getBadgeInset(series_radius) - shift
            - (series_radius + 2)
        if left < 0 then return nil end
    end
    return shift
end

-- The icon as an alpha mask (ink = 255), so it can be painted in any colour.
local function mask(icon, size)
    local key = icon .. "|" .. size
    local cached = masks[key]
    if cached ~= nil then return cached or nil end
    local RenderImage = require("ui/renderimage")
    local ok, src = pcall(RenderImage.renderSVGImageFile, RenderImage, icon, size, size)
    local result = false
    if ok and src then
        local w, h = src:getWidth(), src:getHeight()
        local out = Blitbuffer.new(w, h, Blitbuffer.TYPE_BB8)
        for y = 0, h - 1 do
            for x = 0, w - 1 do
                local c = src:getPixel(x, y)
                -- Dark, opaque pixels are ink: works for an icon drawn on a
                -- transparent background and for one on white.
                local ink = math.floor(c:getAlpha() * (255 - c:getColor8().a) / 255 + 0.5)
                out:setPixel(x, y, Blitbuffer.Color8(ink))
            end
        end
        src:free()
        result = out
    else
        logger.warn("source badge icon can't be drawn", icon, src)
    end
    if mask_count >= MAX_MASKS then
        for _k, m in pairs(masks) do if m then m:free() end end
        masks, mask_count = {}, 0
    end
    masks[key] = result
    mask_count = mask_count + 1
    return result or nil
end

--- Paints badge (from get()) in the bottom-right corner of the cover at
-- x, y (width × height). config: ZenOS's config (its badge colours and
-- size), or nil for the running plugin's.
function M.paint(bb, badge, x, y, width, height, config)
    if type(badge) ~= "table" or type(badge.icon) ~= "string" then return end
    if not (width and height and width > 0 and height > 0) then return end
    config = config or plugin_config()
    local r = M.radius(width, height, config)
    local inset = utils.getBadgeInset(r)
    local cx = x + width - r - inset
    local cy = y + height - r - inset
    local foreground = utils.getBadgeTextColor(config)
    utils.paintBadgeCircle(bb, cx, cy, r + 2, foreground)
    utils.paintBadgeCircle(bb, cx, cy, r, utils.getBadgeColor(config))
    local m = mask(badge.icon, math.max(1, math.floor(r * 1.45)))
    if not m then return end
    local mw, mh = m:getWidth(), m:getHeight()
    local mx, my = cx - math.floor(mw / 2), cy - math.floor(mh / 2)
    if Blitbuffer.isColor8 and not Blitbuffer.isColor8(foreground) then
        bb:colorblitFromRGB32(m, mx, my, 0, 0, mw, mh, foreground)
    else
        bb:colorblitFrom(m, mx, my, 0, 0, mw, mh, foreground)
    end
end

--- Paints the source badge for path on a cover frame (after the frame
-- paints itself), for covers ZenOS draws without other badges.
function M.decorate(frame, path)
    if type(frame) ~= "table" or type(frame.paintTo) ~= "function" then return end
    local orig = frame.paintTo
    frame.paintTo = function(self, bb, x, y)
        orig(self, bb, x, y)
        local badge = M.get(path)
        local d = self.dimen
        if badge and d and d.w and d.h then M.paint(bb, badge, x, y, d.w, d.h) end
    end
end

--- Drops the drawn icons (tests; a source whose icon files changed).
function M.clear()
    for _k, m in pairs(masks) do if m then m:free() end end
    masks, mask_count = {}, 0
end

return M
