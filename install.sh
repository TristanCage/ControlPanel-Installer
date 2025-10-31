#!/bin/bash
# shellcheck source=/dev/null

set -e

########################################################
# 
#              Pterodactyl-AutoThemes Installation
#
#              Created and maintained by Goodness Tech
#
#                 Protected by MIT License
#
########################################################

# Get the latest version before running the script #
get_release() {
curl --silent \
  -H "Accept: application/vnd.github.com/v3+json" \
  https://api.github.com/repos/Ferks-FK/ControlPanel-Installer/releases/latest |
  grep '"tag_name":' |
  sed -E 's/.*"([^"]+)".*/\1/'
}

# Variables #
SCRIPT_RELEASE="$(get_release)"
SUPPORT_LINK="https://discord.gg/buDBbSGJmQ"
WIKI_LINK="https://github.com/Ferks-FK/ControlPanel-Installer/wiki"
GITHUB_URL="https://raw.githubusercontent.com/Ferks-FK/ControlPanel.gg-Installer/$SCRIPT_RELEASE"
RANDOM_PASSWORD="$(openssl rand -base64 32)"
MYSQL_PASSWORD=false
CONFIGURE_SSL=false
INFORMATIONS="/var/log/ControlPanel-Info"
FQDN=""

update_variables() {
CLIENT_VERSION="$(grep "'version'" "/var/www/controlpanel/config/app.php" | cut -c18-25 | sed "s/[',]//g")"
LATEST_VERSION="$(curl -s https://raw.githubusercontent.com/Ctrlpanel-gg/panel/main/config/app.php | grep "'version'" | cut -c18-25 | sed "s/[',]//g")"
}

# Visual Functions #
print_brake() {
  for ((n = 0; n < $1; n++)); do
    echo -n "#"
  done
  echo ""
}

print_warning() {
  echo ""
  echo -e "* ${YELLOW}WARNING${RESET}: $1"
  echo ""
}

print_error() {
  echo ""
  echo -e "* ${RED}ERROR${RESET}: $1"
  echo ""
}

print_success() {
  echo ""
  echo -e "* ${GREEN}SUCCESS${RESET}: $1"
  echo ""
}

print() {
  echo ""
  echo -e "* ${GREEN}$1${RESET}"
  echo ""
}

hyperlink() {
  echo -e "\e]8;;${1}\a${1}\e]8;;\a"
}

# Colors #
GREEN="\e[0;92m"
YELLOW="\033[1;33m"
RED='\033[0;31m'
RESET="\e[0m"

EMAIL_RX="^(([A-Za-z0-9]+((\.|\-|\_|\+)?[A-Za-z0-9]?)*[A-Za-z0-9]+)|[A-Za-z0-9]+)@(([A-Za-z0-9]+)+((\.|\-|\_)?([A-Za-z0-9]+)+)*)+\.([A-Za-z]{2,})+$"

valid_email() {
  [[ $1 =~ ${EMAIL_RX} ]]
}

email_input() {
  local __resultvar=$1
  local result=''

  while ! valid_email "$result"; do
    echo -n "* ${2}"
    read -r result

    valid_email "$result" || print_error "${3}"
  done

  eval "$__resultvar="'$result'""
}

password_input() {
  local __resultvar=$1
  local result=''
  local default="$4"

  while [ -z "$result" ]; do
    echo -n "* ${2}"
    while IFS= read -r -s -n1 char; do
      [[ -z $char ]] && {
        printf '\n'
        break
      }
      if [[ $char == $'\x7f' ]]; then
        if [ -n "$result" ]; then
          [[ -n $result ]] && result=${result%?}
          printf '\b \b'
        fi
      else
        result+=$char
        printf '*'
      fi
    done
    [ -z "$result" ] && [ -n "$default" ] && result="$default"
    [ -z "$result" ] && print_error "${3}"
  done

  eval "$__resultvar="'$result'""
}

# OS check #
check_distro() {
  if [ -f /etc/os-release ]; then
    . /etc/os-release
    OS=$(echo "$ID" | awk '{print tolower($0)}')
    OS_VER=$VERSION_ID
  elif type lsb_release >/dev/null 2>&1; then
    OS=$(lsb_release -si | awk '{print tolower($0)}')
    OS_VER=$(lsb_release -sr)
  elif [ -f /etc/lsb-release ]; then
    . /etc/lsb-release
    OS=$(echo "$DISTRIB_ID" | awk '{print tolower($0)}')
    OS_VER=$DISTRIB_RELEASE
  elif [ -f /etc/debian_version ]; then
    OS="debian"
    OS_VER=$(cat /etc/debian_version)
  elif [ -f /etc/SuSe-release ]; then
    OS="SuSE"
    OS_VER="?"
  elif [ -f /etc/redhat-release ]; then
    OS="Red Hat/CentOS"
    OS_VER="?"
  else
    OS=$(uname -s)
    OS_VER=$(uname -r)
  fi

  OS=$(echo "$OS" | awk '{print tolower($0)}')
  OS_VER_MAJOR=$(echo "$OS_VER" | cut -d. -f1)
}

only_upgrade_panel() {
print "Updating your panel, please wait..."

cd /var/www/controlpanel
php artisan down

git stash
git pull

[ "$OS" == "centos" ] && export PATH=/usr/local/bin:$PATH
COMPOSER_ALLOW_SUPERUSER=1 composer install --no-dev --optimize-autoloader

php artisan migrate --seed --force

php artisan view:clear
php artisan config:clear

set_permissions

php artisan queue:restart

php artisan up

print "Your panel has been successfully updated to version ${YELLOW}${LATEST_VERSION}${RESET}."
exit 1
}

enable_services_debian_based() {
systemctl enable mariadb --now
systemctl enable redis-server --now
systemctl enable nginx
}

enable_services_centos_based() {
systemctl enable mariadb --now
systemctl enable redis --now
systemctl enable nginx
}

allow_selinux() {
setsebool -P httpd_can_network_connect 1 || true
setsebool -P httpd_execmem 1 || true
setsebool -P httpd_unified 1 || true
}

centos_php() {
curl -so /etc/php-fpm.d/www-controlpanel.conf "$GITHUB_URL"/configs/www-controlpanel.conf

systemctl enable php-fpm --now
}

check_compatibility() {
print "Checking if your system is compatible with the script..."
sleep 2

case "$OS" in
    debian)
      PHP_SOCKET="/run/php/php8.3-fpm.sock"
      [ "$OS_VER_MAJOR" == "9" ] && SUPPORTED=true
      [ "$OS_VER_MAJOR" == "10" ] && SUPPORTED=true
      [ "$OS_VER_MAJOR" == "11" ] && SUPPORTED=true
    ;;
    ubuntu)
      PHP_SOCKET="/run/php/php8.3-fpm.sock"
      [ "$OS_VER_MAJOR" == "18" ] && SUPPORTED=true
      [ "$OS_VER_MAJOR" == "20" ] && SUPPORTED=true
      [ "$OS_VER_MAJOR" == "22" ] && SUPPORTED=true
    ;;
    centos)
      PHP_SOCKET="/var/run/php-fpm/controlpanel.sock"
      [ "$OS_VER_MAJOR" == "7" ] && SUPPORTED=true
      [ "$OS_VER_MAJOR" == "8" ] && SUPPORTED=true
    ;;
    *)
        SUPPORTED=false
    ;;
esac

if [ "$SUPPORTED" == true ]; then
    print "$OS $OS_VER is supported!"
  else
    print_error "$OS $OS_VER is not supported!"
    exit 1
fi
}

ask_ssl() {
echo -ne "* Would you like to configure ssl for your domain? (y/N): "
read -r CONFIGURE_SSL
if [[ "$CONFIGURE_SSL" == [Yy] ]]; then
    CONFIGURE_SSL=true
    email_input EMAIL "Enter your email address to create the SSL certificate for your domain: " "Email cannot by empty or invalid!"
fi
}

install_composer() {
print "Installing Composer..."

curl -sS https://getcomposer.org/installer | php -- --install-dir=/usr/local/bin --filename=composer
}

download_files() {
print "Downloading Necessary Files..."

git clone -q https://github.com/Ctrlpanel-gg/panel.git /var/www/controlpanel
rm -rf /var/www/controlpanel/.env.example
curl -so /var/www/controlpanel/.env.example "$GITHUB_URL"/configs/.env.example

cd /var/www/controlpanel
[ "$OS" == "centos" ] && export PATH=/usr/local/bin:$PATH
COMPOSER_ALLOW_SUPERUSER=1 composer install --no-dev --optimize-autoloader
}

set_permissions() {
print "Setting Necessary Permissions..."

case "$OS" in
  debian | ubuntu)
    chown -R www-data:www-data /var/www/controlpanel/
  ;;
  centos)
    chown -R nginx:nginx /var/www/controlpanel/
  ;;
esac

cd /var/www/controlpanel
chmod -R 755 storage/* bootstrap/cache/
}

configure_environment() {
print "Configuring the base file..."

sed -i -e "s@<timezone>@$TIMEZONE@g" /var/www/controlpanel/.env.example
sed -i -e "s@<db_host>@$DB_HOST@g" /var/www/controlpanel/.env.example
sed -i -e "s@<db_port>@$DB_PORT@g" /var/www/controlpanel/.env.example
sed -i -e "s@<db_name>@$DB_NAME@g" /var/www/controlpanel/.env.example
sed -i -e "s@<db_user>@$DB_USER@g" /var/www/controlpanel/.env.example
sed -i -e "s|<db_pass>|$DB_PASS|g" /var/www/controlpanel/.env.example
}

check_database_info() {
# Check if mysql has a password
if ! mysql -u root -e "SHOW DATABASES;" &>/dev/null; then
  MYSQL_PASSWORD=true
  print_warning "It looks like your MySQL has a password, please enter it now"
  password_input MYSQL_ROOT_PASS "MySQL Password: " "Password cannot by empty!"
  if mysql -u root -p"$MYSQL_ROOT_PASS" -e "SHOW DATABASES;" &>/dev/null; then
      print "The password is correct, continuing..."
    else
      print_warning "The password is not correct, please re-enter the password"
      check_database_info
  fi
fi

# Checks to see if the chosen user already exists
if [ "$MYSQL_PASSWORD" == true ]; then
    mysql -u root -p"$MYSQL_ROOT_PASS" -e "SELECT User FROM mysql.user;" 2>/dev/null >> "$INFORMATIONS/check_user.txt"
  else
    mysql -u root -e "SELECT User FROM mysql.user;" 2>/dev/null >> "$INFORMATIONS/check_user.txt"
fi
sed -i '1d' "$INFORMATIONS/check_user.txt"
while grep -q "$DB_USER" "$INFORMATIONS/check_user.txt"; do
  print_warning "Oops, it looks like user ${GREEN}$DB_USER${RESET} already exists in your MySQL, please use another one."
  echo -n "* Database User: "
  read -r DB_USER
done
rm -r "$INFORMATIONS/check_user.txt"

# Check if the database already exists in mysql
if [ "$MYSQL_PASSWORD" == true ]; then
    mysql -u root -p"$MYSQL_ROOT_PASS" -e "SHOW DATABASES;" 2>/dev/null >> "$INFORMATIONS/check_db.txt"
  else
    mysql -u root -e "SHOW DATABASES;" 2>/dev/null >> "$INFORMATIONS/check_db.txt"
fi
sed -i '1d' "$INFORMATIONS/check_db.txt"
while grep -q "$DB_NAME" "$INFORMATIONS/check_db.txt"; do
  print_warning "Oops, it looks like the database ${GREEN}$DB_NAME${RESET} already exists in your MySQL, please use another one."
  echo -n "* Database Name: "
  read -r DB_NAME
done
rm -r "$INFORMATIONS/check_db.txt"
}

configure_database() {
print "Configuring Database..."

if [ "$MYSQL_PASSWORD" == true ]; then
    mysql -u root -p"$MYSQL_ROOT_PASS" -e "CREATE DATABASE ${DB_NAME};" &>/dev/null
    mysql -u root -p"$MYSQL_ROOT_PASS" -e "CREATE USER '${DB_USER}'@'${DB_HOST}' IDENTIFIED BY '${DB_PASS}';" &>/dev/null
    mysql -u root -p"$MYSQL_ROOT_PASS" -e "GRANT ALL PRIVILEGES ON ${DB_NAME}.* TO '${DB_USER}'@'${DB_HOST}';" &>/dev/null
    mysql -u root -p"$MYSQL_ROOT_PASS" -e "FLUSH PRIVILEGES;" &>/dev/null
  else
    mysql -u root -e "CREATE DATABASE ${DB_NAME};"
    mysql -u root -e "CREATE USER '${DB_USER}'@'${DB_HOST}' IDENTIFIED BY '${DB_PASS}';"
    mysql -u root -e "GRANT ALL PRIVILEGES ON ${DB_NAME}.* TO '${DB_USER}'@'${DB_HOST}';"
    mysql -u root -e "FLUSH PRIVILEGES;"
fi
}

configure_webserver() {
print "Configuring Web-Server..."

if [ "$CONFIGURE_SSL" == true ]; then
    WEB_FILE="controlpanel_ssl.conf"
  else
    WEB_FILE="controlpanel.conf"
fi

case "$OS" in
  debian | ubuntu)
    rm -rf /etc/nginx/sites-enabled/default

    curl -so /etc/nginx/sites-available/controlpanel.conf "$GITHUB_URL"/configs/$WEB_FILE

    sed -i -e "s@<domain>@$FQDN@g" /etc/nginx/sites-available/controlpanel.conf

    sed -i -e "s@<php_socket>@$PHP_SOCKET@g" /etc/nginx/sites-available/controlpanel.conf

    [ "$OS" == "debian" ] && [ "$OS_VER_MAJOR" == "9" ] && sed -i -e 's/ TLSv1.3//' /etc/nginx/sites-available/controlpanel.conf

    ln -s /etc/nginx/sites-available/controlpanel.conf /etc/nginx/sites-enabled/controlpanel.conf
  ;;
  centos)
    rm -rf /etc/nginx/conf.d/default

    curl -so /etc/nginx/conf.d/controlpanel.conf "$GITHUB_URL"/configs/$WEB_FILE

    sed -i -e "s@<domain>@$FQDN@g" /etc/nginx/conf.d/controlpanel.conf

    sed -i -e "s@<php_socket>@$PHP_SOCKET@g" /etc/nginx/conf.d/controlpanel.conf
  ;;
esac

# Kill nginx if it is listening on port 80 before it starts, fixed a port usage bug.
if netstat -tlpn | grep 80 &>/dev/null; then
  killall nginx
fi

if [ "$(systemctl is-active --quiet nginx)" == "active" ]; then
    systemctl restart nginx
  else
    systemctl start nginx
fi
}

configure_firewall() {
print "Configuring the firewall..."

case "$OS" in
  debian | ubuntu)
    apt-get install -qq -y ufw

    ufw allow ssh &>/dev/null
    ufw allow http &>/dev/null
    ufw allow https &>/dev/null

    ufw --force enable &>/dev/null
    ufw --force reload &>/dev/null
  ;;
  centos)
    yum update -y -q

    yum -y -q install firewalld &>/dev/null

    systemctl --now enable firewalld &>/dev/null

    firewall-cmd --add-service=http --permanent -q
    firewall-cmd --add-service=https --permanent -q
    firewall-cmd --add-service=ssh --permanent -q
    firewall-cmd --reload -q
  ;;
esac
}

configure_ssl() {
print "Configuring SSL..."

FAILED=false

if [ "$(systemctl is-active --quiet nginx)" == "inactive" ] || [ "$(systemctl is-active --quiet nginx)" == "failed" ]; then
  systemctl start nginx
fi

case "$OS" in
  debian | ubuntu)
    apt-get update -y -qq && apt-get upgrade -y -qq
    apt-get install -y -qq certbot && apt-get install -y -qq python3-certbot-nginx
  ;;
  centos)
    [ "$OS_VER_MAJOR" == "7" ] && yum -y -q install certbot python-certbot-nginx
    [ "$OS_VER_MAJOR" == "8" ] && yum -y -q install certbot python3-certbot-nginx
  ;;
esac

certbot certonly --nginx --non-interactive --agree-tos --quiet --no-eff-email --email "$EMAIL" -d "$FQDN" || FAILED=true

if [ ! -d "/etc/letsencrypt/live/$FQDN/" ] || [ "$FAILED" == true ]; then
    if [ "$(systemctl is-active --quiet nginx)" == "active" ]; then
      systemctl stop nginx
    fi
    print_warning "The script failed to generate the SSL certificate automatically, trying alternative command..."
    FAILED=false

    certbot certonly --standalone --non-interactive --agree-tos --quiet --no-eff-email --email "$EMAIL" -d "$FQDN" || FAILED=true

    if [ -d "/etc/letsencrypt/live/$FQDN/" ] || [ "$FAILED" == false ]; then
        print "The script was able to successfully generate the SSL certificate!"
      else
        print_warning "The script failed to generate the certificate, try to do it manually."
    fi
  else
    print "The script was able to successfully generate the SSL certificate!"
fi
}

configure_crontab() {
print "Configuring Crontab"

# FIX: Use a more reliable way to append the crontab entry
(crontab -l 2>/dev/null; echo "* * * * * php /var/www/controlpanel/artisan schedule:run >> /dev/null 2>&1") | crontab -
}

configure_service() {
print "Configuring ControlPanel Service..."

curl -so /etc/systemd/system/controlpanel.service "$GITHUB_URL"/configs/controlpanel.service

case "$OS" in
  debian | ubuntu)
    sed -i -e "s@<user>@www-data@g" /etc/systemd/system/controlpanel.service
  ;;
  centos)
    sed -i -e "s@<user>@nginx@g" /etc/systemd/system/controlpanel.service
  ;;
esac

systemctl enable controlpanel.service --now
}

# NEW FUNCTION: Install basic dependencies to prevent crashes
basic_deps() {
  print "Installing basic system utilities..."
  case "$OS" in
    debian | ubuntu)
      apt-get update -y -qq
      # Adding dirmngr, git, curl, net-tools for robustness
      apt-get install -y -qq dirmngr curl git wget unzip tar net-tools
    ;;
    centos)
      yum install -y -q epel-release curl git wget unzip tar net-tools
    ;;
  esac
}

deps_ubuntu() {
print "Installing dependencies for Ubuntu ${OS_VER}"

# Add "add-apt-repository" command
apt-get install -y software-properties-common curl apt-transport-https ca-certificates gnupg

# Add additional repositories for PHP, Redis, and MariaDB
LC_ALL=C.UTF-8 add-apt-repository -y ppa:ondrej/php
curl -sS https://downloads.mariadb.com/MariaDB/mariadb_repo_setup | sudo bash

# Update repositories list
apt-get update -y && apt-get upgrade -y

# Add universe repository if you are on Ubuntu 18.04
[ "$OS_VER_MAJOR" == "18" ] && apt-add-repository universe

# Install Dependencies - NOW USING PHP 8.3
apt-get install -y php8.3 php8.3-{cli,gd,mysql,pdo,mbstring,tokenizer,bcmath,xml,fpm,curl,zip,intl,redis} mariadb-server nginx tar unzip git redis-server psmisc net-tools

# Enable services
enable_services_debian_based
}

deps_debian() {
print "Installing dependencies for Debian ${OS_VER}"

# MariaDB need dirmngr - already done in basic_deps but kept just in case
apt-get install -y dirmngr

# install PHP 8.3 using sury's repo
apt-get install -y ca-certificates apt-transport-https lsb-release
wget -O /etc/apt/trusted.gpg.d/php.gpg https://packages.sury.org/php/apt.gpg
echo "deb https://packages.sury.org/php/ $(lsb_release -sc) main" | tee /etc/apt/sources.list.d/php.list

# Add the MariaDB repo
curl -sS https://downloads.mariadb.com/MariaDB/mariadb_repo_setup | bash

# Update repositories list
apt-get update -y && apt-get upgrade -y

# Install Dependencies - NOW USING PHP 8.3
apt-get install -y php8.3 php8.3-{cli,gd,mysql,pdo,mbstring,tokenizer,bcmath,xml,fpm,curl,zip,intl,redis} mariadb-server nginx tar unzip git redis-server psmisc net-tools

# Enable services
enable_services_debian_based
}

deps_centos() {
print "Installing dependencies for CentOS ${OS_VER}"

if [ "$OS_VER_MAJOR" == "7" ]; then
    # SELinux tools
    yum install -y policycoreutils policycoreutils-python selinux-policy selinux-policy-targeted libselinux-utils setroubleshoot-server setools setools-console mcstrans
    
    # Install MariaDB
    curl -sS https://downloads.mariadb.com/MariaDB/mariadb_repo_setup | bash

    # Add remi repo (php8.3)
    yum install -y http://rpms.remirepo.net/enterprise/remi-release-7.rpm
    yum install -y yum-utils
    yum-config-manager -y --disable remi-php54
    yum-config-manager -y --enable remi-php83

    # Install dependencies - ADDED php-redis to fix "Class Redis not found"
    yum -y install php php-common php-tokenizer php-curl php-fpm php-cli php-json php-mysqlnd php-mcrypt php-gd php-mbstring php-pdo php-zip php-bcmath php-dom php-opcache php-intl php-redis mariadb-server nginx curl tar zip unzip git redis psmisc net-tools
    yum update -y
  elif [ "$OS_VER_MAJOR" == "8" ]; then
    # SELinux tools
    yum install -y policycoreutils selinux-policy selinux-policy-targeted setroubleshoot-server setools setools-console mcstrans
    
    # Add remi repo (php8.3)
    yum install -y http://rpms.remirepo.net/enterprise/remi-release-8.rpm
    yum module enable -y php:remi-8.3

    # Install MariaDB
    yum install -y mariadb mariadb-server

    # Install dependencies - ADDED php-redis to fix "Class Redis not found"
    yum install -y php php-common php-fpm php-cli php-json php-mysqlnd php-gd php-mbstring php-pdo php-zip php-bcmath php-dom php-opcache php-intl php-redis mariadb-server nginx curl tar zip unzip git redis psmisc net-tools
    yum update -y
fi

# Enable services
enable_services_centos_based

# SELinux
allow_selinux
}

install_controlpanel() {
print "Starting installation, this may take a few minutes, please wait."
sleep 2

# Check Distro again for accurate dependency targeting
check_distro

# Install basic dependencies first (FIX for intl/other errors)
basic_deps

case "$OS" in
  debian | ubuntu)
    apt-get update -y && apt-get upgrade -y
    [ "$OS" == "ubuntu" ] && deps_ubuntu
    [ "$OS" == "debian" ] && deps_debian
  ;;
  centos)
    yum update -y && yum upgrade -y
    deps_centos
  ;;
esac

[ "$OS" == "centos" ] && centos_php
install_composer
download_files
set_permissions
configure_environment
check_database_info
configure_database
configure_firewall
configure_crontab
configure_service
[ "$CONFIGURE_SSL" == true ] && configure_ssl
configure_webserver
bye
}

# NEW FUNCTION: Uninstall the panel and all related files
uninstall_controlpanel() {
    print_warning "This process will remove the ControlPanel installation, database, and configurations."
    echo -n "* Are you absolutely sure you want to uninstall ControlPanel? (y/N): "
    read -r CONFIRM_UNINSTALL
    [[ "$CONFIRM_UNINSTALL" != [Yy] ]] && print_error "Uninstallation aborted!" && exit 1

    if [ ! -f "$INFORMATIONS/install.info" ]; then
        print_error "Could not find installation log file ($INFORMATIONS/install.info). Manual cleanup is required."
        exit 1
    fi

    print "Reading installation details..."
    DB_NAME=$(grep '* Database Name:' "$INFORMATIONS/install.info" | awk '{print $4}')
    DB_USER=$(grep '* Database User:' "$INFORMATIONS/install.info" | awk '{print $4}')
    DB_PASS=$(grep '* Database Pass:' "$INFORMATIONS/install.info" | awk '{print $4}')
    FQDN=$(grep '* Hostname/FQDN:' "$INFORMATIONS/install.info" | awk '{print $2}')
    
    # Check if mysql has a password
    MYSQL_ROOT_PASS=""
    if ! mysql -u root -e "SHOW DATABASES;" &>/dev/null; then
      print_warning "It looks like your MySQL has a password, please enter it now to remove the database:"
      password_input MYSQL_ROOT_PASS "MySQL Password: " "Password cannot by empty!"
    fi

    print "Stopping services..."
    systemctl stop controlpanel.service || true

    print "Removing Database and User ($DB_NAME, $DB_USER)..."
    if [ -n "$MYSQL_ROOT_PASS" ]; then
      mysql -u root -p"$MYSQL_ROOT_PASS" -e "DROP DATABASE IF EXISTS ${DB_NAME};" &>/dev/null
      mysql -u root -p"$MYSQL_ROOT_PASS" -e "DROP USER IF EXISTS '${DB_USER}'@'%';" &>/dev/null
      mysql -u root -p"$MYSQL_ROOT_PASS" -e "FLUSH PRIVILEGES;" &>/dev/null
    else
      mysql -u root -e "DROP DATABASE IF EXISTS ${DB_NAME};" &>/dev/null
      mysql -u root -e "DROP USER IF EXISTS '${DB_USER}'@'%';" &>/dev/null
      mysql -u root -e "FLUSH PRIVILEGES;" &>/dev/null
    fi

    print "Removing Nginx configuration..."
    # Attempt to remove configuration files for both debian/ubuntu and centos
    if [ -f "/etc/nginx/sites-enabled/controlpanel.conf" ]; then
        rm -f /etc/nginx/sites-enabled/controlpanel.conf
    fi
    if [ -f "/etc/nginx/sites-available/controlpanel.conf" ]; then
        rm -f /etc/nginx/sites-available/controlpanel.conf
    fi
    if [ -f "/etc/nginx/conf.d/controlpanel.conf" ]; then
        rm -f /etc/nginx/conf.d/controlpanel.conf
    fi
    
    print "Removing systemd service..."
    systemctl disable controlpanel.service || true
    rm -f /etc/systemd/system/controlpanel.service
    systemctl daemon-reload || true

    print "Removing Crontab entry..."
    crontab -l | grep -v 'php /var/www/controlpanel/artisan schedule:run' | crontab -

    print "Removing panel files (${YELLOW}/var/www/controlpanel${RESET})..."
    rm -rf /var/www/controlpanel

    print "Removing install logs (${YELLOW}$INFORMATIONS${RESET})..."
    rm -rf "$INFORMATIONS"

    print "Restarting Nginx..."
    systemctl restart nginx || true

    print_success "ControlPanel has been successfully uninstalled."
    exit 0
}


main() {
# Check Distro first to set variables for upgrade/install
check_distro

# Check if it is already installed and check the version #
if [ -d "/var/www/controlpanel" ]; then
  update_variables
  
  # New Menu for Installed Panel
  print_brake 75
  print_warning "The ControlPanel seems to be already installed."
  print "* Current Version: ${YELLOW}$CLIENT_VERSION${RESET} | Latest Version: ${YELLOW}$LATEST_VERSION${RESET}"
  echo
  echo -e "* Select an option:"
  echo -e "  ${GREEN}1)${RESET} Upgrade Panel (Current Logic)"
  echo -e "  ${RED}2)${RESET} Uninstall Panel (Cleanup all files and DB)"
  echo -e "  ${YELLOW}3)${RESET} Exit"
  echo -ne "* Enter your choice (1-3): "
  read -r PANEL_CHOICE
  print_brake 75

  case $PANEL_CHOICE in
    1)
      if [ "$CLIENT_VERSION" != "$LATEST_VERSION" ]; then
          only_upgrade_panel
        else
          print "Panel is already up-to-date. Aborting..."
          exit 1
      fi
    ;;
    2)
      uninstall_controlpanel
    ;;
    3)
      print "Exiting script. Bye..."
      exit 1
    ;;
    *)
      print_error "Invalid choice. Exiting..."
      exit 1
    ;;
  esac

  exit 1
fi

# Check if pterodactyl is installed #
if [ ! -d "/var/www/pterodactyl" ]; then
  print_warning "An installation of pterodactyl was not found in the directory ${YELLOW}/var/www/pterodactyl${RESET}"
  echo -ne "* Is your pterodactyl panel installed on this machine? (y/N): "
  read -r PTERO_DIR
  if [[ "$PTERO_DIR" =~ [Yy] ]]; then
    echo -e "* ${GREEN}EXAMPLE${RESET}: /var/www/myptero"
    echo -ne "* Enter the directory from where your pterodactyl panel is installed: "
    read -r PTERO_DIR
    if [ -f "$PTERO_DIR/config/app.php" ]; then
        print "Pterodactyl was found, continuing..."
      else
        print_error "Pterodactyl not found, running script again..."
        main
    fi
  fi
fi

# Check if the OS is compatible #
check_compatibility

# Set FQDN for panel #
while [ -z "$FQDN" ]; do
  print_warning "Do not use a domain that is already in use by another application, such as the domain of your pterodactyl."
  echo -ne "* Set the Hostname/FQDN for panel (${YELLOW}panel.example.com${RESET}): "
  read -r FQDN
  [ -z "$FQDN" ] && print_error "FQDN cannot be empty"
done

# Install the packages to check FQDN and ask about SSL only if FQDN is a string #
if [[ "$FQDN" == [a-zA-Z]* ]]; then
  ask_ssl
fi

# Set host of the database #
echo -ne "* Enter the host of the database (${YELLOW}127.0.0.1${RESET}): "
read -r DB_HOST
[ -z "$DB_HOST" ] && DB_HOST="127.0.0.1"

# Set port of the database #
echo -ne "* Enter the port of the database (${YELLOW}3306${RESET}): "
read -r DB_PORT
[ -z "$DB_PORT" ] && DB_PORT="3306"

# Set name of the database #
echo -ne "* Enter the name of the database (${YELLOW}controlpanel${RESET}): "
read -r DB_NAME
[ -z "$DB_NAME" ] && DB_NAME="controlpanel"

# Set user of the database #
echo -ne "* Enter the username of the database (${YELLOW}controlpaneluser${RESET}): "
read -r DB_USER
[ -z "$DB_USER" ] && DB_USER="controlpaneluser"

# Set pass of the database #
password_input DB_PASS "Enter the password of the database (Enter for random password): " "Password cannot by empty!" "$RANDOM_PASSWORD"

# Ask Time-Zone #
echo -e "* List of valid time-zones here: ${YELLOW}$(hyperlink "http://php.net/manual/en/timezones.php")${RESET}"
echo -ne "* Select Time-Zone (${YELLOW}America/New_York${RESET}): "
read -r TIMEZONE
[ -z "$TIMEZONE" ] && TIMEZONE="America/New_York"

# Summary #
echo
print_brake 75
echo
echo -e "* Hostname/FQDN: $FQDN"
echo -e "* Database Host: $DB_HOST"
echo -e "* Database Port: $DB_PORT"
echo -e "* Database Name: $DB_NAME"
echo -e "* Database User: $DB_USER"
echo -e "* Database Pass: (censored)"
echo -e "* Time-Zone: $TIMEZONE"
echo -e "* Configure SSL: $CONFIGURE_SSL"
echo
print_brake 75
echo

# Create the logs directory #
mkdir -p $INFORMATIONS

# Write the information to a log #
{
  echo -e "* Hostname/FQDN: $FQDN"
  echo -e "* Database Host: $DB_HOST"
  echo -e "* Database Port: $DB_PORT"
  echo -e "* Database Name: $DB_NAME"
  echo -e "* Database User: $DB_USER"
  echo -e "* Database Pass: $DB_PASS"
  echo ""
  echo "* After using this file, delete it immediately!"
} > $INFORMATIONS/install.info

# Confirm all the choices #
echo -n "* Initial settings complete, do you want to continue to the installation? (y/N): "
read -r CONTINUE_INSTALL
[[ "$CONTINUE_INSTALL" =~ [Yy] ]] && install_controlpanel
[[ "$CONTINUE_INSTALL" == [Nn] ]] && print_error "Installation aborted!" && exit 1
}

bye() {
echo
print_brake 90
echo
echo -e "${GREEN}* The script has finished the installation process!${RESET}"

[ "$CONFIGURE_SSL" == true ] && APP_URL="https://$FQDN"
[ "$CONFIGURE_SSL" == false ] && APP_URL="http://$FQDN"

echo -e "${GREEN}* To complete the configuration of your panel, go to ${YELLOW}$(hyperlink "$APP_URL/install")${RESET}"
echo -e "${GREEN}* Thank you for using this script!"
echo -e "* Wiki: ${YELLOW}$(hyperlink "$WIKI_LINK")${RESET}"
echo -e "${GREEN}* Support Group: ${YELLOW}$(hyperlink "$SUPPORT_LINK")${RESET}"
echo -e "${GREEN}*${RESET} If you have questions about the information that is requested on the installation page\nall the necessary information about it is written in: (${YELLOW}$INFORMATIONS/install.info${RESET})."
echo
print_brake 90
echo
}

# Exec Script #
main