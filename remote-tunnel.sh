#!/bin/bash
# TAILORED FOR AIVEN MANAGED DB & CLOUDFLARE TUNNEL INTEGRATION

# Check if user is root or sudo
if ! [ $( id -u ) = 0 ]; then
    echo "Please run this script as sudo or root" 1>&2
    exit 1
fi

# Check to see if any old files left over
if [ "$( find . -maxdepth 1 \( -name 'guacamole-*' -o -name 'mysql-connector-java-*' \) )" != "" ]; then
    echo "Possible temp files detected. Please review 'guacamole-*' & 'mysql-connector-java-*'" 1>&2
    exit 1
fi

# Version number of Guacamole to install
GUACVERSION="1.6.0"
MCJVER="8.0.27"

# Colors to use for output
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
RED='\033[0;31m'
GREEN='\033[0;32m'
CYAN='\033[0;36m'
NC='\033[0m'

LOG="/tmp/guacamole_${GUACVERSION}_build.log"

installTOTP=""
installDuo=""
installCloudflare=""
cfToken=""
mysqlHost=""
mysqlPort=""
guacDb=""
guacUser=""
guacPwd=""
PROMPT=""

# MFA Setup Prompts
if [[ -z "${installTOTP}" ]] && [[ "${installDuo}" != true ]]; then
    echo -e -n "${CYAN}MFA: Would you like to install TOTP (choose 'N' if you want Duo)? (y/N): ${NC}"
    read PROMPT
    if [[ ${PROMPT} =~ ^[Yy]$ ]]; then
        installTOTP=true
        installDuo=false
    else
        installTOTP=false
    fi
fi

if [[ -z "${installDuo}" ]] && [[ "${installTOTP}" != true ]]; then
    echo -e -n "${CYAN}MFA: Would you like to install Duo? (y/N): ${NC}"
    read PROMPT
    if [[ ${PROMPT} =~ ^[Yy]$ ]]; then
        installDuo=true
        installTOTP=false
    else
        installDuo=false
    fi
fi

# Cloudflare Tunnel Setup Prompt
echo -e -n "${CYAN}Cloudflare: Would you like to install Cloudflare Tunnel? (y/N): ${NC}"
read PROMPT
if [[ ${PROMPT} =~ ^[Yy]$ ]]; then
    installCloudflare=true
    echo -e "${YELLOW}You will need your Cloudflare Tunnel Token from the Zero Trust Dashboard.${NC}"
    read -p "Enter Cloudflare Tunnel Token: " cfToken
else
    installCloudflare=false
fi

# Remote Database Details Gathering
echo -e "${YELLOW}\nEntering Remote / Aiven Managed Database Details:${NC}"
[ -z "${mysqlHost}" ] && read -p "Enter Managed MySQL server hostname or IP: " mysqlHost
[ -z "${mysqlPort}" ] && read -p "Enter Managed MySQL server port: " mysqlPort
[ -z "${guacDb}" ] && read -p "Enter Guacamole database name: " guacDb
[ -z "${guacUser}" ] && read -p "Enter Guacamole database user: " guacUser

if [ -z "${guacPwd}" ]; then
    while true; do
        read -s -p "Enter MySQL user password: " guacPwd
        echo
        read -s -p "Confirm MySQL user password: " PROMPT2
        echo
        [ "${guacPwd}" = "${PROMPT2}" ] && break
        echo -e "${RED}Passwords don't match. Please try again.${NC}" 1>&2
        echo
    done
fi
echo

# Package Management and Environment Check
source /etc/os-release
if [[ "${NAME}" == "Ubuntu" ]] || [[ "${NAME}" == "Linux Mint" ]]; then
    add-apt-repository -y universe
    JPEGTURBO="libjpeg-turbo8-dev"
    LIBPNG="libpng-dev"
elif [[ "${NAME}" == *"Debian"* ]] || [[ "${NAME}" == *"Raspbian GNU/Linux"* ]] || [[ "${NAME}" == *"Kali GNU/Linux"* ]] || [[ "${NAME}" == "LMDE" ]]; then
    JPEGTURBO="libjpeg62-turbo-dev"
    LIBPNG="libpng-dev"
else
    echo "Unsupported distribution."
    exit 1
fi

echo -e "${BLUE}Updating apt...${NC}"
apt-get -qq update

if [[ $( apt-cache show tomcat9 2> /dev/null | egrep "Version: 9" | wc -l ) -gt 0 ]]; then
    TOMCAT="tomcat9"
elif [[ $( apt-cache show tomcat8 2> /dev/null | egrep "Version: 8.[5-9]" | wc -l ) -gt 0 ]]; then
    TOMCAT="tomcat8"
else
    echo -e "${RED}Failed. Can't find supported Tomcat package${NC}" 1>&2
    exit 1
fi

echo -e "${BLUE}Installing dependencies...${NC}"
export DEBIAN_FRONTEND=noninteractive
apt-get -y install build-essential libcairo2-dev ${JPEGTURBO} ${LIBPNG} libossp-uuid-dev libavcodec-dev libavformat-dev libavutil-dev \
libswscale-dev freerdp2-dev libpango1.0-dev libssh2-1-dev libtelnet-dev libvncserver-dev libpulse-dev libssl-dev \
libvorbis-dev libwebp-dev libwebsockets-dev freerdp2-x11 libtool-bin ghostscript dpkg-dev wget crudini libc-bin \
${TOMCAT} &>> ${LOG}

# Download Guacamole Elements
SERVER="http://apache.org/dyn/closer.cgi?action=download&filename=guacamole/${GUACVERSION}"
wget -q -O guacamole-server-${GUACVERSION}.tar.gz ${SERVER}/source/guacamole-server-${GUACVERSION}.tar.gz && tar -xzf guacamole-server-${GUACVERSION}.tar.gz
wget -q -O guacamole-${GUACVERSION}.war ${SERVER}/binary/guacamole-${GUACVERSION}.war
wget -q -O guacamole-auth-jdbc-${GUACVERSION}.tar.gz ${SERVER}/binary/guacamole-auth-jdbc-${GUACVERSION}.tar.gz && tar -xzf guacamole-auth-jdbc-${GUACVERSION}.tar.gz
wget -q -O mysql-connector-java-${MCJVER}.tar.gz https://dev.mysql.com/get/Downloads/Connector-J/mysql-connector-java-${MCJVER}.tar.gz && tar -xzf mysql-connector-java-${MCJVER}.tar.gz

if [ "${installTOTP}" = true ]; then
    wget -q -O guacamole-auth-totp-${GUACVERSION}.tar.gz ${SERVER}/binary/guacamole-auth-totp-${GUACVERSION}.tar.gz && tar -xzf guacamole-auth-totp-${GUACVERSION}.tar.gz
fi

# Directory Structuring
mkdir -p /etc/guacamole/lib/ /etc/guacamole/extensions/ /usr/sbin/.config/freerdp /var/guacamole
chown daemon:daemon /usr/sbin/.config/freerdp /var/guacamole

# Compilation
cd guacamole-server-${GUACVERSION}/
export CFLAGS="-Wno-error"
./configure --with-systemd-dir=/etc/systemd/system &>> ${LOG}
make &>> ${LOG} && make install &>> ${LOG}
ldconfig
cd ..

# Deployment Mapping
mv -f guacamole-${GUACVERSION}.war /etc/guacamole/guacamole.war
mv -f guacamole-auth-jdbc-${GUACVERSION}/mysql/guacamole-auth-jdbc-mysql-${GUACVERSION}.jar /etc/guacamole/extensions/
ln -sf /etc/guacamole/guacamole.war /var/lib/${TOMCAT}/webapps/
mv -f mysql-connector-java-${MCJVER}/mysql-connector-java-${MCJVER}.jar /etc/guacamole/lib/mysql-connector-java.jar

if [ "${installTOTP}" = true ]; then
    mv -f guacamole-auth-totp-${GUACVERSION}/guacamole-auth-totp-${GUACVERSION}.jar /etc/guacamole/extensions/
fi

# Config Generations
cat > /etc/guacamole/guacamole.properties << EOF
mysql-hostname: ${mysqlHost}
mysql-port: ${mysqlPort}
mysql-database: ${guacDb}
mysql-username: ${guacUser}
mysql-password: ${guacPwd}
mysql-ssl-mode: required
EOF

cat > /etc/guacamole/guacd.conf << EOF
[server]
bind_host = 127.0.0.1
bind_port = 4822
EOF

# Restart Core Daemons
service ${TOMCAT} restart && systemctl enable ${TOMCAT}
service guacd stop 2>/dev/null && service guacd start && systemctl enable guacd

# ==========================================
# NEW: CLOUDFLARE TUNNEL DEPLOYMENT ZONE
# ==========================================
if [ "${installCloudflare}" = true ] && [ ! -z "${cfToken}" ]; then
    echo -e "${BLUE}\nInstalling Cloudflare Tunnel client (cloudflared)...${NC}"
    
    # 1. Download official Cloudflare deb package repository setup
    mkdir -p --mode=0755 /etc/apt/keyrings
    wget -qO- https://pkg.cloudflare.com/cloudflare-main.gpg | tee /etc/apt/keyrings/cloudflare-main.gpg >/dev/null
    echo "deb [signed-by=/etc/apt/keyrings/cloudflare-main.gpg] https://pkg.cloudflare.com/cloudflare-main.gpg stable main" | tee /etc/apt/sources.list.d/cloudflare-main.list
    
    # 2. Install cloudflared
    apt-get update && apt-get install -y cloudflared &>> ${LOG}
    
    # 3. Install tunnel runtime as a background systemd service using your token
    echo -e "${BLUE}Registering cloudflared service with your secure token...${NC}"
    cloudflared service install "$cfToken" &>> ${LOG}
    
    # 4. Start up the tunnel service
    systemctl start cloudflared
    systemctl enable cloudflared
    echo -e "${GREEN}Cloudflare Tunnel service is active and running at boot!${NC}"
else
    # Fallback traditional firewall hole if tunnel is bypassed
    if [ -x "$( command -v ufw )" ] && [[ $(ufw status | grep inactive | wc -l) -eq 0 ]]; then
        ufw allow 8080/tcp comment 'allow tomcat fallback'
    fi
fi

# Cleanup build workspace
rm -rf guacamole-* mysql-connector-java-*

echo -e "${GREEN}\nDeployment Complete!${NC}"
if [ "${installCloudflare}" = true ]; then
    echo -e "Your local ports are secured. Route your Tunnel hostname to: ${CYAN}http://localhost:8080/guacamole/${NC} inside the Cloudflare Zero Trust Console."
else
    echo -e "- Visit: http://localhost:8080/guacamole/"
fi
