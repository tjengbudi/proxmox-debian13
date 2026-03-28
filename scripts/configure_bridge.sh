#!/bin/bash

# Proxmox Setup v1.1.0
# by: Matheew Alves

cd /proxmox-debian13

# Load configs files // Carregar os arquivos de configuração
source ./configs/colors.conf
source ./configs/language.conf

AUTORUN=0
if [ "${1:-}" = "--autorun" ]; then
    AUTORUN=1
fi

validate_ipv4()
{
    [[ "$1" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]
}

validate_cidr()
{
    [[ "$1" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}/([0-9]|[12][0-9]|3[0-2])$ ]]
}

apply_network_changes()
{
    if command -v ifreload >/dev/null 2>&1; then
        ifreload -a
    else
        systemctl restart networking
    fi
}

show_layout_error()
{
    local details="${1:-}"

    if [ "$LANGUAGE" == "en" ]; then
        whiptail --title "Network Configuration" --msgbox "Automatic bridge rewrite could not safely determine which network file should be updated.\n\n${details}\nPlease migrate the bridge configuration manually." 16 70
    else
        whiptail --title "Configuração de Rede" --msgbox "A reescrita automática da bridge não conseguiu determinar com segurança qual arquivo de rede deve ser atualizado.\n\n${details}\nFaça a migração manualmente." 16 70
    fi
}

show_generated_file_error()
{
    if [ "$LANGUAGE" == "en" ]; then
        whiptail --title "Network Configuration ERROR" --msgbox "The generated /etc/network/interfaces content did not pass internal validation.\n\nThe original file was kept unchanged.\nPlease review the network configuration manually." 14 70
    else
        whiptail --title "ERRO na Configuração de Rede" --msgbox "O conteúdo gerado para /etc/network/interfaces não passou na validação interna.\n\nO arquivo original foi mantido inalterado.\nRevise a configuração de rede manualmente." 14 70
    fi
}

confirm_dhcp_selection()
{
    if [ "$LANGUAGE" == "en" ]; then
        whiptail --title "Network Configuration" --defaultno --yesno "DHCP mode will replace the current static address assignment for this host with a DHCP-based bridge.\n\nOn dedicated servers this often breaks remote access if no DHCP service is present.\n\nDo you want to continue with DHCP mode?" 16 70
    else
        whiptail --title "Configuração de Rede" --defaultno --yesno "O modo DHCP vai substituir o endereçamento estático atual deste host por uma bridge baseada em DHCP.\n\nEm servidores dedicados isso costuma quebrar o acesso remoto se não existir um serviço DHCP disponível.\n\nDeseja continuar com o modo DHCP?" 16 70
    fi
}

should_apply_network_now()
{
    if is_ssh_autorun; then
        return 1
    fi

    if [ -n "$SSH_CONNECTION" ]; then
        if [ "$LANGUAGE" == "en" ]; then
            whiptail --title "Network Configuration" --defaultno --yesno "You are connected over SSH.\n\nApplying the new bridge configuration right now may terminate this remote session and leave the server unreachable if the network settings are wrong.\n\nRecommended action: choose 'No', then apply from console/KVM or reboot the server.\n\nDo you still want to apply the network changes now?" 18 72
        else
            whiptail --title "Configuração de Rede" --defaultno --yesno "Você está conectado via SSH.\n\nAplicar a nova bridge agora pode derrubar esta sessão remota e deixar o servidor inacessível se as configurações de rede estiverem erradas.\n\nAção recomendada: escolher 'Não', depois aplicar via console/KVM ou reiniciar o servidor.\n\nDeseja aplicar as alterações de rede agora mesmo?" 18 72
        fi
        return $?
    fi

    return 0
}

show_deferred_apply_message()
{
    if [ "$LANGUAGE" == "en" ]; then
        whiptail --title "Network Configuration" --msgbox "The bridge configuration files were saved, but the live network was NOT reloaded.\n\nApply the changes later from console/KVM with:\nifreload -a\n\nor reboot the server when you are ready." 16 70
    else
        whiptail --title "Configuração de Rede" --msgbox "Os arquivos da bridge foram salvos, mas a rede em execução NÃO foi recarregada.\n\nAplique as alterações depois via console/KVM com:\nifreload -a\n\nou reinicie o servidor quando estiver pronto." 16 70
    fi
}

show_ssh_autorun_message()
{
    if [ "$LANGUAGE" == "en" ]; then
        echo "Bridge setup was started automatically during SSH login."
        echo "The saved static network settings will be written automatically, but live reload will be skipped for safety."
        echo "If you want a different layout, run it manually later with:"
        echo "  bash /proxmox-debian13/scripts/configure_bridge.sh"
    else
        echo "A configuração da bridge foi iniciada automaticamente durante o login SSH."
        echo "As configurações estáticas salvas serão gravadas automaticamente, mas a recarga ao vivo será ignorada por segurança."
        echo "Se quiser um layout diferente, execute manualmente depois com:"
        echo "  bash /proxmox-debian13/scripts/configure_bridge.sh"
    fi
}

is_ssh_autorun()
{
    [ "$AUTORUN" -eq 1 ] && [ -n "$SSH_CONNECTION" ]
}

show_autorun_apply_result()
{
    if [ "$LANGUAGE" == "en" ]; then
        echo "Bridge configuration was generated automatically with:"
        echo "  interface: $INTERFACE"
        echo "  address:   $IP_ADDRESS"
        echo "  gateway:   ${GATEWAY:-<none>}"
        echo "Live network reload was skipped because this was triggered during SSH login."
        echo "Apply later from console/KVM with:"
        echo "  ifreload -a"
        echo "or reboot the server when ready."
    else
        echo "A configuração da bridge foi gerada automaticamente com:"
        echo "  interface: $INTERFACE"
        echo "  address:   $IP_ADDRESS"
        echo "  gateway:   ${GATEWAY:-<nenhum>}"
        echo "A recarga ao vivo da rede foi ignorada porque isso foi acionado durante o login SSH."
        echo "Aplique depois via console/KVM com:"
        echo "  ifreload -a"
        echo "ou reinicie o servidor quando estiver pronto."
    fi
}

persist_network_config()
{
    local config_file="$1"
    local iface="$2"
    local ip_cidr="$3"
    local gw="$4"

    echo "INTERFACE=$iface" > "$config_file"
    echo "IP_ADDRESS=$ip_cidr" >> "$config_file"
    echo "GATEWAY=$gw" >> "$config_file"
}

apply_saved_static_bridge_config()
{
    local config_file="$1"

    if ! ip link show dev "$INTERFACE" >/dev/null 2>&1; then
        if [ "$LANGUAGE" == "en" ]; then
            echo "Automatic bridge setup aborted: interface '$INTERFACE' does not exist."
        else
            echo "Configuração automática da bridge abortada: a interface '$INTERFACE' não existe."
        fi
        return 1
    fi

    if ! validate_cidr "$IP_ADDRESS"; then
        if [ "$LANGUAGE" == "en" ]; then
            echo "Automatic bridge setup aborted: saved IP/CIDR '$IP_ADDRESS' is invalid."
        else
            echo "Configuração automática da bridge abortada: o IP/CIDR salvo '$IP_ADDRESS' é inválido."
        fi
        return 1
    fi

    if [[ -n "$GATEWAY" ]] && ! validate_ipv4 "$GATEWAY"; then
        if [ "$LANGUAGE" == "en" ]; then
            echo "Automatic bridge setup aborted: saved gateway '$GATEWAY' is invalid."
        else
            echo "Configuração automática da bridge abortada: o gateway salvo '$GATEWAY' é inválido."
        fi
        return 1
    fi

    persist_network_config "$config_file" "$INTERFACE" "$IP_ADDRESS" "$GATEWAY"

    if ! install_bridge_config "$INTERFACE" "static" "$IP_ADDRESS" "$GATEWAY"; then
        return 1
    fi

    return 0
}

render_bridge_config()
{
    local iface="$1"
    local mode="$2"
    local ip_cidr="$3"
    local gw="$4"

    cat <<EOF

# Physical interface for Proxmox bridge
auto $iface
iface $iface inet manual

# Proxmox Bridge
auto vmbr0
iface vmbr0 inet $mode
EOF

    if [ "$mode" = "static" ]; then
        printf "    address %s\n" "$ip_cidr"
        if [ -n "$gw" ]; then
            printf "    gateway %s\n" "$gw"
        fi
    fi

    cat <<EOF
    bridge_ports $iface
    bridge_stp off
    bridge_fd 0
EOF
}

file_has_iface_definition()
{
    local file="$1"
    local iface="$2"

    grep -Eq "^[[:space:]]*iface[[:space:]]+${iface//./\\.}([[:space:]]+|$)" "$file"
}

collect_sourced_interface_files()
{
    collect_network_files_recursive /etc/network/interfaces | tail -n +2
}

collect_all_network_files()
{
    collect_network_files_recursive /etc/network/interfaces
}

resolve_network_include_path()
{
    local base_dir="$1"
    local raw_path="$2"

    case "$raw_path" in
        /*)
            printf '%s\n' "$raw_path"
            ;;
        *)
            printf '%s\n' "$base_dir/$raw_path"
            ;;
    esac
}

expand_network_include_spec()
{
    local base_dir="$1"
    local include_spec="$2"
    local resolved_spec

    resolved_spec=$(resolve_network_include_path "$base_dir" "$include_spec")

    compgen -G "$resolved_spec" || true
}

collect_network_files_recursive()
{
    local root_file="$1"

    declare -A seen=()

    _collect_network_files_recursive_inner "$root_file" seen
}

_collect_network_files_recursive_inner()
{
    local file="$1"
    local seen_name="$2"
    local line
    local include_spec
    local include_path
    local include_dir
    local candidate
    local base_dir
    declare -n seen_ref="$seen_name"

    [ -f "$file" ] || return 0

    case "$file" in
        /*)
            ;;
        *)
            file="$(readlink -f "$file")"
            ;;
    esac

    if [ "${seen_ref[$file]}" = "1" ]; then
        return 0
    fi
    seen_ref["$file"]=1

    printf '%s\n' "$file"

    base_dir=$(dirname "$file")

    while IFS= read -r line; do
        case "$line" in
            [[:space:]]*source[[:space:]]*)
                include_spec=$(printf '%s\n' "$line" | awk '{print $2}')
                for candidate in $include_spec; do
                    while IFS= read -r include_path; do
                        [ -f "$include_path" ] || continue
                        _collect_network_files_recursive_inner "$include_path" "$seen_name"
                    done < <(expand_network_include_spec "$base_dir" "$candidate")
                done
                ;;
            [[:space:]]*source-directory[[:space:]]*)
                include_spec=$(printf '%s\n' "$line" | awk '{print $2}')
                include_dir=$(resolve_network_include_path "$base_dir" "$include_spec")
                if [ -d "$include_dir" ]; then
                    while IFS= read -r candidate; do
                        [ -f "$candidate" ] || continue
                        _collect_network_files_recursive_inner "$candidate" "$seen_name"
                    done < <(find "$include_dir" -maxdepth 1 -type f ! -name '.*' | sort)
                fi
                ;;
        esac
    done < "$file"
}

backup_network_files()
{
    local backup_dir
    local file
    local backup_file

    backup_dir=$(mktemp -d)
    : > "$backup_dir/manifest"

    while IFS= read -r file; do
        [ -f "$file" ] || continue
        backup_file="$backup_dir/$(basename "$file").$(cksum < "$file" | awk '{print $1}')"
        cp "$file" "$backup_file"
        printf '%s|%s\n' "$file" "$backup_file" >> "$backup_dir/manifest"
    done < <(collect_all_network_files)

    printf '%s\n' "$backup_dir"
}

restore_network_backups()
{
    local backup_dir="$1"
    local file
    local backup_file

    [ -n "$backup_dir" ] || return 0
    [ -f "$backup_dir/manifest" ] || return 0

    while IFS='|' read -r file backup_file; do
        [ -f "$backup_file" ] || continue
        cp "$backup_file" "$file"
    done < "$backup_dir/manifest"
}

cleanup_network_backups()
{
    local backup_dir="$1"

    [ -n "$backup_dir" ] || return 0
    rm -rf "$backup_dir"
}

is_cloud_init_network_file()
{
    local file="$1"

    case "$(basename "$file")" in
        *cloud-init*)
            return 0
            ;;
    esac

    grep -q "generated from information provided by the datasource" "$file"
}

disable_cloud_init_network_config()
{
    mkdir -p /etc/cloud/cloud.cfg.d
    cat > /etc/cloud/cloud.cfg.d/99-disable-network-config.cfg <<'EOF'
network: {config: disabled}
EOF
}

show_cloud_init_takeover_message()
{
    if [ "$LANGUAGE" == "en" ]; then
        echo "Cloud-init network management was disabled so the Proxmox bridge configuration can persist."
    else
        echo "O gerenciamento de rede do cloud-init foi desativado para que a configuração da bridge do Proxmox persista."
    fi
}

resolve_interfaces_target_file()
{
    local iface="$1"
    local main_file="/etc/network/interfaces"
    local -a sourced_files=()
    local -a iface_matches=()
    local -a bridge_matches=()
    local file

    if file_has_iface_definition "$main_file" "$iface" || file_has_iface_definition "$main_file" "vmbr0"; then
        printf '%s\n' "$main_file"
        return 0
    fi

    while IFS= read -r file; do
        [ -n "$file" ] || continue
        sourced_files+=("$file")
    done < <(collect_sourced_interface_files)

    if [ ${#sourced_files[@]} -eq 0 ]; then
        printf '%s\n' "$main_file"
        return 0
    fi

    for file in "${sourced_files[@]}"; do
        if file_has_iface_definition "$file" "$iface"; then
            iface_matches+=("$file")
        fi
        if file_has_iface_definition "$file" "vmbr0"; then
            bridge_matches+=("$file")
        fi
    done

    if [ ${#iface_matches[@]} -eq 1 ]; then
        printf '%s\n' "${iface_matches[0]}"
        return 0
    fi

    if [ ${#iface_matches[@]} -gt 1 ]; then
        return 2
    fi

    if [ ${#bridge_matches[@]} -eq 1 ]; then
        printf '%s\n' "${bridge_matches[0]}"
        return 0
    fi

    if [ ${#bridge_matches[@]} -gt 1 ]; then
        return 3
    fi

    return 1
}

strip_iface_from_file()
{
    local file="$1"
    local iface="$2"
    local temp_file

    temp_file=$(mktemp)

    awk -v iface="$iface" '
        function is_target(name) {
            return name == iface
        }

        BEGIN {
            skip_stanza = 0
        }

        {
            line = $0

            if (skip_stanza) {
                if (line ~ /^[[:space:]]*$/) {
                    skip_stanza = 0
                    next
                }

                if (line ~ /^[^[:space:]#]/) {
                    skip_stanza = 0
                } else {
                    next
                }
            }

            if (line ~ /^[[:space:]]*iface[[:space:]]+/ && is_target($2)) {
                skip_stanza = 1
                next
            }

            if (line ~ /^[[:space:]]*(auto|allow-[^[:space:]]+)[[:space:]]+/) {
                keyword = $1
                kept = ""

                for (i = 2; i <= NF; i++) {
                    if (!is_target($i)) {
                        kept = kept (kept ? OFS : "") $i
                    }
                }

                if (kept != "") {
                    print keyword, kept
                }
                next
            }

            print
        }
    ' "$file" > "$temp_file" || {
        rm -f "$temp_file"
        return 1
    }

    mv "$temp_file" "$file"
    chmod 644 "$file"
}

ensure_main_loopback()
{
    local main_file="/etc/network/interfaces"
    local temp_file

    if file_has_iface_definition "$main_file" "lo"; then
        return 0
    fi

    temp_file=$(mktemp)
    cat <<'EOF' > "$temp_file"
auto lo
iface lo inet loopback

EOF
    cat "$main_file" >> "$temp_file"
    mv "$temp_file" "$main_file"
    chmod 644 "$main_file"
}

normalize_loopback_definitions()
{
    local main_file="/etc/network/interfaces"
    local -a all_files=()
    local file

    while IFS= read -r file; do
        [ -f "$file" ] || continue
        all_files+=("$file")
    done < <(collect_all_network_files)

    for file in "${all_files[@]}"; do
        if file_has_iface_definition "$file" "lo"; then
            strip_iface_from_file "$file" "lo" || return 1
        fi
    done

    ensure_main_loopback || return 1

    if ! file_has_iface_definition "$main_file" "lo"; then
        return 1
    fi
}

rewrite_interfaces_file()
{
    local iface="$1"
    local mode="$2"
    local ip_cidr="$3"
    local gw="$4"
    local source_file="$5"
    local output_file="$6"
    local strip_loopback=0

    if [ "$source_file" != "/etc/network/interfaces" ] && file_has_iface_definition "/etc/network/interfaces" "lo"; then
        strip_loopback=1
    fi

    awk -v iface="$iface" -v bridge="vmbr0" -v strip_lo="$strip_loopback" '
        function is_target(name) {
            return name == iface || name == bridge || (strip_lo && name == "lo")
        }

        BEGIN {
            skip_stanza = 0
        }

        {
            line = $0

            if (skip_stanza) {
                if (line ~ /^[[:space:]]*$/) {
                    skip_stanza = 0
                    next
                }

                if (line ~ /^[^[:space:]#]/) {
                    skip_stanza = 0
                } else {
                    next
                }
            }

            if (line ~ /^[[:space:]]*iface[[:space:]]+/) {
                if (is_target($2)) {
                    skip_stanza = 1
                    next
                }
            }

            if (line ~ /^[[:space:]]*(auto|allow-[^[:space:]]+)[[:space:]]+/) {
                keyword = $1
                kept = ""

                for (i = 2; i <= NF; i++) {
                    if (!is_target($i)) {
                        kept = kept (kept ? OFS : "") $i
                    }
                }

                if (kept != "") {
                    print keyword, kept
                }
                next
            }

            print
        }
    ' "$source_file" > "$output_file" || return 1

    render_bridge_config "$iface" "$mode" "$ip_cidr" "$gw" >> "$output_file" || return 1
}

validate_generated_interfaces_file()
{
    local iface="$1"
    local mode="$2"
    local ip_cidr="$3"
    local gw="$4"
    local candidate="$5"

    [ -s "$candidate" ] || return 1
    grep -Eq "^[[:space:]]*iface[[:space:]]+$iface[[:space:]]+inet[[:space:]]+manual([[:space:]]|\$)" "$candidate" || return 1
    grep -Eq "^[[:space:]]*iface[[:space:]]+vmbr0[[:space:]]+inet[[:space:]]+$mode([[:space:]]|\$)" "$candidate" || return 1
    grep -Eq "^[[:space:]]*bridge_ports[[:space:]]+$iface([[:space:]]|\$)" "$candidate" || return 1

    if [ "$mode" = "static" ]; then
        grep -Eq "^[[:space:]]*address[[:space:]]+$ip_cidr([[:space:]]|\$)" "$candidate" || return 1
        if [ -n "$gw" ]; then
            grep -Eq "^[[:space:]]*gateway[[:space:]]+$gw([[:space:]]|\$)" "$candidate" || return 1
        fi
    fi
}

install_bridge_config()
{
    local iface="$1"
    local mode="$2"
    local ip_cidr="$3"
    local gw="$4"
    local target_file
    local temp_file
    local rewrite_status
    local target_status

    target_file=$(resolve_interfaces_target_file "$iface")
    target_status=$?

    case $target_status in
        0)
            ;;
        1)
            if [ "$LANGUAGE" == "en" ]; then
                show_layout_error "No file defining 'iface $iface' or 'iface vmbr0' was found in /etc/network/interfaces or sourced fragments."
            else
                show_layout_error "Nenhum arquivo com 'iface $iface' ou 'iface vmbr0' foi encontrado em /etc/network/interfaces ou nos fragments carregados."
            fi
            return 1
            ;;
        2)
            if [ "$LANGUAGE" == "en" ]; then
                show_layout_error "Multiple sourced files define 'iface $iface'. The script cannot safely choose which one to rewrite."
            else
                show_layout_error "Muitos arquivos carregados definem 'iface $iface'. O script não consegue escolher com segurança qual deve ser reescrito."
            fi
            return 1
            ;;
        3)
            if [ "$LANGUAGE" == "en" ]; then
                show_layout_error "Multiple sourced files define 'iface vmbr0'. The script cannot safely choose which one to rewrite."
            else
                show_layout_error "Muitos arquivos carregados definem 'iface vmbr0'. O script não consegue escolher com segurança qual deve ser reescrito."
            fi
            return 1
            ;;
        *)
            show_generated_file_error
            return 1
            ;;
    esac

    temp_file=$(mktemp)

    if is_cloud_init_network_file "$target_file"; then
        disable_cloud_init_network_config
        show_cloud_init_takeover_message
    fi

    rewrite_interfaces_file "$iface" "$mode" "$ip_cidr" "$gw" "$target_file" "$temp_file"
    rewrite_status=$?

    if [ $rewrite_status -ne 0 ]; then
        rm -f "$temp_file"
        show_generated_file_error
        return 1
    fi

    if ! validate_generated_interfaces_file "$iface" "$mode" "$ip_cidr" "$gw" "$temp_file"; then
        rm -f "$temp_file"
        show_generated_file_error
        return 1
    fi

    NETWORK_FILE_BACKUPS_DIR=$(backup_network_files)
    NETWORK_TARGET_FILE="$target_file"

    mv "$temp_file" "$target_file"
    chmod 644 "$target_file"

    if ! normalize_loopback_definitions; then
        restore_network_backups "$NETWORK_FILE_BACKUPS_DIR"
        cleanup_network_backups "$NETWORK_FILE_BACKUPS_DIR"
        NETWORK_FILE_BACKUPS_DIR=""
        show_generated_file_error
        return 1
    fi
}

# Becoming superuser // Tornando-se superusuário
super_user()
{
    if [ "$(whoami)" != "root" ]; then
        if [ "$LANGUAGE" == "en" ]; then
            echo -e "${ciano}Log in as superuser...${default}"
        else
            echo -e "${ciano}Faça o login como superusuário...${default}" 
        fi
        sudo -E bash "$0" "$@"
        exit $?
    fi
}

configure_bridge()
{
    config_file="configs/network.conf"

    # Check if the configuration file exists
    if [ ! -f "$config_file" ]; then
        whiptail --title "Network Configuration" --msgbox "The configuration file $config_file does not exist. Run the script install_proxmox-1.sh first or configure manually." 15 60
        exit 1
    fi

    # Read configurations from the file
    source "$config_file"

    # Backup network interfaces file before making changes
    if [ ! -f "/etc/network/interfaces.backup" ]; then
        cp /etc/network/interfaces /etc/network/interfaces.backup
        echo -e "${green}Backup created: /etc/network/interfaces.backup${default}"
    fi

    # Display network information
    whiptail --title "Network Configuration" --msgbox "Interface Information:\n\nPhysical Interface: $INTERFACE\nIP Address: $IP_ADDRESS\nGateway: $GATEWAY" 15 60

    if ! ip link show dev "$INTERFACE" >/dev/null 2>&1; then
        whiptail --title "Network Configuration" --msgbox "The selected interface '$INTERFACE' does not exist on this host." 10 60
        exit 1
    fi

    # Use the variables read from the file or prompt for new ones if blank
    while true; do
        choice=$(whiptail --title "Network Configuration" --menu "Select an option:" 15 60 6 \
            "1" "Configure Manually" \
            "2" "Use DHCP" \
            "3" "Exit" 3>&1 1>&2 2>&3)

        case $choice in
            "1")
                # Manual configuration
                physical_interface=$(whiptail --inputbox "Enter the name of the physical interface (leave blank to keep $INTERFACE):" 10 60 "$INTERFACE" --title "Manual Configuration" 3>&1 1>&2 2>&3)
                ip_address=$(whiptail --inputbox "Enter the IP address for the bridge (leave blank to keep $IP_ADDRESS):" 10 60 "$IP_ADDRESS" --title "Manual Configuration" 3>&1 1>&2 2>&3)
                gateway=$(whiptail --inputbox "Enter the gateway for the bridge (leave blank to keep $GATEWAY):" 10 60 "$GATEWAY" --title "Manual Configuration" 3>&1 1>&2 2>&3)

                # Use the variables read or the new ones entered
                INTERFACE=${physical_interface:-$INTERFACE}
                IP_ADDRESS=${ip_address:-$IP_ADDRESS}

                if ! ip link show dev "$INTERFACE" >/dev/null 2>&1; then
                    whiptail --title "Network Configuration" --msgbox "Invalid interface '$INTERFACE'. Exiting..." 10 60
                    exit 1
                fi

                if ! validate_cidr "$IP_ADDRESS"; then
                    whiptail --title "Network Configuration" --msgbox "Invalid bridge IP/CIDR '$IP_ADDRESS'. Exiting..." 10 60
                    exit 1
                fi

                # Validate if the gateway is a valid IP address
                if [[ -n "$gateway" ]] && ! validate_ipv4 "$gateway"; then
                    whiptail --title "Network Configuration" --msgbox "Invalid gateway. Exiting..." 10 60
                    exit 1
                fi

                GATEWAY=${gateway:-$GATEWAY}

                persist_network_config "$config_file" "$INTERFACE" "$IP_ADDRESS" "$GATEWAY"

                if ! install_bridge_config "$INTERFACE" "static" "$IP_ADDRESS" "$GATEWAY"; then
                    exit 1
                fi

                whiptail --title "Network Configuration" --msgbox "The vmbr0 bridge was created successfully!" 10 60
                break
                ;;

            "2")
                # DHCP configuration

                if ! ip link show dev "$INTERFACE" >/dev/null 2>&1; then
                    whiptail --title "Network Configuration" --msgbox "Invalid interface '$INTERFACE'. Exiting..." 10 60
                    exit 1
                fi

                if ! confirm_dhcp_selection; then
                    continue
                fi

                persist_network_config "$config_file" "$INTERFACE" "$IP_ADDRESS" "$GATEWAY"

                if ! install_bridge_config "$INTERFACE" "dhcp" "$IP_ADDRESS" "$GATEWAY"; then
                    exit 1
                fi

                whiptail --title "Network Configuration" --msgbox "The vmbr0 bridge was configured with DHCP." 10 60
                break
                ;;

            "3")
                whiptail --title "Network Configuration" --msgbox "You can configure the vmbr0 bridge later by running the script /proxmox-debian13/scripts/configure_bridge.sh, manually, or through the Proxmox web interface. Refer to the Proxmox documentation for more information." 15 60
                exit 0
                ;;

            *)
                whiptail --title "Network Configuration" --msgbox "Invalid option" 10 60
                ;;
        esac
    done

    if ! should_apply_network_now; then
        cleanup_network_backups "$NETWORK_FILE_BACKUPS_DIR"
        NETWORK_FILE_BACKUPS_DIR=""
        show_deferred_apply_message
        return 0
    fi

    whiptail --title "Network Configuration" --msgbox "Restarting the network service to apply the changes...\n\nWARNING: This may temporarily disconnect your network.\nIf you lose connection, you can restore the backup at:\n/etc/network/interfaces.backup" 15 60

    if ! apply_network_changes; then
        if [ -n "$NETWORK_FILE_BACKUPS_DIR" ]; then
            restore_network_backups "$NETWORK_FILE_BACKUPS_DIR"
        else
            cp /etc/network/interfaces.backup /etc/network/interfaces
        fi
        apply_network_changes >/dev/null 2>&1 || true
        whiptail --title "Network Configuration ERROR" --msgbox "ERROR: Failed to apply networking changes.\n\nThe previous /etc/network/interfaces backup has been restored.\nPlease review the configuration manually." 15 60
        exit 1
    fi

    cleanup_network_backups "$NETWORK_FILE_BACKUPS_DIR"
    NETWORK_FILE_BACKUPS_DIR=""

    if ! ip link set dev vmbr0 up; then
        whiptail --title "Network Configuration ERROR" --msgbox "WARNING: Failed to bring up vmbr0 interface!\n\nThe bridge was created but may need manual configuration.\nPlease check with: ip addr show vmbr0" 15 60
    else
        whiptail --title "Network Configuration" --msgbox "SUCCESS: The vmbr0 bridge was created and activated!\n\nYou can verify with: ip addr show vmbr0" 10 60
    fi
}

configurar_bridge()
{
   config_file="configs/network.conf"

    # Verificar se o arquivo de configuração existe
    if [ ! -f "$config_file" ]; then
        whiptail --title "Configuração de Rede" --msgbox "O arquivo de configuração $config_file não existe. Execute o script install_proxmox-1.sh primeiro ou configure manualmente." 15 60
        exit 1
    fi

    # Ler as configurações do arquivo
    source "$config_file"

    # Fazer backup do arquivo de interfaces de rede antes de fazer alterações
    if [ ! -f "/etc/network/interfaces.backup" ]; then
        cp /etc/network/interfaces /etc/network/interfaces.backup
        echo -e "${green}Backup criado: /etc/network/interfaces.backup${default}"
    fi

    # Exibindo informações de rede
    whiptail --title "Configuração de Rede" --msgbox "Informações da Interface:\n\nInterface Física: $INTERFACE\nEndereço IP: $IP_ADDRESS\nGateway: $GATEWAY" 15 60

    if ! ip link show dev "$INTERFACE" >/dev/null 2>&1; then
        whiptail --title "Configuração de Rede" --msgbox "A interface selecionada '$INTERFACE' não existe neste host." 10 60
        exit 1
    fi

    # Utilizar as variáveis lidas do arquivo ou solicitar novas se estiverem em branco
    while true; do
        choice=$(whiptail --title "Configuração de Rede" --menu "Selecione uma opção:" 15 60 6 \
            "1" "Configurar Manualmente" \
            "2" "Usar DHCP" \
            "3" "Sair" 3>&1 1>&2 2>&3)

        case $choice in
            "1")
                # Leitura manual das configurações
                interface_fisica=$(whiptail --inputbox "Informe o nome da interface física (deixe em branco para manter $INTERFACE):" 10 60 "$INTERFACE" --title "Configuração Manual" 3>&1 1>&2 2>&3)
                endereco_ip=$(whiptail --inputbox "Informe o endereço IP para a bridge (deixe em branco para manter $IP_ADDRESS):" 10 60 "$IP_ADDRESS" --title "Configuração Manual" 3>&1 1>&2 2>&3)
                gateway=$(whiptail --inputbox "Informe o gateway para a bridge (deixe em branco para manter $GATEWAY):" 10 60 "$GATEWAY" --title "Configuração Manual" 3>&1 1>&2 2>&3)

                # Utilizar as variáveis lidas ou as novas informadas
                INTERFACE=${interface_fisica:-$INTERFACE}
                IP_ADDRESS=${endereco_ip:-$IP_ADDRESS}

                if ! ip link show dev "$INTERFACE" >/dev/null 2>&1; then
                    whiptail --title "Configuração de Rede" --msgbox "Interface inválida '$INTERFACE'. Saindo..." 10 60
                    exit 1
                fi

                if ! validate_cidr "$IP_ADDRESS"; then
                    whiptail --title "Configuração de Rede" --msgbox "IP/CIDR inválido para a bridge: '$IP_ADDRESS'. Saindo..." 10 60
                    exit 1
                fi

                # Validar se o gateway é um endereço IP válido
                if [[ -n "$gateway" ]] && ! validate_ipv4 "$gateway"; then
                    whiptail --title "Configuração de Rede" --msgbox "Gateway inválido. Saindo..." 10 60
                    exit 1
                fi

                GATEWAY=${gateway:-$GATEWAY}

                persist_network_config "$config_file" "$INTERFACE" "$IP_ADDRESS" "$GATEWAY"

                if ! install_bridge_config "$INTERFACE" "static" "$IP_ADDRESS" "$GATEWAY"; then
                    exit 1
                fi

                whiptail --title "Configuração de Rede" --msgbox "A bridge vmbr0 foi criada com sucesso!" 10 60
                break
                ;;

            "2")
                # Configuração para DHCP

                if ! ip link show dev "$INTERFACE" >/dev/null 2>&1; then
                    whiptail --title "Configuração de Rede" --msgbox "Interface inválida '$INTERFACE'. Saindo..." 10 60
                    exit 1
                fi

                if ! confirm_dhcp_selection; then
                    continue
                fi

                persist_network_config "$config_file" "$INTERFACE" "$IP_ADDRESS" "$GATEWAY"

                if ! install_bridge_config "$INTERFACE" "dhcp" "$IP_ADDRESS" "$GATEWAY"; then
                    exit 1
                fi

                whiptail --title "Configuração de Rede" --msgbox "A bridge vmbr0 foi configurada com DHCP." 10 60
                break
                ;;

            "3")
                whiptail --title "Configuração de Rede" --msgbox "Você pode configurar a bridge vmbr0 posteriormente executando o script /proxmox-debian13/scripts/configure_bridge.sh, manualmente ou através da interface web do Proxmox. Consulte a documentação do Proxmox para mais informações." 15 60
                exit 0
                ;;

            *)
                whiptail --title "Configuração de Rede" --msgbox "Opção inválida" 10 60
                ;;
        esac
    done

    if ! should_apply_network_now; then
        cleanup_network_backups "$NETWORK_FILE_BACKUPS_DIR"
        NETWORK_FILE_BACKUPS_DIR=""
        show_deferred_apply_message
        return 0
    fi

    whiptail --title "Configuração de Rede" --msgbox "Reiniciando o serviço de rede para aplicar as alterações...\n\nAVISO: Isso pode desconectar sua rede temporariamente.\nSe perder a conexão, você pode restaurar o backup em:\n/etc/network/interfaces.backup" 15 60

    if ! apply_network_changes; then
        if [ -n "$NETWORK_FILE_BACKUPS_DIR" ]; then
            restore_network_backups "$NETWORK_FILE_BACKUPS_DIR"
        else
            cp /etc/network/interfaces.backup /etc/network/interfaces
        fi
        apply_network_changes >/dev/null 2>&1 || true
        whiptail --title "ERRO na Configuração de Rede" --msgbox "ERRO: Falha ao aplicar alterações de rede.\n\nO backup anterior de /etc/network/interfaces foi restaurado.\nRevise a configuração manualmente." 15 60
        exit 1
    fi

    cleanup_network_backups "$NETWORK_FILE_BACKUPS_DIR"
    NETWORK_FILE_BACKUPS_DIR=""

    if ! ip link set dev vmbr0 up; then
        whiptail --title "ERRO na Configuração de Rede" --msgbox "AVISO: Falha ao ativar interface vmbr0!\n\nA bridge foi criada mas pode precisar de configuração manual.\nVerifique com: ip addr show vmbr0" 15 60
    else
        whiptail --title "Configuração de Rede" --msgbox "SUCESSO: A bridge vmbr0 foi criada e ativada!\n\nVocê pode verificar com: ip addr show vmbr0" 10 60
    fi
}

remove_start_script() 
{
    # Remove script initialization along with the system // Remover inicialização do script junto com o sistema
    for user_home in /home/*; do
        PROFILE_FILE="$user_home/.bashrc"

        # Remove the script line from the profile file
        sed -i '/^# Run script after login$/,/^# End of bridge script$/d' "$PROFILE_FILE"
        echo -e "${blue}Removed configuration from the profile for user:${cyan} $(basename "$user_home").${normal}"
    done

    # Remove the lines added to /root/.bashrc
    sed -i '/^# Run script after login$/,/^# End of bridge script$/d' /root/.bashrc
    echo -e "${blue}Removed automatic script configuration from /root/.bashrc.${normal}"
}

main()
{
    super_user

    if is_ssh_autorun; then
        show_ssh_autorun_message
        config_file="configs/network.conf"

        if [ ! -f "$config_file" ]; then
            if [ "$LANGUAGE" == "en" ]; then
                echo "Automatic bridge setup aborted: $config_file was not found."
            else
                echo "Configuração automática da bridge abortada: $config_file não foi encontrado."
            fi
            remove_start_script
            return 1
        fi

        source "$config_file"

        if [ ! -f "/etc/network/interfaces.backup" ]; then
            cp /etc/network/interfaces /etc/network/interfaces.backup
            echo -e "${green}Backup created: /etc/network/interfaces.backup${default}"
        fi

        if apply_saved_static_bridge_config "$config_file"; then
            show_autorun_apply_result
            remove_start_script
            return 0
        fi

        remove_start_script
        return 1
    fi

    if [ "$LANGUAGE" == "en" ]; then
        echo -e "${cyan}3rd part: Configuring bridge"
        echo -e "...${default}"
        configure_bridge
    else
        echo -e "${cyan}3ª parte: Configurando a ponte (bridge)"
        echo -e "...${default}"
        configurar_bridge
    fi

    remove_start_script
    
    if [ "$LANGUAGE" == "en" ]; then
        clear
        whiptail --title "Installation Completed" --msgbox "Proxmox 9 installation and network configuration completed successfully!\nRemember to configure Proxmox as needed." 15 60
        whiptail --title "Network Configuration" --msgbox "You can configure the vmbr0 bridge later by running the script /proxmox-debian13/scripts/configure_bridge.sh or through the Proxmox web interface. Refer to the Proxmox documentation for more information." 15 60
    else
        clear
        whiptail --title "Instalação Concluída" --msgbox "Instalação e configuração de rede do Proxmox 9 concluídas com sucesso!\nLembre-se de configurar o Proxmox conforme necessário." 15 60
        whiptail --title "Configuração de Rede" --msgbox "Você pode configurar a bridge vmbr0 posteriormente executando o script /proxmox-debian13/scripts/configure_bridge.sh, ou através da interface web do Proxmox. Consulte a documentação do Proxmox para mais informações." 15 60
    fi

    cd /proxmox-debian13
    ./scripts/welcome.sh
}

main
