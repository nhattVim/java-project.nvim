local M = {}

M.setup = function()
    require("java_project.maven")
    require("java_project.gradle")
    require("java_project.springboot")
end

return M
