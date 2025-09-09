-------------------------
-- Helper Functions
-------------------------

local U = {}

U.notify = function(message, level)
    local ok, notify = pcall(require, "notify")
    if ok then
        notify(message, level, { timeout = 4000 })
    else
        print("[" .. (level or "info") .. "] " .. message)
    end
end

U.input = function(prompt, default)
    vim.fn.inputsave()
    local result = vim.fn.input(prompt, default)
    vim.fn.inputrestore()
    if result == "" then
        U.notify("Input canceled.", "info")
        return nil, true
    end
    return result, false
end

U.select_choice = function(prompt, choices, default_value)
    if not choices or #choices == 0 then
        U.notify("No choices available.", "warn")
        return nil, true
    end

    local default_idx = 1
    if default_value then
        for i, choice in ipairs(choices) do
            if choice == default_value then
                default_idx = i
                break
            end
        end
    end

    local display_choices = {}
    for i, choice in ipairs(choices) do
        table.insert(display_choices, string.format("%d: %s", i, choice))
    end

    local full_prompt = table.concat(display_choices, "\n") .. "\n" .. prompt

    vim.fn.inputsave()
    local sel_str = vim.fn.input(full_prompt, tostring(default_idx))
    vim.fn.inputrestore()

    if sel_str == "" then
        U.notify("Selection canceled.", "info")
        return nil, true
    end

    local idx = tonumber(sel_str)
    if not idx or idx < 1 or idx > #choices then
        U.notify("Invalid selection, using default.", "warn")
        return default_idx, false
    end

    return idx, false
end

U.basename = function(path)
    local sep = package.config:sub(1, 1)
    local pattern = sep == "\\" and "([^\\]+)$" or "([^/]+)$"
    return path:match(pattern)
end

U.check_requirements = function(requirements)
    for _, cmd in ipairs(requirements) do
        if vim.fn.executable(cmd) == 0 then
            U.notify("Requirement not found in PATH: " .. cmd .. ", Please install it first", "error")
            return
        end
    end
end

U.prepare_dir = function(path)
    if vim.fn.isdirectory(path) ~= 0 then
        local files = vim.fn.readdir(path)
        if #files > 0 then
            local override, canceled_override = U.input("Directory not empty. Override? (y/N): ", "n")
            if canceled_override or not override or override:lower() ~= "y" then
                U.notify("Project creation canceled.", "info")
                return false
            end

            -- Delete the contents of the directory
            for _, f in ipairs(files) do
                local full_path = path .. package.config:sub(1, 1) .. f
                if vim.fn.isdirectory(full_path) ~= 0 then
                    vim.fn.delete(full_path, "rf") -- "r" recursive, "f" force
                else
                    vim.fn.delete(full_path)
                end
            end
            U.notify("Directory contents cleared for override.", "info")
        end
    else
        if vim.fn.mkdir(path, "p") == 0 then
            U.notify("Failed to create project directory: " .. path, "error")
            return false
        end
    end

    return true
end

U.chdir = function(path)
    local ok, err = pcall(vim.fn.chdir, path)
    if not ok then
        U.notify("Error changing directory: " .. err, "error")
        return
    end
    U.notify("Changed directory to: " .. path, "info")
end

U.get_gradle_params = function()
    local output = vim.fn.systemlist("gradle help --task init")
    local params = { types = {}, dsls = {}, test_frameworks = {} }

    local current_section = nil
    for _, line in ipairs(output) do
        if line:match("%-%-type") then
            current_section = "types"
        elseif line:match("%-%-dsl") then
            current_section = "dsls"
        elseif line:match("%-%-test%-framework") then
            current_section = "test_frameworks"
        elseif line:match("^%s+[%w%-]+") and current_section then
            -- line kiểu "     java-application"
            local val = vim.trim(line)
            table.insert(params[current_section], val)
        end
    end
    return params
end

return U
