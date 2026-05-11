-- Window rules: assign apps to workspaces
hl.window_rule({ match = { class = "^(zen)$" },                                    workspace = "1" })
hl.window_rule({ match = { class = "^(RemoteDesktopManager)$" },                   workspace = "2" })
hl.window_rule({ match = { class = "^(teams-for-linux|KeePassXC|obsidian|VSCodium)$" }, workspace = "3" })
hl.window_rule({ match = { class = "^(xfreerdp)$" },                               workspace = "9" })

-- Workspace monitor assignments
local asus = "desc:ASUSTek COMPUTER INC XG27ACDNG T2LMAS036666"
local hp   = "desc:HP Inc. HP X27 6CM3153FCC"

for i = 1, 7 do
    hl.workspace_rule({ workspace = tostring(i), monitor = asus })
end
hl.workspace_rule({ workspace = "8",  monitor = hp })
hl.workspace_rule({ workspace = "9",  monitor = hp })
hl.workspace_rule({ workspace = "10", monitor = hp })