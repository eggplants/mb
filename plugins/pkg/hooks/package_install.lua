local cmd = require("cmd")

local function specs(packages)
    local list = {}
    for _, pkg in ipairs(packages) do
        table.insert(list, pkg.version and (pkg.name .. "=" .. pkg.version) or pkg.name)
    end
    return table.concat(list, " ")
end

function PLUGIN:PackageInstall(ctx)
    local pkgs = specs(ctx.packages)
    if ctx.dry_run then
        print("would install " .. pkgs)
        return
    end
    if ctx.update then
        cmd.exec("pkg update -y")
    end
    -- PKGS holds names validated by Termux's apt; keep it unquoted to split it
    cmd.exec("pkg install -y -- $PKGS", { env = { PKGS = pkgs } })
end
