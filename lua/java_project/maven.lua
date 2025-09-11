local U = require("java_project.utils")

local function mvn_new_project()
    -------------------------
    -- Step 0: Check Requirements
    -------------------------
    if not U.check_requirements({ "curl", "mvn", "java" }) then
        return
    end

    -------------------------
    -- Step 1: Project Directory
    -------------------------
    local project_dir, dir_canceled = U.input("Enter project directory: ", vim.fn.getcwd())
    if dir_canceled or not project_dir then
        return
    end

    -- Check if the project directory already exists
    if not U.prepare_dir(project_dir) then
        return
    end

    -- Change into the parent directory to excute Maven
    if not U.chdir(vim.fn.fnamemodify(project_dir, ":h")) then
        return
    end

    -------------------------
    -- Step 2: Maven Coordinates
    -------------------------
    local artifact_id = U.basename(project_dir)
    local group_id, group_canceled = U.input("Enter groupId: ", "com.example")
    if group_canceled then
        return
    end

    -------------------------
    -- Step 3: Archetype Selection
    -------------------------
    local POPULAR_ARCHETYPES = {
        { group = "org.apache.maven.archetypes", artifact = "maven-archetype-quickstart" },
        { group = "org.apache.maven.archetypes", artifact = "maven-archetype-webapp" },
        { group = "org.apache.maven.archetypes", artifact = "maven-archetype-simple" },
    }
    local CACHE_FILE = vim.fn.stdpath("cache") .. "/maven_archetypes.json"

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

    local function get_archetype_versions(group, artifact)
        local url = string.format(
            'https://search.maven.org/solrsearch/select?q=g:"%s"+AND+a:"%s"&core=gav&rows=10&wt=json',
            group,
            artifact
        )
        local cmd = 'curl -s --max-time 10 "' .. url .. '"'
        local output = vim.fn.system(cmd)
        local ok, data = pcall(vim.fn.json_decode, output)
        local versions = {}
        if ok and data and data.response and data.response.docs then
            for _, doc in ipairs(data.response.docs) do
                if doc.v then
                    table.insert(versions, { group = doc.g, artifact = doc.a, version = doc.v })
                end
            end
        end
        table.sort(versions, function(a, b)
            return a.version > b.version
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
            U.notify("Loaded archetypes from cache.", "info")
            return cached
        end
        U.notify("Fetching latest archetypes from Maven Central...", "info")
        local archetypes = {}
        for _, def in ipairs(POPULAR_ARCHETYPES) do
            local versions = get_archetype_versions(def.group, def.artifact)
            if #versions > 0 then
                vim.list_extend(archetypes, versions)
            end
        end
        if #archetypes == 0 then
            table.insert(
                archetypes,
                { group = "org.apache.maven.archetypes", artifact = "maven-archetype-quickstart", version = "1.5" }
            )
            U.notify("Could not fetch archetypes, using default.", "warn")
        else
            save_cache(archetypes)
        end
        return archetypes
    end

    local function choose_archetype(archetypes)
        local unique, seen = {}, {}
        for _, arch in ipairs(archetypes) do
            if not seen[arch.artifact] then
                table.insert(unique, { group = arch.group, artifact = arch.artifact })
                seen[arch.artifact] = true
            end
        end

        local display_choices = {}
        for _, arch_info in ipairs(unique) do
            table.insert(display_choices, arch_info.artifact)
        end

        local idx, canceled = U.select_choice("Select archetype: ", display_choices, display_choices[1])
        if canceled then
            return nil
        end

        local selected = unique[idx]
        return selected.group .. ":" .. selected.artifact
    end

    local function choose_version(selected_ga, archetypes)
        local versions = {}
        local selected_group, selected_artifact = unpack(vim.split(selected_ga, ":"))
        for _, arch in ipairs(archetypes) do
            if arch.group == selected_group and arch.artifact == selected_artifact then
                table.insert(versions, arch.version)
            end
        end

        local prompt = "Select version for " .. selected_artifact .. ": "
        local idx, canceled = U.select_choice(prompt, versions, versions[1])
        if canceled then
            return nil, nil, nil
        end

        return versions[idx], selected_group, selected_artifact
    end

    local available_archetypes = get_available_archetypes()
    if not available_archetypes then
        return
    end

    local selected_ga = choose_archetype(available_archetypes)
    if not selected_ga then
        return
    end

    local selected_version, selected_group, selected_artifact = choose_version(selected_ga, available_archetypes)
    if not selected_version then
        return
    end

    -------------------------
    -- Step 4: Interactive Mode
    -------------------------
    local interactive_mode, interactive_canceled = U.input("Enter interactiveMode (true/false): ", "false")
    if interactive_canceled then
        return
    end

    -------------------------
    -- Step 5: Run Maven Command
    -------------------------
    local mvn_cmd = string.format(
        'mvn archetype:generate "-DgroupId=%s" "-DartifactId=%s" "-DarchetypeGroupId=%s" "-DarchetypeArtifactId=%s" "-DarchetypeVersion=%s" "-DinteractiveMode=%s"',
        group_id,
        artifact_id,
        selected_group,
        selected_artifact,
        selected_version,
        interactive_mode
    )

    U.notify("Running command, this may take a moment...", "info")
    local output = vim.fn.systemlist(mvn_cmd)
    if vim.v.shell_error ~= 0 then
        U.notify("Failed to create Maven project:\n" .. table.concat(output, "\n"), "error")
        return
    end

    -------------------------
    -- Step 6: Open Project in Neovim
    -------------------------
    if not U.chdir(project_dir) then
        U.notify("Failed to change directory to: " .. project_dir, "error")
        return
    end

    if group_id and group_id ~= "" then
        local java_path = group_id:gsub("%.", "/")
        local main_class_path = string.format("src/main/java/%s/App.java", java_path)
        if vim.fn.filereadable(main_class_path) == 1 then
            vim.cmd(":edit " .. main_class_path)
        else
            U.notify("Main class not found: " .. main_class_path, "warn")
        end
    end

    U.notify("Maven project created successfully!", "info")
end

vim.api.nvim_create_user_command("NewMavenProject", mvn_new_project, {})
