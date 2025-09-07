---@diagnostic disable: undefined-field, param-type-mismatch
local function gradle_new_project()
    -------------------------
    -- Utility Functions
    -------------------------
    local function notify_msg(message, level)
        local ok, notify = pcall(require, "notify")
        if ok then
            notify(message, level, { timeout = 3000 })
        else
            -- Fallback to print for users without nvim-notify
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
        -- This helper gets the final component of a path, cross-platform
        local uname = vim.loop.os_uname().sysname
        if uname == "Windows_NT" then
            return path:match("([^\\]+)$")
        else
            return path:match("([^/]+)$")
        end
    end

    -------------------------
    -- Step 1: Project Directory
    -------------------------
    local project_dir, canceled = get_input("Enter project directory: ", vim.fn.getcwd())
    if canceled or not project_dir then
        return
    end

    -- Create the directory if it doesn't exist
    if vim.fn.isdirectory(project_dir) == 0 then
        if vim.fn.mkdir(project_dir, "p") == 0 then
            notify_msg("Failed to create project directory: " .. project_dir, "error")
            return
        end
        notify_msg("Created directory: " .. project_dir, "info")
    end

    -- Change into the project directory. Gradle works from *within* the project root.
    local ok, err = pcall(vim.cmd, "cd " .. project_dir)
    if not ok then
        notify_msg("Error changing directory to " .. project_dir .. ": " .. err, "error")
        return
    end
    notify_msg("Changed directory to: " .. project_dir, "info")

    -------------------------
    -- Step 2: Gradle Parameters
    -------------------------
    -- Project Type
    local project_type, canceled_type =
        get_input("Project type (java-application, java-library, etc.): ", "java-application")
    if canceled_type then
        return
    end

    -- Script DSL
    local script_dsl, canceled_dsl = get_input("Script DSL (groovy, kotlin): ", "groovy")
    if canceled_dsl then
        return
    end

    -- Test Framework
    local test_framework, canceled_test = get_input("Testing framework (junit-jupiter, spock, etc.): ", "junit-jupiter")
    if canceled_test then
        return
    end

    -- Package Name
    local package_name, canceled_package = get_input("Enter package name: ", "com.example")
    if canceled_package then
        return
    end

    -- Project Name (defaults to the directory name)
    local project_name = get_last_dir(project_dir)

    -------------------------
    -- Step 3: Run Gradle Command
    -------------------------
    -- 'echo no' pipes "no" to the interactive prompt, preventing it from hanging.
    local gradle_cmd = string.format(
        "echo no | gradle init --type %s --dsl %s --test-framework %s --package %s --project-name %s --no-daemon",
        project_type,
        script_dsl,
        test_framework,
        package_name,
        project_name
    )

    notify_msg("Running: " .. gradle_cmd, "info")

    -- Using systemlist to capture output for better error reporting
    local output = vim.fn.systemlist(gradle_cmd)
    if vim.v.shell_error ~= 0 then
        notify_msg("Failed to create Gradle project:\n" .. table.concat(output, "\n"), "error")
        return
    end

    -------------------------
    -- Step 4: Open Project in Neovim
    -------------------------
    notify_msg("Gradle project created successfully!", "info")

    -- Refresh file explorer to show new files
    if vim.g.loaded_nvim_tree then
        vim.cmd("NvimTreeRefresh")
    end

    -- Try to open the main App.java file if it was created
    if package_name and package_name ~= "" and project_type == "java-application" then
        local java_path = package_name:gsub("%.", "/")
        local main_class_path = string.format("app/src/main/java/%s/App.java", java_path)

        if vim.fn.filereadable(main_class_path) == 1 then
            vim.cmd(":edit " .. main_class_path)
            notify_msg("Opening " .. main_class_path, "info")
        else
            notify_msg("Main class not found: " .. main_class_path, "warn")
        end
    end
end

-- Create the Neovim user command
vim.api.nvim_create_user_command("NewGradleProject", gradle_new_project, {})
