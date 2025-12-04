#!/bin/bash

# Proxmox Setup v1.1.0
# by: Matheew Alves

cd /proxmox-debian13

# Load configs files // Carregar os arquivos de configuração
source ./configs/colors.conf
source ./configs/language.conf

install_proxmox-1() 
{
    echo -e "${cyan}Setting up Proxmox - 1st part."
    echo -e "Step 1/3: Updating /etc/hosts"
    echo -e "...${default}"

    # Get the current hostname
    current_hostname=$(hostname)

    echo -e "${blue}Current Hostname: ${cyan}"
    hostname
    echo -e "${default}"

    # Display network interfaces using Whiptail
    config_dir="./configs"
    config_file="$config_dir/network.conf"

    if [ ! -d "$config_dir" ]; then
        mkdir -p "$config_dir"
    fi

    echo -e "${cyan}Select your network interface: [Enter the number]${normal}"

    # Function to display interface information
    display_interface_info() 
    {
        interface="$1"
        ip_address="$2"
        gateway="$3"

        echo -e "${blue}Interface Information ${default}$interface"
        echo -e "${blue}IP Address: ${default}$ip_address"
        echo -e "${blue}Gateway: ${default}$gateway"
    }

    # Associative array to store interface information
    declare -A interfaces

    # Populate the associative array with interface information
    while read -r interface ip_address _; do
        if [ -n "$interface" ]; then
            interfaces["$interface"]="$ip_address"
        fi
    done < <(ip addr show | awk '/inet / {split($2, a, "/"); print $NF, a[1]}')

    # Main loop
    while true; do
        # Display options to the user
        PS3="Select an option (Enter the number): "
        options=()
        for interface_option in "${!interfaces[@]}"; do
            options+=("$interface_option" "")
        done

        selected_interface=$(whiptail --title "Network Interface Selection" --menu "Select a network interface:" 15 60 6 "${options[@]}" 3>&1 1>&2 2>&3)

        if [ $? -eq 0 ]; then
            read -r ip_address <<< "$(echo "${interfaces[$selected_interface]}" | awk '{print $1}')"
            gateway="$(ip route show dev "$selected_interface" | awk '/via/ {print $3}')"
            subnet_mask="$(ip addr show dev "$selected_interface" | awk '/inet / {split($2, a, "/"); print a[2]}')"
            subnet_mask="${subnet_mask:-24}"
            ip_address_with_mask="$ip_address/$subnet_mask"

            display_interface_info "$selected_interface" "$ip_address" "$gateway"

            # Display selected interface information
            whiptail --title "Interface Information" --msgbox "Selected Interface: $selected_interface\nIP Address: $ip_address_with_mask\nGateway: $gateway" 10 60

            # Ask the user to confirm the selection
            whiptail --yesno "Do you want to select this interface?" 8 40
            case $? in
                0)
                    clear
                    echo "INTERFACE=$selected_interface" > "$config_file"
                    echo "IP_ADDRESS=$ip_address_with_mask" >> "$config_file"
                    echo "GATEWAY=$gateway" >> "$config_file"

                    echo -e "${green}Settings saved to the file ${cyan}$config_file.${default}"
                    break 2
                    ;;
                1)
                    ;;
                *)
                    echo -e "${yellow}Invalid choice. Please select again.${default}"
                    ;;
            esac
        else
            echo -e "${yellow}Please select a valid option.${default}"
        fi
    done

    echo -e "${blue}Adding or updating an entry in /etc/hosts for your IP address...${default}"

    if grep -qE "$ip_address\s+$current_hostname\.proxmox\.com\s+$current_hostname" /etc/hosts; then
        sed -i -E "s/($ip_address\s+$current_hostname\.proxmox\.com\s+$current_hostname).*/$ip_address       $current_hostname.proxmox.com $current_hostname/" /etc/hosts
        echo -e "${blue}Entry for ${cyan}'$current_hostname'${blue} has been updated in the ${cyan}/etc/hosts${blue} file.${default}"
    else 
        echo "$ip_address       $current_hostname.proxmox.com $current_hostname" | tee -a /etc/hosts > /dev/null
        echo -e "${green}Entry successfully added to the ${cyan}/etc/hosts${green} file:${normal}"
        cat /etc/hosts | grep "$current_hostname"
    fi

    echo -e "${cyan}...${default}"
}

instalar_proxmox-1() 
{
    echo -e "${cyan}Configurando o Proxmox - 1ª parte."
    echo -e "Passo 1/3: Atualizando /etc/hosts"
    echo -e "...${default}"

    # Obtendo o nome do host atual
    current_hostname=$(hostname)

    echo -e "${blue}Nome do Host Atual: ${cyan}"
    hostname
    echo -e "${default}"

    # Exibindo interfaces de rede usando o Whiptail
    config_dir="./configs"
    config_file="$config_dir/network.conf"

    if [ ! -d "$config_dir" ]; then
        mkdir -p "$config_dir"
    fi

    echo -e "${cyan}Selecione a sua interface de rede: [Digite o número]${normal}"

    # Função para exibir informações da interface
    display_interface_info() 
    {
        interface="$1"
        ip_address="$2"
        gateway="$3"

        echo -e "${blue}Informações da Interface ${default}$interface"
        echo -e "${blue}Endereço IP: ${default}$ip_address"
        echo -e "${blue}Gateway: ${default}$gateway"
    }

    # Array associativo para armazenar informações da interface
    declare -A interfaces

    # Preencher o array associativo com informações das interfaces
    while read -r interface ip_address _; do
        if [ -n "$interface" ]; then
            interfaces["$interface"]="$ip_address"
        fi
    done < <(ip addr show | awk '/inet / {split($2, a, "/"); print $NF, a[1]}')

    # Loop principal
    while true; do
        # Exibir opções para o usuário
        PS3="Selecione uma opção (Digite o número): "
        options=()
        for interface_option in "${!interfaces[@]}"; do
            options+=("$interface_option" "")
        done

        selected_interface=$(whiptail --title "Seleção de Interface de Rede" --menu "Selecione uma interface de rede:" 15 60 6 "${options[@]}" 3>&1 1>&2 2>&3)

        if [ $? -eq 0 ]; then
            read -r ip_address <<< "$(echo "${interfaces[$selected_interface]}" | awk '{print $1}')"
            gateway="$(ip route show dev "$selected_interface" | awk '/via/ {print $3}')"
            mascara_subrede="$(ip addr show dev "$selected_interface" | awk '/inet / {split($2, a, "/"); print a[2]}')"
            mascara_subrede="${mascara_subrede:-24}"
            ip_address_with_mask="$ip_address/$mascara_subrede"

            display_interface_info "$selected_interface" "$ip_address" "$gateway"

            # Exibir informações da interface selecionada
            whiptail --title "Informações da Interface" --msgbox "Interface Selecionada: $selected_interface\nEndereço IP: $ip_address_with_mask\nGateway: $gateway" 10 60

            # Perguntar ao usuário se deseja confirmar a seleção
            whiptail --yesno "Deseja selecionar esta interface?" 8 40
            case $? in
                0)
                    clear
                    echo "INTERFACE=$selected_interface" > "$config_file"
                    echo "IP_ADDRESS=$ip_address_with_mask" >> "$config_file"
                    echo "GATEWAY=$gateway" >> "$config_file"

                    echo -e "${green}Configurações salvas no arquivo ${cyan}$config_file.${default}"
                    break 2
                    ;;
                1)
                    ;;
                *)
                    echo -e "${yellow}Escolha inválida. Por favor, selecione novamente.${default}"
                    ;;
            esac
        else
            echo -e "${yellow}Por favor, selecione uma opção válida.${default}"
        fi
    done

    echo -e "${blue}Adicionando ou atualizando uma entrada em /etc/hosts para o seu endereço IP...${default}"

    if grep -qE "$ip_address\s+$current_hostname\.proxmox\.com\s+$current_hostname" /etc/hosts; then
        sed -i -E "s/($ip_address\s+$current_hostname\.proxmox\.com\s+$current_hostname).*/$ip_address       $current_hostname.proxmox.com $current_hostname/" /etc/hosts
        echo -e "${blue}Entrada para ${cyan}'$current_hostname'${blue} foi atualizada no arquivo ${cyan}/etc/hosts.${default}"
    else 
        echo "$ip_address       $current_hostname.proxmox.com $current_hostname" | tee -a /etc/hosts > /dev/null
        echo -e "${green}Entrada adicionada com sucesso ao arquivo ${cyan}/etc/hosts:${normal}"
        cat /etc/hosts | grep "$current_hostname"
    fi

    echo -e "${cyan}...${default}"
}

install_proxmox-2()
{
    if [ "$LANGUAGE" == "en" ]; then
        echo -e "${cyan}Setting up Proxmox - 1st part."
        echo -e "Step 2/3: Adding Proxmox VE Repository"
        echo -e "...${default}"
    else
        echo -e "${cyan}Configurando o Proxmox - 1ª parte."
        echo -e "Passo 2/3: Adicionando o Repositório do Proxmox VE"
        echo -e "...${default}"
    fi

    echo "deb [arch=amd64] http://download.proxmox.com/debian/pve trixie pve-no-subscription" > /etc/apt/sources.list.d/pve-install-repo.list

    # Download GPG key with error handling
    if [ "$LANGUAGE" == "en" ]; then
        echo -e "${cyan}Downloading Proxmox repository GPG key...${default}"
    else
        echo -e "${cyan}Baixando chave GPG do repositório Proxmox...${default}"
    fi

    if ! wget -q https://enterprise.proxmox.com/debian/proxmox-release-trixie.gpg -O /etc/apt/trusted.gpg.d/proxmox-release-trixie.gpg; then
        if [ "$LANGUAGE" == "en" ]; then
            echo -e "${red}CRITICAL ERROR: Failed to download Proxmox GPG key!${default}"
            echo -e "${red}Please check your internet connection and try again.${default}"
        else
            echo -e "${red}ERRO CRÍTICO: Falha ao baixar chave GPG do Proxmox!${default}"
            echo -e "${red}Verifique sua conexão com a internet e tente novamente.${default}"
        fi
        exit 1
    fi

    echo -e "${yellow}Checking Key...${default}"

    # Calculate the hash of the key
    key_hash=$(sha512sum /etc/apt/trusted.gpg.d/proxmox-release-trixie.gpg | cut -d ' ' -f1)

    # Check if the key is empty
    if [ -z "$key_hash" ]; then
        if [ "$LANGUAGE" == "en" ]; then
            echo -e "${red}CRITICAL ERROR: The GPG key is empty or invalid!${default}"
            echo -e "${red}Proxmox installation cannot continue. Aborting...${default}"
        else
            echo -e "${red}ERRO CRÍTICO: A chave GPG está vazia ou inválida!${default}"
            echo -e "${red}A instalação do Proxmox não pode continuar. Abortando...${default}"
        fi
        exit 1
    else
        echo -e "${green}Success: The key is valid.${default}"
    fi

    # Update and upgrade system with error handling
    if [ "$LANGUAGE" == "en" ]; then
        echo -e "${cyan}Updating system packages...${default}"
    else
        echo -e "${cyan}Atualizando pacotes do sistema...${default}"
    fi

    if command -v nala &> /dev/null; then
        # Use nala if installed
        if ! nala update; then
            if [ "$LANGUAGE" == "en" ]; then
                echo -e "${red}CRITICAL ERROR: Failed to update package lists!${default}"
                echo -e "${red}Please check your internet connection and repository configuration.${default}"
            else
                echo -e "${red}ERRO CRÍTICO: Falha ao atualizar listas de pacotes!${default}"
                echo -e "${red}Verifique sua conexão e configuração dos repositórios.${default}"
            fi
            exit 1
        fi

        if ! nala upgrade -y; then
            if [ "$LANGUAGE" == "en" ]; then
                echo -e "${yellow}WARNING: System upgrade had some issues, but continuing...${default}"
            else
                echo -e "${yellow}AVISO: Atualização do sistema teve problemas, mas continuando...${default}"
            fi
        fi
    else
        # Use apt-get if nala is not installed
        if ! apt-get update; then
            if [ "$LANGUAGE" == "en" ]; then
                echo -e "${red}CRITICAL ERROR: Failed to update package lists!${default}"
                echo -e "${red}Please check your internet connection and repository configuration.${default}"
            else
                echo -e "${red}ERRO CRÍTICO: Falha ao atualizar listas de pacotes!${default}"
                echo -e "${red}Verifique sua conexão e configuração dos repositórios.${default}"
            fi
            exit 1
        fi

        if ! apt-get -y full-upgrade; then
            if [ "$LANGUAGE" == "en" ]; then
                echo -e "${yellow}WARNING: System upgrade had some issues, but continuing...${default}"
            else
                echo -e "${yellow}AVISO: Atualização do sistema teve problemas, mas continuando...${default}"
            fi
        fi
    fi

    echo -e "${cyan}...${default}"
}

install_proxmox-3()
{
    if [ "$LANGUAGE" == "en" ]; then
        echo -e "${cyan}Setting up Proxmox - 1st part."
        echo -e "Step 3/3: Downloading Proxmox VE Kernel..."
        echo -e "...${default}"
    else
        echo -e "${cyan}Configurando o Proxmox - 1ª parte."
        echo -e "Passo 3/3: Baixando o Kernel do Proxmox VE..."
        echo -e "...${default}"
    fi

    # Install Proxmox kernel with error handling
    if command -v nala &> /dev/null; then
        # Use nala if installed
        if ! nala install -y proxmox-default-kernel; then
            if [ "$LANGUAGE" == "en" ]; then
                echo -e "${red}CRITICAL ERROR: Failed to install Proxmox kernel!${default}"
                echo -e "${red}Installation cannot continue. Please check the error messages above.${default}"
                echo -e "${yellow}You may need to:"
                echo -e "  1. Check your internet connection"
                echo -e "  2. Run: nala update"
                echo -e "  3. Run: nala install -f"
                echo -e "  4. Try running this script again${default}"
            else
                echo -e "${red}ERRO CRÍTICO: Falha ao instalar kernel do Proxmox!${default}"
                echo -e "${red}A instalação não pode continuar. Verifique as mensagens de erro acima.${default}"
                echo -e "${yellow}Você pode precisar:"
                echo -e "  1. Verificar sua conexão com a internet"
                echo -e "  2. Executar: nala update"
                echo -e "  3. Executar: nala install -f"
                echo -e "  4. Tentar executar este script novamente${default}"
            fi
            exit 1
        fi
    else
        # Use apt-get if nala is not installed
        if ! apt-get install -y proxmox-default-kernel; then
            if [ "$LANGUAGE" == "en" ]; then
                echo -e "${red}CRITICAL ERROR: Failed to install Proxmox kernel!${default}"
                echo -e "${red}Installation cannot continue. Please check the error messages above.${default}"
                echo -e "${yellow}You may need to:"
                echo -e "  1. Check your internet connection"
                echo -e "  2. Run: apt-get update"
                echo -e "  3. Run: apt-get install -f"
                echo -e "  4. Try running this script again${default}"
            else
                echo -e "${red}ERRO CRÍTICO: Falha ao instalar kernel do Proxmox!${default}"
                echo -e "${red}A instalação não pode continuar. Verifique as mensagens de erro acima.${default}"
                echo -e "${yellow}Você pode precisar:"
                echo -e "  1. Verificar sua conexão com a internet"
                echo -e "  2. Executar: apt-get update"
                echo -e "  3. Executar: apt-get install -f"
                echo -e "  4. Tentar executar este script novamente${default}"
            fi
            exit 1
        fi
    fi

    if [ "$LANGUAGE" == "en" ]; then
        echo -e "${green}Installation of Proxmox 1st Part completed successfully!${default}"
    else
        echo -e "${green}Instalação da 1ª Parte do Proxmox concluída com sucesso!${default}"
    fi
}

reboot_setup()
{
    if [ "$LANGUAGE" == "en" ]; then
        echo -e "${yellow}The 2nd Part of the installation will commence after the next reboot."
        # Display warning message about reboot
        echo -e "${red}WARNING: ${yellow}The system needs to be rebooted. Saving work...${normal}"
    else
        echo -e "${yellow}A 2ª parte da instalação será iniciada após o próximo reboot."
        # Exibir mensagem de aviso sobre o reboot
        echo -e "${red}ATENÇÃO: ${yellow}O sistema precisa ser reiniciado. Salvando o trabalho...${normal}"
    fi

   # Add script execution to user profiles
    for user_home in /home/*; do
        PROFILE_FILE="$user_home/.bashrc"

        # Check if the profile file exists before adding
        if [ -f "$PROFILE_FILE" ]; then
            # Add the script execution line at the end of the file
            echo "" >> "$PROFILE_FILE"
            echo "# Execute script after login" >> "$PROFILE_FILE"
            echo "/proxmox-debian13/scripts/install_proxmox-2.sh" >> "$PROFILE_FILE"
            echo "" >> "$PROFILE_FILE"

            echo "Automatic configuration completed for user: $(basename "$user_home")."
        fi
    done

    # Add the following lines at the end of the /root/.bashrc file
    echo "" >> /root/.bashrc
    echo "# Execute script after login" >> /root/.bashrc
    echo "/proxmox-debian13/scripts/install_proxmox-2.sh" >> /root/.bashrc
    echo "" >> /root/.bashrc

    echo "Automatic configuration completed for the root user."

    if [ "$LANGUAGE" == "en" ]; then
        # Enable the service to start on boot
        echo -e "${green}Work Saved!${cyan}"
        echo -e "Rebooting the system automatically to complete the installation..."
        echo -e "${yellow}Login as the '${cyan}root${yellow}' user after the reboot!${default}"
    else
        # Habilitar o serviço para iniciar com o sistema
        echo -e "${green}Trabalho Salvo!${cyan}"
        echo -e "Reiniciando o sistema automaticamente para concluir a instalação..."
        echo -e "${yellow}Faça login como usuário '${cyan}root${yellow}' após o reboot!${default}"
    fi

    # Wait for a few seconds before rebooting
    sleep 5

    # Reboot the system
    systemctl reboot
}

main()
{
    if [ "$LANGUAGE" == "en" ]; then
        # Proxmox Installation
        echo -e "${cyan}Initiating installation of the 1st Part of Proxmox setup${default}"
        install_proxmox-1
    else
        # Instalação do Proxmox
        echo -e "${cyan}iniciando a instalação da 1ºParte do setup do Proxmox${default}"
        instalar_proxmox-1
    fi 

    install_proxmox-2
    install_proxmox-3
    reboot_setup
}

main