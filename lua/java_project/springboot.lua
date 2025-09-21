local U = require("java_project.utils")

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

local function springboot_new_project()
    -------------------------
    -- Step 0: Check Requirements
    -------------------------
    if not U.check_requirements({ "curl", "spring" }) then
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

    local group_id, group_canceled = U.input("Enter Group ID: ", "com.example")
    if group_canceled then
        return
    end

    local default_artifact = U.basename(project_dir)
    local artifact_id, artifact_canceled = U.input("Enter Artifact ID: ", default_artifact)
    if artifact_canceled or artifact_id == nil then
        return
    end

    local name, name_canceled = U.input("Enter project name: ", artifact_id)
    if name_canceled or name == nil then
        return
    end

    local default_package = group_id .. "." .. artifact_id:gsub("%-", "")
    local package_name, package_canceled = U.input("Enter package name: ", default_package)
    if package_canceled or package_name == nil then
        return
    end

    local description, desc_canceled = U.input("Enter project description: ", "Demo project for Spring Boot")
    if desc_canceled then
        return
    end

    local build_idx, build_canceled = U.select_choice("Build type: ", build_choices, "maven")
    if build_canceled then
        return
    end
    local build_choice = build_choices[build_idx]

    local lang_idx, lang_canceled = U.select_choice("Language: ", languages, metadata.language.default)
    if lang_canceled then
        return
    end
    local language = languages[lang_idx]

    local java_idx, java_canceled = U.select_choice("Java version: ", java_versions, metadata.javaVersion.default)
    if java_canceled then
        return
    end
    local java_version = java_versions[java_idx]

    local pack_idx, pack_canceled = U.select_choice("Packaging: ", packagings, metadata.packaging.default)
    if pack_canceled then
        return
    end
    local packaging = packagings[pack_idx]

    local dependencies = select_dependencies(metadata.dependencies)
    if dependencies == "" then
        U.notify("No dependencies selected.", "warn")
        dependencies = "web"
    end

    -------------------------
    -- Step 4: Run Spring CLI Command
    -------------------------
    local build_flag, type_flag
    if build_choice == "gradle" then
        build_flag = "gradle"
        type_flag = "gradle-project"
    else
        build_flag = "maven"
        type_flag = "maven-project"
    end

    local spring_cli_cmd = string.format(
        'spring init --java-version=%s --dependencies=%s --groupId=%s --artifactId=%s --name=%s --package-name=%s --description="%s" --language=%s --build=%s --type=%s --packaging=%s %s',
        java_version,
        dependencies,
        group_id,
        artifact_id,
        name,
        package_name,
        description,
        language,
        build_flag,
        type_flag,
        packaging,
        artifact_id
    )

    U.notify("Running command, this may take a moment...\n" .. spring_cli_cmd, "info")

    local output = vim.fn.systemlist(spring_cli_cmd)
    local full_output = table.concat(output, "\n")
    if vim.v.shell_error ~= 0 or not string.find(full_output, "Project extracted to") then
        U.notify("Failed to create Spring Boot project:\n" .. full_output, "error")
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

    local function capitalize(str)
        if str == nil or #str == 0 then
            return str
        end
        return str:sub(1, 1):upper() .. str:sub(2)
    end

    local pth = package_name:gsub("%.", "/")
    local app_name = capitalize(name:gsub("%-", "")) .. "Application." .. language
    local main_class_path = string.format("src/main/java/%s/%s", pth, app_name)

    if vim.fn.filereadable(main_class_path) == 1 then
        vim.cmd(":edit " .. main_class_path)
    else
        U.notify("Main class not found at: " .. main_class_path, "warn")
    end

    U.notify("Spring Boot project created successfully!", "info")
end

vim.api.nvim_create_user_command("NewSpringBootProject", springboot_new_project, {})
