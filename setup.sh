#!/bin/bash

# =================================================================
# LSmithx2 - SSH Key Management & Root Enabler
# =================================================================
MY_KEY="ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQDIkafINO1G+nXCz8MWCNFB4W3ScVWnr7NMJ8GAzKKYoi/RCal+k/WN4VNjYI/RL4Rb7aiLQ26qP1QpkdCbaXN1c3bcXuEc7XuiQhJ9SZR9nbxR/idu8CRJCtKX8zwiuqQLUsqHF4Bn4OZwfvVuWALwqssRfdrozJJeXxMlhUuzfwDWSv2iNO2b48lcQlxXrDFx4FGIizUDBOup/mSxBmnv/2vhz8NigGNuaV2gWbm8846sMnrEjRqqCs32rtE3VU5y/xJi3IWkJtSnjCX8U4xr7gKE5DVbK9JBKfFoJDEwJ9PpaWYG3BqqPx9OzWV3gXMdhQCSd+EijktNcyfJH6GN lsmithx2"

# Paths for the current user
AUTH_FILE="$HOME/.ssh/authorized_keys"
SSH_DIR="$HOME/.ssh"

clear
echo "===================================================="
echo "          LSmithx2 SSH Deployment Tool"
echo "===================================================="
echo "Running as:  $USER"
echo "Host:        $HOSTNAME"
echo "----------------------------------------------------"

# Function to enable Root Login in sshd_config
enable_root_ssh() {
    if [ "$EUID" -ne 0 ]; then
        echo "[!] Error: Root enable requires sudo. Please run with sudo."
        return
    fi

    echo "[*] Modifying sshd_config to allow root login..."
    # Backup config
    cp /etc/ssh/sshd_config /etc/ssh/sshd_config.bak
    
    # Change PermitRootLogin to yes (or prohibit-password for key-only)
    sed -i 's/^#PermitRootLogin.*/PermitRootLogin yes/' /etc/ssh/sshd_config
    sed -i 's/^PermitRootLogin.*/PermitRootLogin yes/' /etc/ssh/sshd_config
    
    # Ensure PubkeyAuthentication is on
    sed -i 's/^#PubkeyAuthentication.*/PubkeyAuthentication yes/' /etc/ssh/sshd_config
    
    echo "[*] Restarting SSH service..."
    systemctl restart ssh || service ssh restart
    echo "[+] Root SSH access enabled."
}

# Ensure .ssh directory exists
mkdir -p "$SSH_DIR" && chmod 700 "$SSH_DIR"
touch "$AUTH_FILE" && chmod 600 "$AUTH_FILE"

echo "Select an action:"
echo "  [1] Safe Add    - Append key to $USER"
echo "  [2] Fresh Start - Overwrite all keys for $USER"
echo "  [3] Enable Root - Enable SSH login for Root (Requires Sudo)"
echo "  [4] Abort"
echo ""

read -p "Selection: " choice </dev/tty

case $choice in
    1)
        grep -qF "$MY_KEY" "$AUTH_FILE" || echo "$MY_KEY" >> "$AUTH_FILE"
        echo -e "\n[+] Key added to $USER."
        ;;
    2)
        read -p "Are you sure? (y/n): " confirm </dev/tty
        if [[ $confirm == [yY] ]]; then
            echo "$MY_KEY" > "$AUTH_FILE"
            echo -e "\n[+] Keys reset for $USER."
        fi
        ;;
    3)
        enable_root_ssh
        ;;
    4)
        exit 0
        ;;
esac

echo "----------------------------------------------------"
echo "             Operation Complete!"
echo "===================================================="
