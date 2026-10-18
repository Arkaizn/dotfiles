#!/bin/sh
# Package usage data for the settings app's Packages page (read-only):
#   P<TAB>package<TAB>path            a program of the package (/usr/bin)
#   S<TAB>atime<TAB>ctime<TAB>path    its last access / last change (unix s)
#   U<TAB>package<TAB>unit            a systemd unit of the package
#   A<TAB>unit                        an enabled or running unit (system + user)
#   D<TAB>package                     has a launcher (.desktop file)

t=$(mktemp) || exit 1
trap 'rm -f "$t"' EXIT

pacman -Ql | awk 'index($2, "/usr/bin/") == 1 && $2 !~ /\/$/ { print $1 "\t" $2 }' > "$t"
sed 's/^/P\t/' "$t"
cut -f2 "$t" | xargs -r -d '\n' stat -L -c 'S	%X	%Z	%n' 2>/dev/null

pacman -Ql | awk '(index($2, "/usr/lib/systemd/system/") == 1 || index($2, "/usr/lib/systemd/user/") == 1) && $2 !~ /\/$/ {
    n = $2; sub(/.*\//, "", n); print "U\t" $1 "\t" n }'

for scope in --system --user; do
    systemctl "$scope" list-units --state=active --no-legend --plain 2>/dev/null | awk '{ print "A\t" $1 }'
    systemctl "$scope" list-unit-files --state=enabled --no-legend 2>/dev/null | awk '{ print "A\t" $1 }'
done

# packages with a launcher (.desktop file): apps, not command-line tools
pacman -Ql | awk 'index($2, "/usr/share/applications/") == 1 && $2 ~ /\.desktop$/ { print "D\t" $1 }' | sort -u
