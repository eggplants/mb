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
    if ctx.dry_run then
        print("would upgrade all packages (requested: " .. table.concat(names, " ") .. ")")
        return
    end
    -- Termux does not support partial upgrades: library deps are unversioned, so upgrading
    -- only the listed packages can leave them linked against an old soname (e.g. ffmpeg vs libplacebo)
    cmd.exec("pkg upgrade -y -o Dpkg::Options::=--force-confdef -o Dpkg::Options::=--force-confold")
end
