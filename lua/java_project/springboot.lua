-------------------------------------------------
-- Helpers
-------------------------------------------------
local U = require("java_project.utils")

local function urlencode(str)
    if not str then
        return ""
    end
    str = str:gsub("\n", "\r\n")
    return str:gsub("([^%w%-_%.~])", function(c)
        return string.format("%%%02X", string.byte(c))
    end)
end

local function capitalize(str)
    return (str and #str > 0) and (str:sub(1, 1):upper() .. str:sub(2)) or str
end

local function parse_boot_version(ver)
    local patterns = {
        { "%.RELEASE$", "" },
        { "%.BUILD%-SNAPSHOT$", "-SNAPSHOT" },
        { "%.(M%d+)$", "-%1" },
    }
    for _, p in ipairs(patterns) do
        if ver:match(p[1]) then
            return ver:gsub(p[1], p[2])
        end
    end
    return ver
end

-------------------------------------------------
-- Dependency Selector UI State
-------------------------------------------------
local DepUI = {
    buf = nil,
    win = nil,
    deps = {}, -- selected deps

    --  State for search functionality
    search_term = "", -- Current search query
    original_categories = {}, -- Full, unfiltered list of categories
    original_category_names = {}, -- Full, unfiltered list of category names

    -- These will now hold the currently displayed data (either full or filtered)
    categories = {}, -- map: name -> values
    category_names = {}, -- list of category names

    active_category = 1, -- index of current category
    cursor_dep = 1, -- index inside category
    callback = nil,
}

-------------------------------------------------
-- Render UI
-------------------------------------------------
local function render_ui()
    if not DepUI.buf then
        return
    end

    local lines = {
        "╔══════════════════════════════════════════════════════════════════════════════════════╗",
        "║                   Spring Boot Dependency Selector                                    ║",
        "╚══════════════════════════════════════════════════════════════════════════════════════╝",
        "",
        "[h/l] switch category   [j/k] move   [i/Enter] toggle   [/] search   [d] done   [q] quit",
        "",
    }

    -- { {line, start, end, hl_group}, ... }
    local highlights = {}

    -- highlight title
    table.insert(highlights, { 1, 0, -1, "Title" })
    table.insert(highlights, { 2, 0, -1, "Title" })
    table.insert(highlights, { 3, 0, -1, "Title" })

    if DepUI.search_term ~= "" then
        local search_line = "Searching for: '" .. DepUI.search_term .. "' (press '/' and Esc to clear)"
        table.insert(lines, search_line)
        table.insert(lines, "")
        table.insert(highlights, { #lines - 1, 0, -1, "Search" })
    end

    if #DepUI.deps > 0 then
        table.insert(lines, "Selected dependencies:")
        table.insert(highlights, { #lines, 0, -1, "Question" })
        for _, dep_id in ipairs(DepUI.deps) do
            table.insert(lines, "   • " .. dep_id)
            table.insert(highlights, { #lines, 0, -1, "String" })
        end
    else
        table.insert(lines, "No dependencies selected.")
        table.insert(highlights, { #lines, 0, -1, "Comment" })
    end
    table.insert(lines, string.rep("─", 85))

    if #DepUI.category_names == 0 then
        table.insert(lines, "No results found.")
        table.insert(highlights, { #lines, 0, -1, "Error" })
    end

    for i, cat in ipairs(DepUI.category_names) do
        local prefix = (i == DepUI.active_category) and "▶ " or "  "
        table.insert(lines, prefix .. cat)

        if i == DepUI.active_category then
            table.insert(highlights, { #lines, 0, -1, "Keyword" })
            for j, dep in ipairs(DepUI.categories[cat]) do
                local dep_id = dep.id
                local mark = vim.tbl_contains(DepUI.deps, dep_id) and "[✔]" or "[ ]"
                local cursor = (j == DepUI.cursor_dep) and "➤" or " "
                local line = string.format("   %s %s %s - %s", cursor, mark, dep_id, dep.name)
                table.insert(lines, line)

                local is_cursor = j == DepUI.cursor_dep
                local is_selected = vim.tbl_contains(DepUI.deps, dep_id)

                local vis = vim.api.nvim_get_hl(0, { name = "Visual" }) or {}
                local str = vim.api.nvim_get_hl(0, { name = "String" }) or {}
                vim.api.nvim_set_hl(0, "SpringDepVisualString", {
                    bg = vis.bg,
                    fg = str.fg or vis.fg,
                })

                if is_cursor and is_selected then
                    table.insert(highlights, { #lines, 0, -1, "SpringDepVisualString" })
                elseif is_cursor then
                    table.insert(highlights, { #lines, 0, -1, "Visual" })
                elseif is_selected then
                    table.insert(highlights, { #lines, 0, -1, "String" })
                else
                    table.insert(highlights, { #lines, 0, -1, "Normal" })
                end
            end
        end
    end

    vim.bo[DepUI.buf].modifiable = true
    vim.api.nvim_buf_set_lines(DepUI.buf, 0, -1, false, lines)
    vim.bo[DepUI.buf].modifiable = false

    -- Apply highlights
    local ns = vim.api.nvim_create_namespace("SpringBootDepUI")
    vim.api.nvim_buf_clear_namespace(DepUI.buf, ns, 0, -1)
    for _, h in ipairs(highlights) do
        vim.api.nvim_buf_set_extmark(DepUI.buf, ns, h[1] - 1, h[2], {
            end_col = h[3] == -1 and #lines[h[1]] or h[3],
            hl_group = h[4],
        })
    end
end

-------------------------------------------------
-- Search and Filter
-------------------------------------------------
local function filter_and_update()
    if DepUI.search_term == "" then
        -- If search is cleared, restore the original full list
        DepUI.categories = DepUI.original_categories
        DepUI.category_names = DepUI.original_category_names
    else
        local new_categories = {}
        local new_category_names = {}
        local term = DepUI.search_term:lower()

        for _, cat_name in ipairs(DepUI.original_category_names) do
            local matching_deps = {}
            for _, dep in ipairs(DepUI.original_categories[cat_name]) do
                -- Search in dependency id, name, and description
                if
                    dep.id:lower():find(term, 1, true)
                    or dep.name:lower():find(term, 1, true)
                    or (dep.description and dep.description:lower():find(term, 1, true))
                then
                    table.insert(matching_deps, dep)
                end
            end

            -- If any dependencies in this category matched, add it to the results
            if #matching_deps > 0 then
                table.insert(new_category_names, cat_name)
                new_categories[cat_name] = matching_deps
            end
        end
        DepUI.categories = new_categories
        DepUI.category_names = new_category_names
    end

    -- Reset cursor position after filtering
    DepUI.active_category = 1
    DepUI.cursor_dep = 1
    render_ui()
end

-------------------------------------------------
-- Dependency UI Actions
-------------------------------------------------
local function toggle_dep()
    -- This function works without changes because it reads from the (potentially filtered)
    -- DepUI.categories and DepUI.category_names, which is what we want.
    if not DepUI.category_names[DepUI.active_category] then
        return
    end
    local cat = DepUI.category_names[DepUI.active_category]
    local dep = DepUI.categories[cat][DepUI.cursor_dep]
    if not dep then
        return
    end

    local dep_id = dep.id
    if vim.tbl_contains(DepUI.deps, dep_id) then
        DepUI.deps = vim.tbl_filter(function(x)
            return x ~= dep_id
        end, DepUI.deps)
        U.notify("❌ Removed: " .. dep_id, "warn")
    else
        table.insert(DepUI.deps, dep_id)
        U.notify("✅ Added: " .. dep_id, "info")
    end
    render_ui()
end

local function move_cursor(dir)
    if not DepUI.category_names[DepUI.active_category] then
        return
    end
    local deps = DepUI.categories[DepUI.category_names[DepUI.active_category]]
    if not deps then
        return
    end
    if dir == "up" and DepUI.cursor_dep > 1 then
        DepUI.cursor_dep = DepUI.cursor_dep - 1
    elseif dir == "down" and DepUI.cursor_dep < #deps then
        DepUI.cursor_dep = DepUI.cursor_dep + 1
    end
    render_ui()
end

local function switch_category(dir)
    local max = #DepUI.category_names
    if max == 0 then
        return
    end
    if dir == "next" and DepUI.active_category < max then
        DepUI.active_category = DepUI.active_category + 1
    elseif dir == "prev" and DepUI.active_category > 1 then
        DepUI.active_category = DepUI.active_category - 1
    end
    DepUI.cursor_dep = 1
    render_ui()
end

local function close_ui(finish)
    if DepUI.win then
        vim.api.nvim_win_close(DepUI.win, true)
        DepUI.win, DepUI.buf = nil, nil
    end
    if finish and DepUI.callback then
        DepUI.callback(table.concat(DepUI.deps, ","))
    end
end

local function start_search()
    local query = vim.fn.input("Search: ", DepUI.search_term)
    if query == nil then -- User pressed <Esc>
        return
    end
    DepUI.search_term = query
    filter_and_update()
end

-------------------------------------------------
-- Open Dependency Selector
-------------------------------------------------
local function open_dep_ui(dep_metadata, callback)
    -- Reset state
    DepUI.deps, DepUI.search_term = {}, ""
    DepUI.original_categories, DepUI.original_category_names = {}, {}

    -- Store the full, unfiltered list
    for _, group in ipairs(dep_metadata.values) do
        table.insert(DepUI.original_category_names, group.name)
        DepUI.original_categories[group.name] = group.values
    end

    -- The active list starts as the full list
    DepUI.categories = DepUI.original_categories
    DepUI.category_names = DepUI.original_category_names

    DepUI.active_category, DepUI.cursor_dep, DepUI.callback = 1, 1, callback

    DepUI.buf = vim.api.nvim_create_buf(false, true)
    local width, height = math.floor(vim.o.columns * 0.8), math.floor(vim.o.lines * 0.8)
    local row, col = math.floor((vim.o.lines - height) / 2), math.floor((vim.o.columns - width) / 2)

    DepUI.win = vim.api.nvim_open_win(DepUI.buf, true, {
        relative = "editor",
        width = width,
        height = height,
        row = row,
        col = col,
        style = "minimal",
        border = "rounded",
    })

    local bo = vim.bo[DepUI.buf]
    bo.buftype = "nofile"
    bo.bufhidden = "wipe"
    bo.modifiable = false

    render_ui()

    local keymaps = {
        i = toggle_dep,
        ["<CR>"] = toggle_dep,
        j = function()
            move_cursor("down")
        end,
        k = function()
            move_cursor("up")
        end,
        l = function()
            switch_category("next")
        end,
        h = function()
            switch_category("prev")
        end,
        ["<Down>"] = function()
            move_cursor("down")
        end,
        ["<Up>"] = function()
            move_cursor("up")
        end,
        ["<Right>"] = function()
            switch_category("next")
        end,
        ["<Left>"] = function()
            switch_category("prev")
        end,
        q = function()
            close_ui(false)
        end,
        ["<Esc>"] = function()
            close_ui(false)
        end,
        d = function()
            close_ui(true)
        end,
        ["/"] = start_search,
    }

    local opts = { noremap = true, silent = true, buffer = DepUI.buf }
    for k, fn in pairs(keymaps) do
        vim.keymap.set("n", k, fn, opts)
    end
end

-------------------------------------------------
-- Download & Extract Spring Boot Project
-------------------------------------------------
local function download_project(url, target_dir)
    local zip_path = target_dir .. "/starter.zip"
    vim.fn.system({ "curl", "-L", "-o", zip_path, url })
    if vim.v.shell_error ~= 0 then
        return U.notify("❌ Failed to download starter.zip", "error")
    end
    vim.fn.system({ "unzip", "-o", zip_path, "-d", target_dir })
    if vim.v.shell_error ~= 0 then
        return U.notify("❌ Failed to unzip starter.zip", "error")
    end
    vim.fn.delete(zip_path)
    return true
end

-------------------------------------------------
-- Main Command
-------------------------------------------------
local function springboot_new_project()
    -------------------------
    -- Step 0: Check Requirements
    -------------------------
    if not U.check_requirements({ "curl", "unzip" }) then
        return
    end

    -------------------------
    -- Step 1: Fetch Metadata from start.spring.io
    -------------------------
    U.notify("Fetching metadata from start.spring.io...", "info")
    local response = vim.fn.systemlist({ "curl", "-s", "https://start.spring.io/metadata/client" })
    if vim.v.shell_error ~= 0 then
        return U.notify("Failed to fetch metadata.", "error")
    end

    local ok, metadata = pcall(vim.fn.json_decode, table.concat(response, ""))
    if not ok then
        return U.notify("Failed to parse metadata.", "error")
    end

    local function get_options(data)
        local options = {}
        if data and data.values then
            for _, value in ipairs(data.values) do
                table.insert(options, value.id)
            end
        end
        return options
    end

    -------------------------
    -- Step 2: Project Directory
    -------------------------
    local project_dir = U.input("Enter parent directory for project: ", vim.fn.getcwd())
    if not project_dir or not U.prepare_dir(project_dir) or not U.chdir(vim.fn.fnamemodify(project_dir, ":h")) then
        return
    end

    -------------------------
    -- Step 3: Project Parameters
    -------------------------
    local build_choices, languages = { "maven", "gradle" }, get_options(metadata.language)
    local java_versions, packagings = get_options(metadata.javaVersion), get_options(metadata.packaging)
    local boot_versions = get_options(metadata.bootVersion)

    local group_id = U.input("Enter Group ID: ", "com.example") or "com.example"
    local artifact_id = U.input("Enter Artifact ID: ", U.basename(project_dir)) or "demo"
    local name = U.input("Enter project name: ", artifact_id) or artifact_id
    local package_name = U.input("Enter package name: ", group_id .. "." .. artifact_id:gsub("%-", ""))
        or (group_id .. "." .. artifact_id)
    local description = U.input("Enter project description: ", "Demo project for Spring Boot") or "Demo project"

    local build_choice = build_choices[U.select_choice("Build type: ", build_choices, "maven")]
    local language = languages[U.select_choice("Language: ", languages, metadata.language.default)]
    local java_version = java_versions[U.select_choice("Java version: ", java_versions, metadata.javaVersion.default)]
    local packaging = packagings[U.select_choice("Packaging: ", packagings, metadata.packaging.default)]
    local boot_version = parse_boot_version(
        boot_versions[U.select_choice("Spring Boot version: ", boot_versions, metadata.bootVersion.default)]
    )

    open_dep_ui(metadata.dependencies, function(dependencies)
        if dependencies == "" then
            U.notify("No dependencies selected, defaulting to web.", "warn")
            dependencies = "web"
        end

        -------------------------
        -- Step 4: Build URL
        -------------------------
        local type_flag = (build_choice == "gradle") and "gradle-project" or "maven-project"
        local url = string.format(
            "https://start.spring.io/starter.zip?type=%s&language=%s&bootVersion=%s&baseDir=%s&groupId=%s&artifactId=%s&name=%s&description=%s&packageName=%s&packaging=%s&javaVersion=%s&dependencies=%s",
            urlencode(type_flag),
            urlencode(language),
            urlencode(boot_version),
            urlencode(artifact_id),
            urlencode(group_id),
            urlencode(artifact_id),
            urlencode(name),
            urlencode(description),
            urlencode(package_name),
            urlencode(packaging),
            urlencode(java_version),
            urlencode(dependencies)
        )

        U.notify("Downloading project...\n" .. url, "info")
        if not download_project(url, vim.fn.fnamemodify(project_dir, ":h")) then
            return
        end

        -----------------------
        -- Step 5: Open Project in Neovim
        -----------------------
        if not U.chdir(project_dir) then
            return U.notify("Failed to change directory", "error")
        end
        if vim.g.loaded_nvim_tree then
            vim.cmd("NvimTreeRefresh")
        end

        local main_class = capitalize(name:gsub("%-", "")) .. "Application." .. language
        local main_class_path = string.format("src/main/java/%s/%s", package_name:gsub("%.", "/"), main_class)

        if vim.fn.filereadable(main_class_path) == 1 then
            vim.cmd(":edit " .. main_class_path)
        else
            U.notify("Main class not found.", "warn")
        end

        U.notify("✅ Spring Boot project created successfully!", "info")
    end)
end

vim.api.nvim_create_user_command("NewSpringBootProject", springboot_new_project, {})
