describe("statistics book records", function()
    local real_sources

    before_each(function()
        real_sources = package.loaded["common/book_sources"]
        ZenSpec.replace("common/zen_logger", {
            new = function() return { warn = function() end, info = function() end } end,
        })
        ZenSpec.replace("common/tbr_index", {
            getByStatuses = function(statuses)
                if statuses.tbr then return {} end
                return { "/books/local.epub", "/cloud/read.epub", "/cloud/unknown.epub" }
            end,
            isExplicit = function() return false end,
        })
        ZenSpec.replace("common/paths", { isInHomeDir = function() return true end })
        ZenSpec.replace("readhistory", { hist = {} })
        ZenSpec.replace("libs/libkoreader-lfs", {
            attributes = function() return { modification = 1, size = 10 } end,
        })
        ZenSpec.replace("docsettings", {
            findSidecarFile = function(_self, path)
                if path == "/books/local.epub" then return "/books/local.sdr/metadata.epub.lua" end
            end,
            openSettingsFile = function()
                return { data = {
                    summary = { status = "reading" },
                    doc_props = { title = "Local", authors = "A" },
                    partial_md5_checksum = "md5",
                    percent_finished = 0.5,
                    doc_pages = 100,
                } }
            end,
        })
        ZenSpec.unload("modules/filebrowser/patches/stats_tabs/books")
    end)

    after_each(function()
        package.loaded["common/book_sources"] = real_sources
        ZenSpec.unload("modules/filebrowser/patches/stats_tabs/books")
    end)

    it("adds books without a sidecar from their book source's status", function()
        package.loaded["common/book_sources"] = {
            status = function(path)
                if path == "/cloud/read.epub" then
                    return { status = "complete", percent_finished = 1 }
                end
            end,
            bookInfo = function(path)
                if path == "/cloud/read.epub" then
                    return { title = "Cloud", authors = "B\nC", pages = 320 }
                end
            end,
        }

        local records = require("modules/filebrowser/patches/stats_tabs/books").scan()

        assert.are.equal(2, #records)
        assert.are.equal("/books/local.epub", records[1].file)
        assert.are.equal("md5", records[1].md5)
        assert.are.same({
            file = "/cloud/read.epub", status = "complete", title = "Cloud",
            authors = "B, C", percent = 1, pages = 320,
        }, records[2])
    end)

    it("skips books without a sidecar when no book source is loaded", function()
        package.loaded["common/book_sources"] = nil

        local records = require("modules/filebrowser/patches/stats_tabs/books").scan()

        assert.are.equal(1, #records)
        assert.are.equal("/books/local.epub", records[1].file)
    end)
end)
