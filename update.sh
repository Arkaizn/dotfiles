#!/usr/bin/env bash
set -euo pipefail

DOTFILES_DIR="$HOME/git/dotfiles/.config"
TARGET_DIR="$HOME/.config"

# Funktion: listet nur Unterordner + Dateien einer Ebene unter base
list_immediate() {
    local base="$1"
    find "$base" -mindepth 1 -maxdepth 1 -type d -printf "%f/\n"
    find "$base" -maxdepth 1 -type f -printf "%f\n"
}

# Erste Ebene in dotfiles/.config
mapfile -t top_dirs < <(find "$DOTFILES_DIR" -mindepth 1 -maxdepth 1 -type d -printf "%f\n")
mapfile -t top_files < <(find "$DOTFILES_DIR" -maxdepth 1 -type f -printf "%f\n")

options=( "${top_dirs[@]}" "root-files" )

chosen_top=$(printf "%s\n" "${options[@]}" | gum choose --no-limit --height 20)

if [[ -z "$chosen_top" ]]; then
    echo "❌ Keine Auswahl in oberster Ebene."
    exit 1
fi

final_paths=()

for item in $chosen_top; do

    if [[ "$item" == "root-files" ]]; then
        files=( "${top_files[@]}" )
        prefix=""
    elif [[ "$item" == "hypr" ]]; then
        # deine spezielle Ausnahme für hypr
        mapfile -t hypr_subdirs < <(find "$DOTFILES_DIR/hypr" -mindepth 1 -type d -printf "%P\n")
        mapfile -t hypr_root_files < <(find "$DOTFILES_DIR/hypr" -maxdepth 1 -type f -printf "%P\n")

        hypr_options=( "${hypr_subdirs[@]}" "hypr-root-files" )
        hypr_chosen=$(printf "%s\n" "${hypr_options[@]}" | gum choose --no-limit --height 20)

        if [[ -z "$hypr_chosen" ]]; then
            continue
        fi

        for hy in $hypr_chosen; do
            if [[ "$hy" == "hypr-root-files" ]]; then
                for f in "${hypr_root_files[@]}"; do
                    final_paths+=( "hypr/$f" )
                done
            else
                path="$DOTFILES_DIR/hypr/$hy"
                prefix_hy="hypr/$hy"
                items=( $(list_immediate "$path") )
                if [[ ${#items[@]} -eq 0 ]]; then
                    continue
                fi

                echo "📂 hypr/$hy — wähle Dateien oder Unterordner (alle vorausgewählt):"
                selected_args=()
                for i in "${items[@]}"; do
                    selected_args+=(--selected "$i")
                done

                selection=$(printf "%s\n" "${items[@]}" | gum choose --no-limit --height 20 "${selected_args[@]}")

                if [[ -n "$selection" ]]; then
                    while IFS= read -r sel; do
                        final_paths+=( "$prefix_hy/$sel" )
                    done <<< "$selection"
                fi
            fi
        done

    elif [[ "$item" == "custom" ]]; then
        # Spezieller Teil: wenn custom gewählt ist, zusätzlich Abfrage in custom/scripts
        path="$DOTFILES_DIR/custom"
        prefix_custom="custom"

        # Liste Unterordner + Dateien in custom
        items=( $(list_immediate "$path") )
        if [[ ${#items[@]} -ne 0 ]]; then
            echo "📂 Auswahl im Item: custom — wähle Unterordner oder Dateien (alle vorausgewählt):"
            selected_args=()
            for f in "${items[@]}"; do
                selected_args+=(--selected "$f")
            done
            selection=( $(printf "%s\n" "${items[@]}" | gum choose --no-limit --height 20 "${selected_args[@]}") )

            for sel in "${selection[@]}"; do
                # Wenn scripts/ (Ordner) gewählt wird, dann nochmal in scripts Dateien zeigen
                if [[ "$sel" == "scripts/" ]]; then
                    script_path="$path/scripts"
                    prefix_scripts="custom/scripts"
                    script_items=( $(list_immediate "$script_path") )
                    if [[ ${#script_items[@]} -ne 0 ]]; then
                        echo "🛠 custom/scripts — wähle Dateien (alle vorausgewählt):"
                        selected_args2=()
                        for fi in "${script_items[@]}"; do
                            selected_args2+=(--selected "$fi")
                        done
                        script_sel=( $(printf "%s\n" "${script_items[@]}" | gum choose --no-limit --height 20 "${selected_args2[@]}") )
                        for sf in "${script_sel[@]}"; do
                            final_paths+=( "$prefix_scripts/$sf" )
                        done
                    fi
                else
                    # normaler Ordner oder Datei in custom, nicht scripts oder andere
                    # Ordner: sel endet mit '/'
                    if [[ "$sel" == */ ]]; then
                        final_paths+=( "$prefix_custom/$sel" )
                    else
                        final_paths+=( "$prefix_custom/$sel" )
                    fi
                fi
            done
        fi

    else
        # Allgemeiner Fall für alle anderen Ordner außer hypr und custom

        path="$DOTFILES_DIR/$item"
        prefix="$item"
        items=( $(list_immediate "$path") )
        if [[ ${#items[@]} -eq 0 ]]; then
            continue
        fi

        echo "📂 Auswahl im Item: $item — wähle Unterordner oder Dateien (alle vorausgewählt):"
        selected_args=()
        for f in "${items[@]}"; do
            selected_args+=(--selected "$f")
        done
        selection=( $(printf "%s\n" "${items[@]}" | gum choose --no-limit --height 20 "${selected_args[@]}") )
        for sel in "${selection[@]}"; do
            final_paths+=( "$prefix/$sel" )
        done
    fi

done

# Dann wie vorher: Prüfen final_paths, Kopieren etc., mit Rekursion, ohne Ordner-in-sich selbst
if [[ ${#final_paths[@]} -eq 0 ]]; then
    echo "❌ Nach Abwählen keine Dateien oder Ordner übrig."
    exit 1
fi

echo "👉 Folgende Pfade werden kopiert / ersetzt:"
for p in "${final_paths[@]}"; do
    echo "   - $p"
done

if gum confirm "Fortfahren und kopieren?" ; then
    for p in "${final_paths[@]}"; do
        src="$DOTFILES_DIR/$p"
        dest="$TARGET_DIR/$p"

        real_src=$(realpath "$src")
        real_dest=$(realpath "$(dirname "$dest")")

        if [[ "$real_dest" == "$real_src"* ]]; then
            echo "⚠️ Überspringe $p → Ziel liegt innerhalb der Quelle, vermeidet Schleife."
            continue
        fi

        if [[ "${p: -1}" == "/" ]]; then
            mkdir -p "$dest"
            cp -a "$src/." "$dest/"
        else
            mkdir -p "$(dirname "$dest")"
            cp -v "$src" "$dest"
        fi
    done
    echo "✅ Kopiervorgang erledigt."
else
    echo "❌ Abgebrochen."
fi
