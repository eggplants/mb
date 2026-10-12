local cmd = require("cmd")

local function specs(packages)
    local list = {}
    for _, pkg in ipairs(packages) do
        table.insert(list, pkg.version and (pkg.name .. "=" .. pkg.version) or pkg.name)
    end
    return table.concat(list, " ")
end

function PLUGIN:PackageInstall(ctx)
    -- Termux's *-repo packages (glibc-repo, x11-repo, tur-repo, ...) add apt sources, so
    -- they go first and the package lists are refreshed before the rest (e.g. glibc-runner)
    local repos, rest = {}, {}
    for _, pkg in ipairs(ctx.packages) do
        table.insert(pkg.name:match("%-repo$") and repos or rest, pkg)
    end
    if ctx.dry_run then
        print("would install " .. specs(ctx.packages))
        return
    end
    if ctx.update then
        cmd.exec("pkg update -y")
    end
    -- PKGS holds names validated by Termux's apt; keep it unquoted to split it
    if #repos > 0 then
        cmd.exec("pkg install -y -- $PKGS", { env = { PKGS = specs(repos) } })
        cmd.exec("apt-get update")
    end
    if #rest > 0 then
        cmd.exec("pkg install -y -- $PKGS", { env = { PKGS = specs(rest) } })
    end
end
