-- https://wiki.hypr.land/Configuring/Basics/Autostart/

hl.on("hyprland.start", function () 
  hl.exec_cmd("hyprctl setcursor Bibata-Modern-Ice 24")
  hl.exec_cmd("awww-daemon")
  hl.exec_cmd("QS_NO_RELOAD_POPUP=1 qs")
  hl.exec_cmd("cliphist wipe")
  hl.exec_cmd("wl-paste --watch cliphist store")
  hl.exec_cmd("~/.config/hypr/wallpapers/set_wallpaper.sh")
  hl.exec_cmd("~/.config/hypr/hyprlock/hyprlock.sh")
  hl.exec_cmd("hypridle")
  hl.exec_cmd("hyprpm reload -n")
  hl.exec_cmd("nm-applet --indicator")
end)
