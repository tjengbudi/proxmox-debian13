#!/bin/bash

# Proxmox Setup v1.1.0
# by: Matheew Alves

cd /proxmox-debian13

# Load configs files // Carregar os arquivos de configuração
source ./configs/colors.conf
source ./configs/language.conf

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

# Remove script initialization along with the system // Remover inicialização do script junto com o sistema
remove_start_script() 
{
    for user_home in /home/*; do
        PROFILE_FILE="$user_home/.bashrc"
        
        # Remove the script line from the profile file
        sed -i '/# Execute script after login/,/# End of script 2/d' "$PROFILE_FILE"
        echo -e "${blue}Removed profile configuration for user:${cyan} $(basename "$user_home").${normal}"

        # Remove the lines added to /root/.bashrc
        sed -i '/# Execute script after login/,/\/proxmox-debian13\/scripts\/install_proxmox-2.sh/d' /root/.bashrc
        echo -e "${blue}Removed automatic script configuration in /root/.bashrc.${normal}"
    done
}

# Start bridge configuration after reboot // Iniciar configuração da bridge após o reboot
configure_bridge()
{
    for user_home in /home/*; do
        PROFILE_FILE="$user_home/.bashrc"

        # Check if the profile file exists before adding
        if [ -f "$PROFILE_FILE" ]; then
            # Add the script execution line at the end of the file
            echo -e "\n# Run script after login" >> "$PROFILE_FILE"
            echo "/proxmox-debian13/scripts/configure_bridge.sh" >> "$PROFILE_FILE"

            echo "Automatic configuration completed for user: $(basename "$user_home")."
        fi
    done

    # Add the following lines at the end of the /root/.bashrc file
    echo -e "\n# Run script after login" >> /root/.bashrc
    echo "/proxmox-debian13/scripts/configure_bridge.sh" >> /root/.bashrc

    echo "Automatic configuration completed for the root user."
}


proxmox-ve_packages()
{
    if [ "$LANGUAGE" == "en" ]; then
        echo -e "${cyan}Setting up Proxmox 2nd part."
        echo -e "Step 1/3: Proxmox VE packages"
        echo -e "...${default}"
    else
        echo -e "${cyan}Configurando a 2ª parte do Proxmox."
        echo -e "Passo 1/3: Pacotes do Proxmox VE"
        echo -e "...${default}"
    fi

    # Update package lists and fix any broken dependencies first
    if [ "$LANGUAGE" == "en" ]; then
        echo -e "${yellow}Updating package lists and fixing dependencies...${default}"
    else
        echo -e "${yellow}Atualizando listas de pacotes e corrigindo dependências...${default}"
    fi

    if command -v nala &> /dev/null; then
        # Use nala if installed
        nala update
        dpkg --configure -a

        # Install packages using nala
        if [ "$LANGUAGE" == "en" ]; then
            echo -e "${cyan}Installing Proxmox VE and required packages with nala...${default}"
        else
            echo -e "${cyan}Instalando Proxmox VE e pacotes necessários com nala...${default}"
        fi

        if ! nala install -y proxmox-ve postfix open-iscsi chrony; then
            if [ "$LANGUAGE" == "en" ]; then
                echo -e "${red}CRITICAL ERROR: Failed to install Proxmox VE packages!${default}"
                echo -e "${red}Installation cannot continue. Please check the error messages above.${default}"
                echo -e "${yellow}Common solutions:"
                echo -e "  1. Check your internet connection"
                echo -e "  2. Check repository configuration in /etc/apt/sources.list.d/"
                echo -e "  3. Run: nala update"
                echo -e "  4. Check for held packages: dpkg --get-selections | grep hold${default}"
            else
                echo -e "${red}ERRO CRÍTICO: Falha ao instalar pacotes do Proxmox VE!${default}"
                echo -e "${red}A instalação não pode continuar. Verifique as mensagens de erro acima.${default}"
                echo -e "${yellow}Soluções comuns:"
                echo -e "  1. Verificar conexão com a internet"
                echo -e "  2. Verificar configuração dos repositórios em /etc/apt/sources.list.d/"
                echo -e "  3. Executar: nala update"
                echo -e "  4. Verificar pacotes retidos: dpkg --get-selections | grep hold${default}"
            fi
            exit 1
        fi
    else
        # Use apt-get if nala is not installed
        apt-get update
        apt-get install -f -y
        dpkg --configure -a

        # Install packages using apt-get
        if [ "$LANGUAGE" == "en" ]; then
            echo -e "${cyan}Installing Proxmox VE and required packages...${default}"
        else
            echo -e "${cyan}Instalando Proxmox VE e pacotes necessários...${default}"
        fi

        if ! DEBIAN_FRONTEND=noninteractive apt-get install -y -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold" \
            proxmox-ve \
            postfix \
            open-iscsi \
            chrony; then
            if [ "$LANGUAGE" == "en" ]; then
                echo -e "${red}Error: Package installation failed. Trying to fix dependencies...${default}"
            else
                echo -e "${red}Erro: Instalação de pacotes falhou. Tentando corrigir dependências...${default}"
            fi

            apt-get install -f -y

            # Retry installation
            if ! DEBIAN_FRONTEND=noninteractive apt-get install -y -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold" \
                proxmox-ve \
                postfix \
                open-iscsi \
                chrony; then
                if [ "$LANGUAGE" == "en" ]; then
                    echo -e "${red}CRITICAL ERROR: Failed to install Proxmox VE packages!${default}"
                    echo -e "${red}Installation cannot continue. Please check the error messages above.${default}"
                    echo -e "${yellow}Common solutions:"
                    echo -e "  1. Check your internet connection"
                    echo -e "  2. Check repository configuration in /etc/apt/sources.list.d/"
                    echo -e "  3. Run: apt-get update"
                    echo -e "  4. Run: apt-get install -f"
                    echo -e "  5. Check for held packages: dpkg --get-selections | grep hold${default}"
                else
                    echo -e "${red}ERRO CRÍTICO: Falha ao instalar pacotes do Proxmox VE!${default}"
                    echo -e "${red}A instalação não pode continuar. Verifique as mensagens de erro acima.${default}"
                    echo -e "${yellow}Soluções comuns:"
                    echo -e "  1. Verificar conexão com a internet"
                    echo -e "  2. Verificar configuração dos repositórios em /etc/apt/sources.list.d/"
                    echo -e "  3. Executar: apt-get update"
                    echo -e "  4. Executar: apt-get install -f"
                    echo -e "  5. Verificar pacotes retidos: dpkg --get-selections | grep hold${default}"
                fi
                exit 1
            fi
        fi
    fi

    if [ "$LANGUAGE" == "en" ]; then
        echo -e "${green}Proxmox VE packages installed successfully!${default}"
    else
        echo -e "${green}Pacotes do Proxmox VE instalados com sucesso!${default}"
    fi
}

# Remove Debian kernel // Remover kernel do Debian
remove_kernel()
{
    if [ "$LANGUAGE" == "en" ]; then
        echo -e "${cyan}Setting up Proxmox 2nd part."
        echo -e "Step 2/3: Removing old kernel"
        echo -e "...${default}"
    else
        echo -e "${cyan}Configurando a 2ª parte do Proxmox."
        echo -e "Passo 2/3: Removendo o kernel antigo"
        echo -e "...${default}"
    fi

    # Check if Proxmox kernel is installed before removing old kernel
    if ! dpkg -l | grep -q "proxmox-kernel"; then
        if [ "$LANGUAGE" == "en" ]; then
            echo -e "${red}WARNING: Proxmox kernel not detected!${default}"
            echo -e "${yellow}Skipping removal of old kernel for safety.${default}"
            echo -e "${yellow}You can manually remove it later after verifying Proxmox kernel is working.${default}"
        else
            echo -e "${red}AVISO: Kernel do Proxmox não detectado!${default}"
            echo -e "${yellow}Pulando remoção do kernel antigo por segurança.${default}"
            echo -e "${yellow}Você pode removê-lo manualmente depois de verificar que o kernel do Proxmox está funcionando.${default}"
        fi
        return 0
    fi

    # Remove old Debian kernel
    if [ "$LANGUAGE" == "en" ]; then
        echo -e "${yellow}Removing old Debian kernel...${default}"
    else
        echo -e "${yellow}Removendo kernel antigo do Debian...${default}"
    fi

    if command -v nala &> /dev/null; then
        # Use nala if installed
        if ! nala remove -y linux-image-amd64 'linux-image-6.12*'; then
            if [ "$LANGUAGE" == "en" ]; then
                echo -e "${yellow}WARNING: Failed to remove old kernel. This is not critical.${default}"
                echo -e "${yellow}You can manually remove it later with: nala remove linux-image-amd64${default}"
            else
                echo -e "${yellow}AVISO: Falha ao remover kernel antigo. Isso não é crítico.${default}"
                echo -e "${yellow}Você pode removê-lo manualmente depois com: nala remove linux-image-amd64${default}"
            fi
        fi
    else
        # Use apt-get if nala is not installed
        if ! apt-get remove -y linux-image-amd64 'linux-image-6.12*'; then
            if [ "$LANGUAGE" == "en" ]; then
                echo -e "${yellow}WARNING: Failed to remove old kernel. This is not critical.${default}"
                echo -e "${yellow}You can manually remove it later with: apt-get remove linux-image-amd64${default}"
            else
                echo -e "${yellow}AVISO: Falha ao remover kernel antigo. Isso não é crítico.${default}"
                echo -e "${yellow}Você pode removê-lo manualmente depois com: apt-get remove linux-image-amd64${default}"
            fi
        fi
    fi

    # Update grub
    if [ "$LANGUAGE" == "en" ]; then
        echo -e "${cyan}Updating GRUB bootloader...${default}"
    else
        echo -e "${cyan}Atualizando o carregador de boot GRUB...${default}"
    fi

    if ! update-grub; then
        if [ "$LANGUAGE" == "en" ]; then
            echo -e "${red}WARNING: Failed to update GRUB!${default}"
            echo -e "${yellow}You may need to run 'update-grub' manually before rebooting.${default}"
        else
            echo -e "${red}AVISO: Falha ao atualizar GRUB!${default}"
            echo -e "${yellow}Você pode precisar executar 'update-grub' manualmente antes de reiniciar.${default}"
        fi
    fi
}

remove_os-prober()
{
    if [ "$LANGUAGE" == "en" ]; then
        echo -e "${cyan}Setting up Proxmox 2nd part."
        echo -e "Step 3/3: Removing os-prober"
        echo -e "...${default}"
    else
        echo -e "${cyan}Configurando a 2ª parte do Proxmox."
        echo -e "Passo 3/3: Removendo o os-prober"
        echo -e "...${default}"
    fi

    if command -v nala &> /dev/null; then
        # Execute with 'nala' if installed
        nala remove -y os-prober
    else
        # Execute with 'apt' if 'nala' is not installed
        apt remove -y os-prober
    fi
}

main()
{
    super_user
    proxmox-ve_packages
    remove_kernel
    remove_os-prober

    # Check if system info tool is installed // Verificar se a ferramenta de informações do sistema está instalada
    if command -v fastfetch &> /dev/null; then
        fastfetch
    elif command -v neofetch &> /dev/null; then
        neofetch
    fi

    if [ "$LANGUAGE" == "en" ]; then
        echo -e "${green}2º Part of ProxMox installation completed successfully!${default}" 
    else
        echo -e "${green}2º Parte da instalação do ProxMox concluída com sucesso!${default}"
    fi

    remove_start_script
    configure_bridge

    if [ "$LANGUAGE" == "en" ]; then
        echo -e "${red}WARNING: ${yellow}System automatically restarted to complete the installation..."
        echo -e "Log in as the '${cyan}root${yellow}' user after the reboot!${default}"
    else
        echo -e "${red}AVISO: ${yellow}Reiniciado o sistema automaticamente para concluir a instalação..."
        echo -e "Faça o login como usuário '${cyan}root${yellow}' após o reboot!${default}"
    fi
    sleep 5
    systemctl reboot
}

main