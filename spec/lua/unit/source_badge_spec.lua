require("ffi/loadlib")

describe("book source badges", function()
    local Blitbuffer = require("ffi/blitbuffer")
    local BookSources, SourceBadge, warnings, icon_path, plugin, original_device

    -- A black square on a transparent background, inset in a 24x24 box.
    local SQUARE_SVG = [[<svg xmlns="http://www.w3.org/2000/svg" width="24" height="24" viewBox="0 0 24 24">
<rect x="4" y="4" width="16" height="16" fill="#000000"/></svg>]]

    before_each(function()
        warnings = {}
        plugin = rawget(_G, "__ZEN_UI_PLUGIN")
        original_device = package.loaded["device"]
        _G.__ZEN_UI_PLUGIN = nil
        ZenSpec.replace("common/zen_logger", {
            now = function() return 0 end,
            new = function()
                return {
                    warn = function(...) warnings[#warnings + 1] = { ... } end,
                    dbg = function() end,
                }
            end,
        })
        ZenSpec.replace("common/book_sources_kindle", { books = function() return {} end })
        ZenSpec.replace("device", { screen = { scaleBySize = function(_self, size) return size end } })
        ZenSpec.unload("common/book_sources")
        ZenSpec.unload("common/source_badge")
        BookSources = require("common/book_sources")
        SourceBadge = require("common/source_badge")
        icon_path = os.tmpname() .. ".svg"
        local f = assert(io.open(icon_path, "w"))
        f:write(SQUARE_SVG)
        f:close()
    end)

    after_each(function()
        SourceBadge.clear()
        os.remove(icon_path)
        _G.__ZEN_UI_PLUGIN = plugin
        package.loaded["device"] = original_device
    end)

    it("takes the badge from the first source that gives one", function()
        BookSources.register("broken", {
            books = function() return {} end,
            badge = function() error("badge failed") end,
        })
        BookSources.register("odd", {
            books = function() return {} end,
            badge = function() return { icon = "" } end,
        })
        BookSources.register("cloud", {
            books = function() return {} end,
            badge = function(path) if path == "/books/a.epub" then return { icon = "/i/cloud.svg" } end end,
        })
        BookSources.register("later", {
            books = function() return {} end,
            badge = function() return { icon = "/i/other.svg" } end,
        })

        assert.are.same({ icon = "/i/cloud.svg" }, BookSources.badge("/books/a.epub"))
        assert.are.same({ icon = "/i/other.svg" }, BookSources.badge("/books/b.epub"))
        assert.is_nil(BookSources.badge(""))
        assert.is_nil(BookSources.badge(nil))
        assert.is_true(#warnings > 0)
        assert.are.same({ icon = "/i/cloud.svg" }, SourceBadge.get("/books/a.epub"))
    end)

    it("gives no badge without sources that have one", function()
        BookSources.register("plain", { books = function() return {} end })
        assert.is_nil(BookSources.badge("/books/a.epub"))
        assert.is_nil(SourceBadge.get("/books/a.epub"))
    end)

    it("paints the icon in the badge's foreground colour, in the bottom-right corner", function()
        local bb = Blitbuffer.new(200, 300, Blitbuffer.TYPE_BB8)
        bb:fill(Blitbuffer.COLOR_WHITE)
        SourceBadge.paint(bb, { icon = icon_path }, 0, 0, 200, 300, {})

        local r = SourceBadge.radius(200, 300, {})
        local inset = math.floor(r * 0.40)
        local cx, cy = 200 - r - inset, 300 - r - inset
        -- Default colours: a black circle with the icon in white.
        assert.are.equal(0xFF, bb:getPixel(cx, cy):getColor8().a)
        assert.are.equal(0x00, bb:getPixel(cx, cy - r + 2):getColor8().a)
        -- Nothing outside the corner.
        assert.are.equal(0xFF, bb:getPixel(20, 20):getColor8().a)
        assert.are.equal(0xFF, bb:getPixel(cx - 2 * r - 4, cy):getColor8().a)
        bb:free()
    end)

    it("paints the circle without the icon when it can't be drawn", function()
        local bb = Blitbuffer.new(200, 300, Blitbuffer.TYPE_BB8)
        bb:fill(Blitbuffer.COLOR_WHITE)
        SourceBadge.paint(bb, { icon = "/nonexistent/icon.svg" }, 0, 0, 200, 300, {})
        local r = SourceBadge.radius(200, 300, {})
        local inset = math.floor(r * 0.40)
        assert.are.equal(0x00, bb:getPixel(200 - r - inset, 300 - r - inset):getColor8().a)
        bb:free()
    end)

    it("keeps the badge within small covers and moves it clear of the series badge", function()
        assert.is_true(SourceBadge.radius(40, 60, {}) * 2 <= math.floor(40 * 0.45))
        local r = SourceBadge.radius(200, 300, {})
        local series_r = 15
        local shift = SourceBadge.shift(200, 300, {}, series_r)
        -- Moved left past the series badge, which stays in the corner: their
        -- outlined circles don't touch.
        local series_cx = 200 - series_r - math.floor(series_r * 0.4)
        local cx = 200 - r - math.floor(r * 0.4) - shift
        assert.is_true(series_cx - cx >= r + series_r + 4)
        assert.is_true(cx - r - 2 >= 0)
        -- nil: no room for both (the source badge is left out).
        assert.is_nil(SourceBadge.shift(40, 60, {}, 11))
    end)

    it("stays clear of the page count on the left, or is left out", function()
        local r = SourceBadge.radius(200, 300, {})
        local inset = math.floor(r * 0.4)
        local gap = math.max(2, math.floor(r * 0.4))
        -- In the corner, with nothing else there.
        assert.are.equal(0, SourceBadge.shift(200, 300, {}))
        local left = 200 - r - inset - (r + 2) -- its outlined left edge, in the corner
        assert.are.equal(0, SourceBadge.shift(200, 300, {}, nil, left - gap))
        assert.is_nil(SourceBadge.shift(200, 300, {}, nil, left - gap + 1))
        -- Beside the series number, the page count must still be clear of it.
        local shift = SourceBadge.shift(200, 300, {}, 15)
        assert.are.equal(shift, SourceBadge.shift(200, 300, {}, 15, left - shift - gap))
        assert.is_nil(SourceBadge.shift(200, 300, {}, 15, left - shift - gap + 1))
    end)

    it("paints the badge moved left by shift", function()
        local bb = Blitbuffer.new(200, 300, Blitbuffer.TYPE_BB8)
        bb:fill(Blitbuffer.COLOR_WHITE)
        local shift = SourceBadge.shift(200, 300, {}, 15)
        SourceBadge.paint(bb, { icon = "/nonexistent/icon.svg" }, 0, 0, 200, 300, {}, shift)
        local r = SourceBadge.radius(200, 300, {})
        local inset = math.floor(r * 0.40)
        assert.are.equal(0x00, bb:getPixel(200 - r - inset - shift, 300 - r - inset):getColor8().a)
        -- The corner is left for the series badge.
        assert.are.equal(0xFF, bb:getPixel(200 - 15 - math.floor(15 * 0.4), 300 - r - inset):getColor8().a)
        bb:free()
    end)

    it("decorates a cover frame with the badge its source gives now", function()
        local badge = { icon = icon_path }
        BookSources.register("cloud", {
            books = function() return {} end,
            badge = function() return badge end,
        })
        local painted = 0
        local frame = {
            dimen = { w = 200, h = 300 },
            paintTo = function() painted = painted + 1 end,
        }
        SourceBadge.decorate(frame, "/books/a.epub")
        local bb = Blitbuffer.new(200, 300, Blitbuffer.TYPE_BB8)
        bb:fill(Blitbuffer.COLOR_WHITE)
        frame:paintTo(bb, 0, 0)
        assert.are.equal(1, painted)
        local r = SourceBadge.radius(200, 300, {})
        local inset = math.floor(r * 0.40)
        assert.are.equal(0x00, bb:getPixel(200 - r - inset, 300 - 2 * r - inset + 2):getColor8().a)

        badge = nil
        bb:fill(Blitbuffer.COLOR_WHITE)
        frame:paintTo(bb, 0, 0)
        assert.are.equal(2, painted)
        assert.are.equal(0xFF, bb:getPixel(200 - r - inset, 300 - 2 * r - inset + 2):getColor8().a)
        bb:free()
    end)
end)
