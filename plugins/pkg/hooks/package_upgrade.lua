local cmd = require("cmd")

function PLUGIN:PackageUpgrade(ctx)
    local names = {}
    for _, pkg in ipairs(ctx.packages) do
        if not pkg.version then
            table.insert(names, pkg.name)
        end
    end
    if #names == 0 then
        return
    end
    local pkgs = table.concat(names, " ")
    if ctx.dry_run then
        print("would upgrade " .. pkgs)
        return
    end
    cmd.exec("pkg update -y")
    cmd.exec("apt-get install -y --only-upgrade -- $PKGS", { env = { PKGS = pkgs } })
end
