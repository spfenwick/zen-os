-- Book sources' books without a file (common/book_sources.lua) are listed
-- in their folders like files. Code that lists a folder's books with its
-- own lfs.dir scan misses them unless it asks BookSources too (a folder
-- cover's count and images, "all finished", ...). This keeps every lfs.dir
-- user classified: a new one fails here until it is.
describe("book listing scans", function()
    -- Lists a folder's books, so it must add the sources' books (it
    -- references BookSources: visibleFolderBooks, addToListing or books()).
    local BOOK_SCANS = {
        ["modules/filebrowser/folder_cover.lua"] = "folder covers: count, images, all finished",
        ["common/tbr_index.lua"] = "To Be Read scope (adds BookSources.books())",
    }
    -- Reads directories for something other than a folder's book list.
    local OTHER = {
        ["common/book_walker.lua"] = "generic walker; the flat view adds the sources' books per folder",
        ["modules/filebrowser/patches/browser_item_table_cache.lua"] = "folder signatures and child mtimes",
        ["modules/filebrowser/patches/navbar.lua"] = "folder mtime snapshot",
        ["modules/filebrowser/patches/context_menu_file_dialog.lua"] =
            "fallbacks without a file chooser, and whether a folder is empty after a move",
        ["common/cover_utils.lua"] = "fallback without a file chooser (whose listing has the sources' books)",
        ["common/folder_cover_files.lua"] = "folder cover image files",
        ["modules/filebrowser/metadata/epub.lua"] = "inside an unpacked EPUB",
        ["modules/filebrowser/patches/kindle_virtual_library.lua"] = "Kindle thumbnails",
        ["modules/filebrowser/patches/incompatible_plugins_check.lua"] = "plugin folders",
        ["modules/menu/app_launcher/plugin_scan.lua"] = "plugin folders",
        ["modules/filebrowser/patches/home/home_quotes.lua"] = "quote files",
        ["common/hid_keys.lua"] = "input devices",
        ["common/library_font_path.lua"] = "fonts",
        ["common/icon_packs.lua"] = "icon packs",
        ["common/opds_cover_cache.lua"] = "cached OPDS covers",
        ["common/brand_migration.lua"] = "settings migration",
        ["common/utils.lua"] = "icon files",
        ["common/quickstart/quickstart_pages.lua"] = "sample covers from the home folder's files",
    }

    local function lua_files()
        local root = ZenSpec.root
        local out = {}
        local handle = assert(io.popen("cd '" .. root .. "' && find common modules config main.lua -name '*.lua' 2>/dev/null"))
        for line in handle:lines() do out[#out + 1] = line end
        handle:close()
        return out
    end

    local function read(path)
        local f = assert(io.open(ZenSpec.root .. "/" .. path, "r"))
        local text = f:read("*a")
        f:close()
        return text
    end

    it("classifies every lfs.dir user", function()
        local unknown = {}
        for _i, path in ipairs(lua_files()) do
            local text = read(path)
            -- Code, not comments.
            local code = text:gsub("%-%-%[%[.-%]%]", ""):gsub("%-%-[^\n]*", "")
            if code:find("lfs.dir", 1, true) and not BOOK_SCANS[path] and not OTHER[path] then
                unknown[#unknown + 1] = path
            end
        end
        assert.are.same({}, unknown,
            "classify these lfs.dir users above; a book scan must add the book sources' books")
    end)

    it("has every book scan ask the book sources", function()
        for path in pairs(BOOK_SCANS) do
            local text = read(path)
            assert.is_truthy(text:find("BookSources", 1, true) or text:find("book_sources", 1, true),
                path .. " lists books without the book sources")
        end
    end)
end)
