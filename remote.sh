#!/bin/bash
# Something isn't working? # tail -f /var/log/messages /var/log/syslog /var/log/tomcat*/*.out

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

# Latest Version of MySQL Connector/J 
MCJVER="8.0.27"

# Colors to use for output
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
RED='\033[0;31m'
GREEN='\033[0;32m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Log Location
LOG="/tmp/guacamole_${GUACVERSION}_build.log"

# Initialize variable values
installTOTP=""
installDuo=""
mysqlHost=""
mysqlPort=""
guacDb=""
guacUser=""
guacPwd=""
PROMPT=""

# Get script arguments for non-interactive mode
while [ "$1" != "" ]; do
    case $1 in
        # Remote MySQL server information
        -h | --mysqlhost )
            shift
            mysqlHost="$1"
            ;;
        -p | --mysqlport )
            shift
            mysqlPort="$1"
            ;;
        # Guac database/user information
        -db | --guacdb )
            shift
            guacDb="$1"
            ;;
        -gu | --guacuser )
            shift
            guacUser="$1"
            ;;
        -gp | --guacpwd )
            shift
            guacPwd="$1"
            ;;
        # MFA selection
        -t | --totp )
            installTOTP=true
            ;;
        -d | --duo )
            installDuo=true
            ;;
        -o | --nomfa )
            installTOTP=false
            installDuo=false
            ;;
    esac
    shift
done

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

# We need to get Aiven/Remote MySQL connection values
echo -e "${YELLOW}\nEntering Remote / Aiven Managed Database Details:${NC}"
[ -z "${mysqlHost}" ] \
  && read -p "Enter Managed MySQL server hostname or IP: " mysqlHost
[ -z "${mysqlPort}" ] \
  && read -p "Enter Managed MySQL server port: " mysqlPort
[ -z "${guacDb}" ] \
  && read -p "Enter Guacamole database name: " guacDb
[ -z "${guacUser}" ] \
  && read -p "Enter Guacamole database user: " guacUser

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

# Different version of Ubuntu/Linux Mint and Debian have different package names...
source /etc/os-release
if [[ "${NAME}" == "Ubuntu" ]] || [[ "${NAME}" == "Linux Mint" ]]; then
    add-apt-repository -y universe
    JPEGTURBO="libjpeg-turbo8-dev"
    LIBPNG="libpng-dev"
elif [[ "${NAME}" == *"Debian"* ]] || [[ "${NAME}" == *"Raspbian GNU/Linux"* ]] || [[ "${NAME}" == *"Kali GNU/Linux"* ]] || [[ "${NAME}" == "LMDE" ]]; then
    JPEGTURBO="libjpeg62-turbo-dev"
    LIBPNG="libpng-dev"
else
    echo "Unsupported distribution - Debian, Kali, Raspbian, Linux Mint or Ubuntu only"
    exit 1
fi

# Update apt to search for Tomcat version 
echo -e "${BLUE}Updating apt...${NC}"
apt-get -qq update

# Detect local Tomcat package to map the webapp directory
if [[ $( apt-cache show tomcat9 2> /dev/null | egrep "Version: 9" | wc -l ) -gt 0 ]]; then
    echo -e "${BLUE}Found tomcat9 package...${NC}"
    TOMCAT="tomcat9"
elif [[ $( apt-cache show tomcat8 2> /dev/null | egrep "Version: 8.[5-9]" | wc -l ) -gt 0 ]]; then
    echo -e "${BLUE}Found tomcat8.5+ package...${NC}"
    TOMCAT="tomcat8"
elif [[ $( apt-cache show tomcat7 2> /dev/null | egrep "Version: 7" | wc -l ) -gt 0 ]]; then
    echo -e "${BLUE}Found tomcat7 package...${NC}"
    TOMCAT="tomcat7"
else
    echo -e "${RED}Failed. Can't find Tomcat package${NC}" 1>&2
    exit 1
fi

echo -e "${BLUE}Installing required build packages...${NC}"
export DEBIAN_FRONTEND=noninteractive

# Required system packages (EXCLUDING local mysql-server packages)
apt-get -y install build-essential libcairo2-dev ${JPEGTURBO} ${LIBPNG} libossp-uuid-dev libavcodec-dev libavformat-dev libavutil-dev \
libswscale-dev freerdp2-dev libpango1.0-dev libssh2-1-dev libtelnet-dev libvncserver-dev libpulse-dev libssl-dev \
libvorbis-dev libwebp-dev libwebsockets-dev freerdp2-x11 libtool-bin ghostscript dpkg-dev wget crudini libc-bin \
${TOMCAT} &>> ${LOG}

if [ $? -ne 0 ]; then
    echo -e "${RED}Failed. See ${LOG}${NC}" 1>&2
    exit 1
else
    echo -e "${GREEN}OK${NC}"
fi
echo

SERVER="http://apache.org/dyn/closer.cgi?action=download&filename=guacamole/${GUACVERSION}"
echo -e "${BLUE}Downloading Guacamole source and binaries...${NC}"

# Download Guacamole Server
wget -q --show-progress -O guacamole-server-${GUACVERSION}.tar.gz ${SERVER}/source/guacamole-server-${GUACVERSION}.tar.gz
tar -xzf guacamole-server-${GUACVERSION}.tar.gz

# Download Guacamole Client
wget -q --show-progress -O guacamole-${GUACVERSION}.war ${SERVER}/binary/guacamole-${GUACVERSION}.war

# Download Guacamole authentication extensions (Database)
wget -q --show-progress -O guacamole-auth-jdbc-${GUACVERSION}.tar.gz ${SERVER}/binary/guacamole-auth-jdbc-${GUACVERSION}.tar.gz
tar -xzf guacamole-auth-jdbc-${GUACVERSION}.tar.gz

# MFA Setup
if [ "${installTOTP}" = true ]; then
    wget -q --show-progress -O guacamole-auth-totp-${GUACVERSION}.tar.gz ${SERVER}/binary/guacamole-auth-totp-${GUACVERSION}.tar.gz
    tar -xzf guacamole-auth-totp-${GUACVERSION}.tar.gz
fi

if [ "${installDuo}" = true ]; then
    wget -q --show-progress -O guacamole-auth-duo-${GUACVERSION}.tar.gz ${SERVER}/binary/guacamole-auth-duo-${GUACVERSION}.tar.gz
    tar -xzf guacamole-auth-duo-${GUACVERSION}.tar.gz
fi

# Download MySQL Connector/J manually
wget -q --show-progress -O mysql-connector-java-${MCJVER}.tar.gz https://dev.mysql.com/get/Downloads/Connector-J/mysql-connector-java-${MCJVER}.tar.gz
tar -xzf mysql-connector-java-${MCJVER}.tar.gz

# Make environment directories
rm -rf /etc/guacamole/lib/
rm -rf /etc/guacamole/extensions/
mkdir -p /etc/guacamole/lib/
mkdir -p /etc/guacamole/extensions/
mkdir -p /usr/sbin/.config/freerdp
chown daemon:daemon /usr/sbin/.config/freerdp
mkdir -p /var/guacamole
chown daemon:daemon /var/guacamole

# Build guacd (Guacamole-server)
cd guacamole-server-${GUACVERSION}/
export CFLAGS="-Wno-error"

echo -e "${BLUE}Configuring Guacamole-Server...${NC}"
./configure --with-systemd-dir=/etc/systemd/system  &>> ${LOG}

echo -e "${BLUE}Compiling Guacamole-Server...${NC}"
make &>> ${LOG}
make install &>> ${LOG}
ldconfig
cd ..

# Move compiled / downloaded files to environment targets
mv -f guacamole-${GUACVERSION}.war /etc/guacamole/guacamole.war
mv -f guacamole-auth-jdbc-${GUACVERSION}/mysql/guacamole-auth-jdbc-mysql-${GUACVERSION}.jar /etc/guacamole/extensions/
ln -sf /etc/guacamole/guacamole.war /var/lib/${TOMCAT}/webapps/
mv -f mysql-connector-java-${MCJVER}/mysql-connector-java-${MCJVER}.jar /etc/guacamole/lib/mysql-connector-java.jar

if [ "${installTOTP}" = true ]; then
    mv -f guacamole-auth-totp-${GUACVERSION}/guacamole-auth-totp-${GUACVERSION}.jar /etc/guacamole/extensions/
fi

if [ "${installDuo}" = true ]; then
    mv -f guacamole-auth-duo-${GUACVERSION}/guacamole-auth-duo-${GUACVERSION}.jar /etc/guacamole/extensions/
fi

# Configure guacamole.properties directly with your Managed/Aiven database params
rm -f /etc/guacamole/guacamole.properties
touch /etc/guacamole/guacamole.properties
echo "mysql-hostname: ${mysqlHost}" >> /etc/guacamole/guacamole.properties
echo "mysql-port: ${mysqlPort}" >> /etc/guacamole/guacamole.properties
echo "mysql-database: ${guacDb}" >> /etc/guacamole/guacamole.properties
echo "mysql-username: ${guacUser}" >> /etc/guacamole/guacamole.properties
echo "mysql-password: ${guacPwd}" >> /etc/guacamole/guacamole.properties
echo "mysql-ssl-mode: required" >> /etc/guacamole/guacamole.properties

# Create guacd.conf configuration file 
cat >> /etc/guacamole/guacd.conf <<- "EOF"
[server]
bind_host = 0.0.0.0
bind_port = 4822
EOF

# Restart application web servers and daemons
echo -e "${BLUE}Restarting system services...${NC}"
service ${TOMCAT} restart
systemctl enable ${TOMCAT}
service guacd stop 2>/dev/null
service guacd start
systemctl enable guacd

# Firewall checks
if [ -x "$( command -v ufw )" ]; then
    if [[ $(ufw status | grep inactive | wc -l) -eq 0 ]]; then
        ufw allow 8080/tcp comment 'allow tomcat'
    fi
fi    

# Cleanup deployment directories
rm -rf guacamole-*
rm -rf mysql-connector-java-*

echo -e "${GREEN}\nInstallation Complete!\n- Portal URL: http://localhost:8080/guacamole/\n- Default login: guacadmin/guacadmin${NC}"
echo -e "${YELLOW}Reminder: Make sure you have manually imported the schema tables into your Aiven instance beforehand!${NC}"
