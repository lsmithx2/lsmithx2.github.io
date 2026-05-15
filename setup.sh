#!/bin/bash

# =================================================================
# LSmithx2 - SSH Key Management Utility (Remote Edition)
# =================================================================
MY_KEY="ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQDIkafINO1G+nXCz8MWCNFB4W3ScVWnr7NMJ8GAzKKYoi/RCal+k/WN4VNjYI/RL4Rb7aiLQ26qP1QpkdCbaXN1c3bcXuEc7XuiQhJ9SZR9nbxR/idu8CRJCtKX8zwiuqQLUsqHF4Bn4OZwfvVuWALwqssRfdrozJJeXxMlhUuzfwDWSv2iNO2b48lcQlxXrDFx4FGIizUDBOup/mSxBmnv/2vhz8NigGNuaV2gWbm8846sMnrEjRqqCs32rtE3VU5y/xJi3IWkJtSnjCX8U4xr7gKE5DVbK9JBKfFoJDEwJ9PpaWYG3BqqPx9OzWV3gXMdhQCSd+EijktNcyfJH6GN lsmithx2"

AUTH_FILE="$HOME/.ssh/authorized_keys"
SSH_DIR="$HOME/.ssh"

clear
echo "===================================================="
echo "          LSmithx2 SSH Deployment Tool"
echo "===================================================="
echo "Target User: $USER"
echo "Host:        $HOSTNAME"
echo "----------------------------------------------------"

# Setup directory
if [ ! -d "$SSH_DIR" ]; then
    mkdir -p "$SSH_DIR"
    chmod 700 "$SSH_DIR"
fi
touch "$AUTH_FILE"
chmod 600 "$AUTH_FILE"

echo "How would you like LSmithx2 to handle this server?"
echo ""
echo "  [1] Safe Add    - Append key to existing list"
echo "  [2] Fresh Start - Wipe existing keys and use mine only"
echo "  [3] Abort       - Exit"
echo ""

# Note: </dev/tty is required for one-liner piped execution
read -p "Selection: " choice </dev/tty

case $choice in
    1)
        if grep -qF "$MY_KEY" "$AUTH_FILE"; then
            echo -e "\n[!] LSmithx2 key is already present."
        else
            echo "$MY_KEY" >> "$AUTH_FILE"
            echo -e "\n[+] Success: Key appended."
        fi
        ;;
    2)
        echo -e "\n[!] Warning: This will remove all other access keys."
        read -p "Are you sure? (y/n): " confirm </dev/tty
        if [[ $confirm == [yY] ]]; then
            echo "$MY_KEY" > "$AUTH_FILE"
            echo "[+] Success: All old keys purged."
        else
            echo "[*] Operation cancelled."
        fi
        ;;
    3)
        echo -e "\n[*] Goodbye!"
        exit 0
        ;;
    *)
        echo -e "\n[X] Invalid entry."
        exit 1
        ;;
esac

echo "----------------------------------------------------"
echo "             Deployment Complete!"
echo "===================================================="
