local U = require("java_project.utils")

---@diagnostic disable: undefined-field, param-type-mismatch
local function gradle_new_project()
    -------------------------
    -- Step 0: Check Requirements
    -------------------------
    if not U.check_requirements({ "gradle", "java" }) then
        return
    end

    -------------------------
    -- Step 1: Project Directory
    -------------------------
    local project_dir, canceled = U.input("Enter project directory: ", vim.fn.getcwd())
    if canceled or not project_dir then
        return
    end

    -- Check if the project directory already exists
    if not U.prepare_dir(project_dir) then
        return
    end

    -- Change into the project directory. Gradle works from *within* the project root.
    if not U.chdir(project_dir) then
        return
    end

    -------------------------
    -- Step 2: Gradle Parameters
    -------------------------
    local project_types = { "java-application", "java-gradle-plugin", "java-library" }
    local script_dsls = { "groovy", "kotlin" }
    local test_frameworks = { "junit-jupiter", "spock", "junit" }

    local project_type, canceled_type = U.select_choice("Project type: ", project_types, "java-application")
    if canceled_type then
        return
    end

    local script_dsl, canceled_dsl = U.select_choice("Script DSL: ", script_dsls, "groovy")
    if canceled_dsl then
        return
    end

    -- Test Framework
    local test_framework, canceled_test = U.select_choice("Testing framework: ", test_frameworks, "junit-jupiter")
    if canceled_test then
        return
    end

    -- Package Name
    local package_name, canceled_package = U.input("Enter package name: ", "com.example")
    if canceled_package then
        return
    end

    -- Project Name (defaults to the directory name)
    local project_name = U.basename(project_dir)

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

    U.notify("Running: " .. gradle_cmd, "info")

    local output = vim.fn.systemlist(gradle_cmd)
    if vim.v.shell_error ~= 0 then
        U.notify("Failed to create Gradle project:\n" .. table.concat(output, "\n"), "error")
        return
    end

    -------------------------
    -- Step 4: Open Project in Neovim
    -------------------------
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
            U.notify("Opening " .. main_class_path, "info")
        else
            U.notify("Main class not found: " .. main_class_path, "warn")
        end
    end

    U.notify("Gradle project created successfully!", "info")
end

-- Create the Neovim user command
vim.api.nvim_create_user_command("NewGradleProject", gradle_new_project, {})
