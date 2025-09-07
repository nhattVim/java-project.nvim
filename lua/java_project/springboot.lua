---@diagnostic disable: undefined-field, param-type-mismatch, need-check-nil
local function springboot_new_project()
    -------------------------
    -- Utility Functions
    -------------------------
    local function notify_msg(message, level)
        local ok, notify = pcall(require, "notify")
        if ok then
            notify(message, level, { timeout = 4000 })
        else
            print("[" .. (level or "info") .. "] " .. message)
        end
    end

    local function get_input(prompt, default)
        vim.fn.inputsave()
        local result = vim.fn.input(prompt, default)
        vim.fn.inputrestore()
        if result == "" then
            notify_msg("Input canceled.", "info")
            return nil, true
        end
        return result, false
    end

    local function get_last_dir(path)
        local uname = vim.loop.os_uname().sysname
        if uname == "Windows_NT" then
            return path:match("([^\\]+)$")
        else
            return path:match("([^/]+)$")
        end
    end

    -- Helper to get user input with a list of choices
    local function get_choice_input(prompt, choices, default)
        local prompt_str = string.format("%s (%s): ", prompt, table.concat(choices, "/"))
        local user_input, canceled = get_input(prompt_str, default)
        if canceled then
            return nil, true
        end

        for _, choice in ipairs(choices) do
            if choice == user_input then
                return user_input, false
            end
        end

        notify_msg("Invalid choice. Please select one of: " .. table.concat(choices, ", "), "error")
        return nil, true
    end

    -- Helper to capitalize a string
    local function capitalize(str)
        return str:sub(1, 1):upper() .. str:sub(2)
    end

    -------------------------
    -- Step 0: Fetch Metadata from start.spring.io
    -------------------------
    notify_msg("Fetching metadata from start.spring.io...", "info")
    local response = vim.fn.systemlist({ "curl", "-s", "https://start.spring.io/metadata/client" })
    if vim.v.shell_error ~= 0 then
        notify_msg("Failed to fetch metadata from Spring Initializr.", "error")
        return
    end

    local ok, metadata = pcall(vim.fn.json_decode, table.concat(response, ""))
    if not ok then
        notify_msg("Failed to parse metadata: " .. tostring(metadata), "error")
        return
    end

    -- Helper to extract options from metadata
    local function get_options(data)
        local options = {}
        if data and data.values then
            for _, value in ipairs(data.values) do
                table.insert(options, value.id)
            end
        end
        return options
    end

    local build_types = { "maven", "gradle-project" }
    local languages = get_options(metadata.language)
    local java_versions = get_options(metadata.javaVersion)
    local boot_versions = get_options(metadata.bootVersion)
    local packagings = get_options(metadata.packaging)

    -------------------------
    -- Step 1: Project Directory
    -------------------------
    local project_dir, canceled = get_input("Enter parent directory for project: ", vim.fn.getcwd())
    if canceled or not project_dir then
        return
    end

    -- Create the parent directory if it doesn't exist
    if vim.fn.isdirectory(project_dir) == 0 then
        if vim.fn.mkdir(project_dir, "p") == 0 then
            notify_msg("Failed to create parent directory: " .. project_dir, "error")
            return
        end
    end

    -- Change to the parent directory
    local cd_ok, err = pcall(vim.cmd, "cd " .. project_dir)
    if not cd_ok then
        notify_msg("Error changing to parent directory: " .. err, "error")
        return
    end
    notify_msg("Working directory set to: " .. project_dir, "info")

    -------------------------
    -- Step 2: Project Parameters
    -------------------------
    -- Project Coordinates
    local group_id, canceled_group = get_input("Enter Group ID: ", "com.example")
    if canceled_group then
        return
    end

    local default_artifact = get_last_dir(project_dir)
    local artifact_id, canceled_artifact = get_input("Enter Artifact ID: ", default_artifact)
    if canceled_artifact then
        return
    end

    local name, canceled_name = get_input("Enter project name: ", artifact_id)
    if canceled_name then
        return
    end

    local default_package = group_id .. "." .. artifact_id:gsub("%-", "")
    local package_name, canceled_package = get_input("Enter package name: ", default_package)
    if canceled_package then
        return
    end

    local description, canceled_desc = get_input("Enter project description: ", "Demo project for Spring Boot")
    if canceled_desc then
        return
    end

    -- Project Options
    local build_type, canceled_build = get_choice_input("Build type", build_types, "maven")
    if canceled_build then
        return
    end

    local language, canceled_lang = get_choice_input("Language", languages, metadata.language.default)
    if canceled_lang then
        return
    end

    local java_version, canceled_java = get_choice_input("Java version", java_versions, metadata.javaVersion.default)
    if canceled_java then
        return
    end

    local boot_version, canceled_boot =
        get_choice_input("Spring Boot version", boot_versions, metadata.bootVersion.default)
    if canceled_boot then
        return
    end

    local packaging, canceled_pack = get_choice_input("Packaging", packagings, metadata.packaging.default)
    if canceled_pack then
        return
    end

    local dependencies, canceled_deps = get_input("Enter dependencies (comma-separated):", "web,lombok,data-jpa,h2")
    if canceled_deps then
        return
    end

    -------------------------
    -- Step 3: Run Spring CLI Command
    -------------------------
    local spring_cli_cmd = string.format(
        'spring init --boot-version=%s --java-version=%s --dependencies=%s --groupId=%s --artifactId=%s --name=%s --package-name=%s --description="%s" --language=%s --build=%s --packaging=%s %s',
        boot_version,
        java_version,
        dependencies,
        group_id,
        artifact_id,
        name,
        package_name,
        description,
        language,
        build_type,
        packaging,
        artifact_id
    )

    notify_msg("Running command, this may take a moment...", "info")
    local output = vim.fn.systemlist(spring_cli_cmd)
    if vim.v.shell_error ~= 0 then
        notify_msg("Failed to create Spring Boot project:\n" .. table.concat(output, "\n"), "error")
        return
    end

    -------------------------
    -- Step 4: Open Project in Neovim
    -------------------------
    local final_project_path = project_dir .. "/" .. artifact_id

    -- Change to the final project directory
    local final_cd_ok, final_err = pcall(vim.cmd, "cd " .. final_project_path)
    if not final_cd_ok then
        notify_msg("Project created, but failed to open it: " .. final_err, "error")
        return
    end

    notify_msg("Spring Boot project created successfully!", "info")

    if vim.g.loaded_nvim_tree then
        vim.cmd("NvimTreeRefresh")
    end

    -- Open the main class
    local pth = package_name:gsub("%.", "/")
    local app_name = capitalize(name:gsub("%-", "")) .. "Application." .. language
    local main_class_path = string.format("src/main/java/%s/%s", pth, app_name)

    if vim.fn.filereadable(main_class_path) == 1 then
        vim.cmd(":edit " .. main_class_path)
    else
        notify_msg("Main class not found at: " .. main_class_path, "warn")
    end
end

vim.api.nvim_create_user_command("NewSpringBootProject", springboot_new_project, {})
