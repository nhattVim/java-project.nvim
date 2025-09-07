---@diagnostic disable: undefined-field
local function mvn_new_project()
    -------------------------
    -- Utility Functions
    -------------------------
    local function notify_msg(message, level)
        local ok, notify = pcall(require, "notify")
        if ok then
            notify(message, level, { timeout = 3000 })
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

    -------------------------
    -- Step 1: Project Directory
    -------------------------
    local project_dir, canceled = get_input("Enter project directory: ", vim.fn.getcwd())
    if canceled or not project_dir then
        return
    end

    if vim.fn.isdirectory(project_dir) == 0 and vim.fn.mkdir(project_dir, "p") == 0 then
        notify_msg("Failed to create project directory: " .. project_dir, "error")
        return
    end

    local parent_dir = vim.fn.fnamemodify(project_dir, ":h")
    local ok1, err = pcall(vim.fn.chdir, parent_dir)
    if not ok1 then
        notify_msg("Error changing directory: " .. err, "error")
        return
    end
    notify_msg("Changed directory to: " .. project_dir, "info")

    -------------------------
    -- Step 2: Maven Coordinates
    -------------------------
    local group_id, canceled_group = get_input("Enter groupId: ", "com.example")
    if canceled_group then
        return
    end
    local artifact_id = get_last_dir(project_dir)

    -------------------------
    -- Step 3: Archetype Selection
    -------------------------
    local POPULAR_ARCHETYPES = {
        "maven-archetype-quickstart",
        "maven-archetype-webapp",
        "maven-archetype-simple",
    }
    local CACHE_FILE = vim.fn.stdpath("cache") .. "/maven_archetypes.json"

    -- Cache handling
    local function load_cache()
        local ok, content = pcall(vim.fn.readfile, CACHE_FILE)
        if ok and content and #content > 0 then
            local data = vim.fn.json_decode(table.concat(content, "\n"))
            if data and data.timestamp and (os.time() - data.timestamp) < 86400 then
                return data.archetypes
            end
        end
        return nil
    end

    local function save_cache(archetypes)
        local data = { timestamp = os.time(), archetypes = archetypes }
        local ok, json_str = pcall(vim.fn.json_encode, data)
        if ok and json_str then
            vim.fn.mkdir(vim.fn.fnamemodify(CACHE_FILE, ":h"), "p")
            vim.fn.writefile({ json_str }, CACHE_FILE)
        end
    end

    -- Fetch latest versions from Maven Central
    local function get_archetype_versions(artifact)
        local url = "https://search.maven.org/solrsearch/select?q=a:" .. artifact .. "&core=gav&rows=10&wt=json"
        local cmd = 'curl -s --max-time 10 "' .. url .. '"'
        local output = vim.fn.system(cmd)
        local ok, data = pcall(vim.fn.json_decode, output)
        local versions = {}
        if ok and data and data.response and data.response.docs then
            for _, doc in ipairs(data.response.docs) do
                if doc.v then
                    table.insert(versions, doc.v)
                end
            end
        end
        table.sort(versions, function(a, b)
            return a > b
        end)
        local latest = {}
        for i = 1, math.min(5, #versions) do
            table.insert(latest, versions[i])
        end
        return latest
    end

    local function get_available_archetypes()
        local cached = load_cache()
        if cached then
            notify_msg("Loaded archetypes from cache.", "info")
            return cached
        end
        notify_msg("Fetching latest archetypes from Maven Central...", "info")
        local archetypes = {}
        for _, artifact in ipairs(POPULAR_ARCHETYPES) do
            local versions = get_archetype_versions(artifact)
            if #versions > 0 then
                for _, v in ipairs(versions) do
                    table.insert(archetypes, { artifact = artifact, version = v })
                end
            end
        end
        if #archetypes == 0 then
            table.insert(archetypes, { artifact = "maven-archetype-quickstart", version = "1.5" })
            notify_msg("Could not fetch archetypes, using default.", "warn")
        else
            save_cache(archetypes)
        end
        return archetypes
    end

    local function choose_archetype(archetypes)
        local unique = {}
        local seen = {}
        for _, arch in ipairs(archetypes) do
            if not seen[arch.artifact] then
                table.insert(unique, arch.artifact)
                seen[arch.artifact] = true
            end
        end
        local choices = {}
        for i, a in ipairs(unique) do
            table.insert(choices, string.format("%d: %s", i, a))
        end
        local sel = vim.fn.input(table.concat(choices, "\n") .. "\nSelect archetype: ", "1")
        local idx = tonumber(sel)
        if not idx or idx < 1 or idx > #unique then
            notify_msg("Invalid selection, using default archetype", "warn")
            return unique[1]
        end
        return unique[idx]
    end

    local function choose_version(selected_artifact, archetypes)
        local versions = {}
        for _, arch in ipairs(archetypes) do
            if arch.artifact == selected_artifact then
                table.insert(versions, arch.version)
            end
        end
        local choices = {}
        for i, v in ipairs(versions) do
            table.insert(choices, string.format("%d: %s", i, v))
        end
        local sel =
            vim.fn.input(table.concat(choices, "\n") .. "\nSelect version for " .. selected_artifact .. ": ", "1")
        local idx = tonumber(sel)
        if not idx or idx < 1 or idx > #versions then
            notify_msg("Invalid selection, using latest version", "warn")
            return versions[1]
        end
        return versions[idx]
    end

    local available_archetypes = get_available_archetypes()
    local selected_archetype = choose_archetype(available_archetypes)
    local selected_version = choose_version(selected_archetype, available_archetypes)

    if not selected_archetype or not selected_version then
        return
    end

    -------------------------
    -- Step 4: Interactive Mode
    -------------------------
    local interactive_mode, canceled_interactive = get_input("Enter interactiveMode (true/false): ", "false")
    if canceled_interactive then
        return
    end

    -------------------------
    -- Step 5: Run Maven Command
    -------------------------
    local mvn_cmd = string.format(
        'mvn archetype:generate "-DgroupId=%s" "-DartifactId=%s" "-DarchetypeArtifactId=%s" "-DarchetypeVersion=%s" "-DinteractiveMode=%s"',
        group_id,
        artifact_id,
        selected_archetype,
        selected_version,
        interactive_mode
    )

    local output = vim.fn.systemlist(mvn_cmd)
    if vim.v.shell_error ~= 0 then
        notify_msg("Failed to create Maven project:\n" .. table.concat(output, "\n"), "error")
        return
    end

    -------------------------
    -- Step 6: Open Project in Neovim
    -------------------------
    local ok, err2 = pcall(vim.fn.chdir, project_dir)
    if not ok then
        notify_msg("Failed to open project: " .. err2, "error")
    end

    if group_id and group_id ~= "" then
        local java_path = group_id:gsub("%.", "/")
        local main_class_path = string.format("src/main/java/%s/App.java", java_path)
        if vim.fn.filereadable(main_class_path) == 1 then
            vim.cmd(":edit " .. main_class_path)
        else
            notify_msg("Main class not found: " .. main_class_path, "warn")
        end
    end

    notify_msg("Maven project created successfully!", "info")
end

-- Create Neovim command
vim.api.nvim_create_user_command("NewMavenProject", mvn_new_project, {})
