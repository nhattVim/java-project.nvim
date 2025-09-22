local U = require("java_project.utils")

-------------------------------------------------
-- Helper: URL Encode
-------------------------------------------------
local function urlencode(str)
    if str == nil then
        return ""
    end
    str = str:gsub("\n", "\r\n")
    str = str:gsub("([^%w%-_%.~])", function(c)
        return string.format("%%%02X", string.byte(c))
    end)
    return str
end

-------------------------------------------------
-- Helper: Capitalize
-------------------------------------------------
local function capitalize(str)
    return (str and #str > 0) and (str:sub(1, 1):upper() .. str:sub(2)) or str
end

-------------------------------------------------
-- Helper: Parse Boot Version
-------------------------------------------------
local function parse_boot_version(ver)
    -- 1. if .RELEASE -> remove .RELEASE
    if ver:match("%.RELEASE$") then
        return ver:gsub("%.RELEASE$", "")
    end

    -- 2. if .BUILD%-SNAPSHOT -> change to -SNAPSHOT
    if ver:match("%.BUILD%-SNAPSHOT$") then
        return ver:gsub("%.BUILD%-SNAPSHOT$", "-SNAPSHOT")
    end

    -- 3. if .M%d+ -> change to -M%d+
    if ver:match("%.M%d+$") then
        return ver:gsub("%.(M%d+)$", "-%1")
    end

    -- 4. else -> do nothing
    return ver
end

-------------------------------------------------
-- Dependency Selection
-------------------------------------------------
local function select_dependencies(dep_metadata)
    local categories = {}
    local category_map = {}

    for _, group in ipairs(dep_metadata.values) do
        table.insert(categories, group.name)
        category_map[group.name] = group.values
    end

    local selected_deps = {}

    while true do
        -- show selected
        local msg = (#selected_deps > 0) and ("Selected: " .. table.concat(selected_deps, ", "))
            or "No dependencies selected yet."
        U.notify(msg, "info")

        -- choose category
        local cat_idx, cat_cancel = U.select_choice("Select category (ESC to finish):", categories)
        if cat_cancel then
            break
        end
        local category = categories[cat_idx]

        -- deps in group
        local deps = {}
        for _, dep in ipairs(category_map[category]) do
            table.insert(deps, dep.id .. " - " .. dep.name)
        end

        local dep_idx, dep_cancel = U.select_choice("Toggle dependency (ESC to skip):", deps)
        if not dep_cancel then
            local dep_id = category_map[category][dep_idx].id
            if vim.tbl_contains(selected_deps, dep_id) then
                -- remove
                selected_deps = vim.tbl_filter(function(x)
                    return x ~= dep_id
                end, selected_deps)
                U.notify("❌ Removed: " .. dep_id, "warn")
            else
                -- add
                table.insert(selected_deps, dep_id)
                U.notify("✅ Added: " .. dep_id, "info")
            end
        end
    end

    return table.concat(selected_deps, ",")
end

-------------------------------------------------
-- Download & Extract Spring Boot Project
-------------------------------------------------
local function download_project(url, target_dir)
    local zip_path = target_dir .. "/starter.zip"

    vim.fn.system({ "curl", "-L", "-o", zip_path, url })
    if vim.v.shell_error ~= 0 then
        U.notify("❌ Failed to download starter.zip", "error")
        return false
    end

    vim.fn.system({ "unzip", "-o", zip_path, "-d", target_dir })
    if vim.v.shell_error ~= 0 then
        U.notify("❌ Failed to unzip starter.zip", "error")
        return false
    end

    vim.fn.delete(zip_path)
    return true
end

-------------------------------------------------
-- Main Function
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
        U.notify("Failed to fetch metadata from Spring Initializr.", "error")
        return
    end

    local ok, metadata = pcall(vim.fn.json_decode, table.concat(response, ""))
    if not ok then
        U.notify("Failed to parse metadata: " .. tostring(metadata), "error")
        return
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
    local project_dir, dir_canceled = U.input("Enter parent directory for project: ", vim.fn.getcwd())
    if dir_canceled or not project_dir then
        return
    end

    if not U.prepare_dir(project_dir) then
        return
    end

    if not U.chdir(vim.fn.fnamemodify(project_dir, ":h")) then
        return
    end

    -------------------------
    -- Step 3: Project Parameters
    -------------------------
    local build_choices = { "maven", "gradle" }
    local languages = get_options(metadata.language)
    local java_versions = get_options(metadata.javaVersion)
    local packagings = get_options(metadata.packaging)
    local boot_versions = get_options(metadata.bootVersion)

    local group_id = U.input("Enter Group ID: ", "com.example")
    if not group_id then
        return
    end

    local default_artifact = U.basename(project_dir)
    local artifact_id = U.input("Enter Artifact ID: ", default_artifact)
    if not artifact_id then
        return
    end

    local name = U.input("Enter project name: ", artifact_id)
    if not name then
        return
    end

    local default_package = group_id .. "." .. artifact_id:gsub("%-", "")
    local package_name = U.input("Enter package name: ", default_package)
    if not package_name then
        return
    end

    local description = U.input("Enter project description: ", "Demo project for Spring Boot")
    if not description then
        return
    end

    local build_idx = U.select_choice("Build type: ", build_choices, "maven")
    local build_choice = build_choices[build_idx]

    local lang_idx = U.select_choice("Language: ", languages, metadata.language.default)
    local language = languages[lang_idx]

    local java_idx = U.select_choice("Java version: ", java_versions, metadata.javaVersion.default)
    local java_version = java_versions[java_idx]

    local pack_idx = U.select_choice("Packaging: ", packagings, metadata.packaging.default)
    local packaging = packagings[pack_idx]

    local boot_idx = U.select_choice("Spring Boot version: ", boot_versions, metadata.bootVersion.default)
    local boot_version = parse_boot_version(boot_versions[boot_idx])

    local dependencies = select_dependencies(metadata.dependencies)
    if dependencies == "" then
        U.notify("No dependencies selected.", "warn")
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
        U.notify("Failed to change directory to: " .. project_dir, "error")
        return
    end

    if vim.g.loaded_nvim_tree then
        vim.cmd("NvimTreeRefresh")
    end

    local pth = package_name:gsub("%.", "/")
    local app_name = capitalize(name:gsub("%-", "")) .. "Application." .. language
    local main_class_path = string.format("src/main/java/%s/%s", pth, app_name)

    if vim.fn.filereadable(main_class_path) == 1 then
        vim.cmd(":edit " .. main_class_path)
    else
        U.notify("Main class not found at: " .. main_class_path, "warn")
    end

    U.notify("✅ Spring Boot project created successfully!", "info")
end

vim.api.nvim_create_user_command("NewSpringBootProject", springboot_new_project, {})
