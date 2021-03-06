#!/usr/bin/env bash

set -ex

apt-get update

# Determine external IP address
set +x
IP=`ifconfig eth1 | grep inet | awk '{print $2}' | sed 's/addr://'`
echo "IP address is '${IP}'"
set -x

# Determine hostname for Magento web-site
HOST=`hostname -f`
if [ -z ${HOST} ]; then
    # Use external IP address as hostname
    set +x
    HOST=${IP}
    echo "Use IP address '${HOST}' as hostname"
    set -x
fi

# Setup Apache
apt-get install -y apache2
a2enmod rewrite
apache_config="/etc/apache2/sites-available/magento2.conf"
cp /vagrant/magento2.vhost.conf ${apache_config}
sed -i "s/<host>/${HOST}/g" ${apache_config}
# Enable Magento virtual host
a2ensite magento2.conf
# Disable default virtual host
sudo a2dissite 000-default

# Setup PHP
apt-get install -y php5 php5-mhash php5-mcrypt php5-curl php5-cli php5-mysql php5-gd php5-intl curl
if [ ! -f /etc/php5/apache2/conf.d/20-mcrypt.ini ]; then
    ln -s /etc/php5/mods-available/mcrypt.ini /etc/php5/apache2/conf.d/20-mcrypt.ini
fi
if [ ! -f /etc/php5/cli/conf.d/20-mcrypt.ini ]; then
    ln -s /etc/php5/mods-available/mcrypt.ini /etc/php5/cli/conf.d/20-mcrypt.ini
fi
echo "date.timezone = America/Chicago" >> /etc/php5/cli/php.ini

# Restart Apache
service apache2 restart

# Setup MySQL
debconf-set-selections <<< 'mysql-server mysql-server/root_password password password'
debconf-set-selections <<< 'mysql-server mysql-server/root_password_again password password'
apt-get install -q -y mysql-server-5.6 mysql-client-5.6
mysql -u root -ppassword -e "create database if not exists magento;"
mysql -u root -ppassword -e "GRANT ALL ON magento.* TO magento@localhost IDENTIFIED BY 'magento';"

# Setup Composer
apt-get install -y git
if [ ! -f /usr/local/bin/composer ]; then
    cd /tmp
    curl -sS https://getcomposer.org/installer | php
    mv composer.phar /usr/local/bin/composer
fi
github_token="/vagrant/local.config/github.oauth.token"
if [ -f ${github_token} ]; then
    set +x
    echo "Installing GitHub OAuth token from ${github_token}..."
    composer config -g github-oauth.github.com `cat ${github_token}`
    set -x
fi

magento_dir="/var/www/magento2"
cd ${magento_dir}
composer install

rm -rf ${magento_dir}/var/*
rm -rf ${magento_dir}/pub/static/*

set +x
echo "Apache host should be now available at 'http://${HOST}/' pointing to directory '${magento_dir}'"
if [ ${HOST} != ${IP} ]; then
    echo "Don't forget to update your 'hosts' file with '${IP} ${HOST}'"
fi
