local cmd = require("cmd")

function PLUGIN:PackageInstalled(ctx)
    local installed = {}
    local output = cmd.exec("dpkg-query -W -f='${db:Status-Abbrev} ${Package} ${Version}\\n'")
    for line in output:gmatch("[^\r\n]+") do
        local status, name, version = line:match("^(%S+)%s+(%S+)%s+(%S+)$")
        if status == "ii" then
            installed[name] = version
        end
    end

    local results = {}
    for _, pkg in ipairs(ctx.packages) do
        local version = installed[pkg.name]
        table.insert(results, {
            name = pkg.name,
            state = version and "installed" or "missing",
            version = version,
        })
    end
    return { packages = results }
end
