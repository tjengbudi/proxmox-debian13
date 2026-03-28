#!/bin/bash

# Proxmox Setup v1.1.0
# by: Matheew Alves

cd /proxmox-debian13

# Load configs files // Carregar os arquivos de configuração
source ./configs/colors.conf
source ./configs/language.conf

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
    local line
    local path
    local dir
    local candidate

    while IFS= read -r line; do
        case "$line" in
            [[:space:]]*source[[:space:]]*)
                path=$(printf '%s\n' "$line" | awk '{print $2}')
                for candidate in $path; do
                    [ -f "$candidate" ] && printf '%s\n' "$candidate"
                done
                ;;
            [[:space:]]*source-directory[[:space:]]*)
                dir=$(printf '%s\n' "$line" | awk '{print $2}')
                if [ -d "$dir" ]; then
                    find "$dir" -maxdepth 1 -type f ! -name '.*' | sort
                fi
                ;;
        esac
    done < /etc/network/interfaces
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

rewrite_interfaces_file()
{
    local iface="$1"
    local mode="$2"
    local ip_cidr="$3"
    local gw="$4"
    local source_file="$5"
    local output_file="$6"

    awk -v iface="$iface" -v bridge="vmbr0" '
        function is_target(name) {
            return name == iface || name == bridge
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

    NETWORK_TARGET_FILE="$target_file"
    NETWORK_TARGET_FILE_BACKUP="$(mktemp)"
    cp "$target_file" "$NETWORK_TARGET_FILE_BACKUP"

    mv "$temp_file" "$target_file"
    chmod 644 "$target_file"
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

    # Restart the network service to apply the changes
    if [ -n "$SSH_CONNECTION" ]; then
        whiptail --title "Network Configuration" --msgbox "WARNING: This session is running over SSH.\nApplying bridge changes may disconnect your remote session.\nA backup is available at /etc/network/interfaces.backup." 12 60
    fi

    whiptail --title "Network Configuration" --msgbox "Restarting the network service to apply the changes...\n\nWARNING: This may temporarily disconnect your network.\nIf you lose connection, you can restore the backup at:\n/etc/network/interfaces.backup" 15 60

    if ! apply_network_changes; then
        if [ -n "$NETWORK_TARGET_FILE_BACKUP" ] && [ -f "$NETWORK_TARGET_FILE_BACKUP" ]; then
            cp "$NETWORK_TARGET_FILE_BACKUP" "$NETWORK_TARGET_FILE"
        else
            cp /etc/network/interfaces.backup /etc/network/interfaces
        fi
        apply_network_changes >/dev/null 2>&1 || true
        whiptail --title "Network Configuration ERROR" --msgbox "ERROR: Failed to apply networking changes.\n\nThe previous /etc/network/interfaces backup has been restored.\nPlease review the configuration manually." 15 60
        exit 1
    fi

    rm -f "$NETWORK_TARGET_FILE_BACKUP"

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

    # Reiniciar o serviço de rede para aplicar as alterações
    if [ -n "$SSH_CONNECTION" ]; then
        whiptail --title "Configuração de Rede" --msgbox "AVISO: Esta sessão está rodando via SSH.\nAplicar alterações da bridge pode desconectar sua sessão remota.\nHá um backup em /etc/network/interfaces.backup." 12 60
    fi

    whiptail --title "Configuração de Rede" --msgbox "Reiniciando o serviço de rede para aplicar as alterações...\n\nAVISO: Isso pode desconectar sua rede temporariamente.\nSe perder a conexão, você pode restaurar o backup em:\n/etc/network/interfaces.backup" 15 60

    if ! apply_network_changes; then
        if [ -n "$NETWORK_TARGET_FILE_BACKUP" ] && [ -f "$NETWORK_TARGET_FILE_BACKUP" ]; then
            cp "$NETWORK_TARGET_FILE_BACKUP" "$NETWORK_TARGET_FILE"
        else
            cp /etc/network/interfaces.backup /etc/network/interfaces
        fi
        apply_network_changes >/dev/null 2>&1 || true
        whiptail --title "ERRO na Configuração de Rede" --msgbox "ERRO: Falha ao aplicar alterações de rede.\n\nO backup anterior de /etc/network/interfaces foi restaurado.\nRevise a configuração manualmente." 15 60
        exit 1
    fi

    rm -f "$NETWORK_TARGET_FILE_BACKUP"

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
