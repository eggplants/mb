local cmd = require("cmd")

function PLUGIN:PackageUninstall(ctx)
    local names = {}
    for _, pkg in ipairs(ctx.packages) do
        table.insert(names, pkg.name)
    end
    cmd.exec("pkg uninstall -y -- $PKGS", { env = { PKGS = table.concat(names, " ") } })
end
