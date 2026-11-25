-- Book sources' books without a file, listed by KOReader's own FileChooser
-- (frontend/ui/widget/filechooser.lua, from the pinned KOReader): only its
-- UI layer (device, BookList's Menu, UIManager) is stubbed, so its listing
-- and counting code is the real one. If KOReader stops counting a folder
-- through getList(path) without collate (getPathList), or changes
-- getListItem or show_file, this fails before devices see wrong counts.
describe("book sources in KOReader's file chooser", function()
    local lfs = require("libs/libkoreader-lfs")
    local STUBBED = {
        "device", "ui/widget/booklist", "ui/uimanager", "readcollection",
        "document/documentregistry", "ui/bidi", "apps/filemanager/filemanagerutil",
        "ui/widget/filechooser", "common/book_sources", "common/zen_logger",
        "common/book_sources_kindle",
    }
    local saved, FileChooser, BookSources, root

    local function write(path)
        local f = assert(io.open(path, "w"))
        f:write("x")
        f:close()
    end

    local function remove_tree(path)
        for name in lfs.dir(path) do
            if name ~= "." and name ~= ".." then
                local full = path .. "/" .. name
                if lfs.attributes(full, "mode") == "directory" then remove_tree(full) else os.remove(full) end
            end
        end
        lfs.rmdir(path)
    end

    before_each(function()
        saved = {}
        for _i, name in ipairs(STUBBED) do saved[name] = package.loaded[name] end
        pcall(require, "ffi/loadlib")
        ZenSpec.replace("device", { screen = {}, home_dir = "/" })
        local BookList = {
            hasBookBeenOpened = function() return false end,
            getBookStatus = function() return "new" end,
            init = function() end,
        }
        function BookList:extend(o) return setmetatable(o or {}, { __index = self }) end
        ZenSpec.replace("ui/widget/booklist", BookList)
        ZenSpec.replace("ui/uimanager", {})
        ZenSpec.replace("readcollection", { isFileInCollections = function() return false end })
        ZenSpec.replace("document/documentregistry", { hasProvider = function() return true end })
        ZenSpec.replace("ui/bidi", { filename = function(s) return s end, directory = function(s) return s end })
        ZenSpec.replace("apps/filemanager/filemanagerutil", {})
        ZenSpec.replace("common/zen_logger", {
            now = function() return 0 end,
            new = function() return { warn = function() end } end,
        })
        ZenSpec.replace("common/book_sources_kindle", { books = function() return {} end })
        ZenSpec.unload("ui/widget/filechooser")
        FileChooser = require("ui/widget/filechooser")
        assert.is_function(FileChooser.getPathList, "KOReader's FileChooser has no getPathList")
        -- KOReader reads it with a default; the spec's settings have none.
        FileChooser.show_filter = FileChooser.show_filter or {}
        ZenSpec.unload("common/book_sources")
        BookSources = require("common/book_sources")

        root = os.tmpname()
        os.remove(root)
        assert(lfs.mkdir(root))
        assert(lfs.mkdir(root .. "/Sub"))
        write(root .. "/Sub/Real - Book.epub")
        write(root .. "/Here - Real.epub")
        local books = {
            { file = root .. "/Sub/Cloud - One.epub", info = { title = "Cloud One" },
              attr = { size = 2048, modification = 1700000000 } },
            { file = root .. "/Sub/Real - Book.epub", info = { title = "Downloaded" } }, -- has a file
            { file = root .. "/Here - Cloud.epub", info = { title = "Cloud Here" } },
        }
        BookSources.register("cloud", {
            books = function() return books end,
            owns = function(path)
                for _i, b in ipairs(books) do if b.file == path then return true end end
                return false
            end,
            listingKey = function() return "v1" end,
        })
        assert.is_true(BookSources.installListingIntegration())
    end)

    after_each(function()
        for _i, name in ipairs(STUBBED) do package.loaded[name] = saved[name] end
        if root then remove_tree(root) end
    end)

    local function chooser()
        return setmetatable({
            name = "filemanager",
            ui = { folder_shortcuts = { hasFolderShortcut = function() return false end } },
        }, { __index = FileChooser })
    end

    it("counts a folder's books without a file in the folder above", function()
        local fc = chooser()
        local mandatory = fc:getMenuItemMandatory({ path = root .. "/Sub" })
        -- One file on disk, one source book without a file; the source book
        -- with a file isn't counted twice.
        assert.are.equal(2, tonumber(mandatory:match("^(%d+)")), mandatory)
    end)

    it("lists them with the real getListItem", function()
        local fc = chooser()
        local _dirs, files = fc:getList(root .. "/Sub", { text = "name" })
        local paths = {}
        for _i, item in ipairs(files) do paths[item.path] = item end
        local cloud = paths[root .. "/Sub/Cloud - One.epub"]
        assert.is_table(cloud)
        assert.is_true(cloud.is_file)
        assert.are.equal("cloud", cloud._zen_source)
        assert.are.equal(2048, cloud.attr.size)
        assert.are.equal("Cloud One", cloud.doc_props.title)
        assert.is_table(paths[root .. "/Sub/Real - Book.epub"])
        assert.are.equal(2, #files)
    end)

    it("follows the file browser's filters", function()
        local fc = chooser()
        fc.exclude_files = { "^Here %- Cloud" }
        local _dirs, files = fc:getList(root, { text = "name" })
        for _i, item in ipairs(files) do
            assert.are_not.equal(root .. "/Here - Cloud.epub", item.path)
        end
    end)
end)
