#!/bin/bash

set -euo pipefail
cd /root/
swapoff -a

SUBDOMAINNAME="$1"
DOMAINNAME="$2"

mkdir -p /root/.ssh/
echo -n 'command="exit 1",restrict,port-forwarding,permitopen="127.0.0.1:1935",permitopen="127.0.0.1:443" ' >> /root/.ssh/authorized_keys
cat id_ed25519.pub >> /root/.ssh/authorized_keys
mv id_ed25519.pub /root/.ssh/

rm -f /etc/ssh/ssh_host_*
mv ssh_host_* /etc/ssh/
chmod 0600 /etc/ssh/ssh_host_*
chmod 0644 /etc/ssh/ssh_host_*.pub

hostnamectl set-hostname "$DOMAINNAME"
sed -i "s/___SUBDOMAINNAME___/$SUBDOMAINNAME/g" nginx.conf
sed -i "s/___DOMAINNAME___/$DOMAINNAME/g" nginx.conf

export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -yqq software-properties-common git tzdata ufw build-essential libpcre3 libpcre3-dev libssl-dev ffmpeg wget zlib1g-dev
ln -sf /usr/share/zoneinfo/Europe/Berlin /etc/localtime
dpkg-reconfigure --frontend noninteractive tzdata

ufw allow OpenSSH
ufw allow http
ufw allow https
ufw --force enable

git clone https://github.com/sergey-dryabzhinsky/nginx-rtmp-module.git

wget http://nginx.org/download/nginx-1.18.0.tar.gz
tar -xf nginx-1.18.0.tar.gz
cd nginx-1.18.0

./configure --with-http_ssl_module --add-module=../nginx-rtmp-module
make -j $(nproc)
mkdir -p /usr/local/nginx
mount -t ramfs ramfs /usr/local/nginx
make install

mkdir -p /LIVE/hls
mount -t ramfs ramfs /LIVE
chown -R www-data /LIVE/

rm -f /usr/local/nginx/conf/nginx.conf
mv /root/nginx.conf /usr/local/nginx/conf/nginx.conf
mv /root/nginx.service /lib/systemd/system/nginx.service
rm -f /usr/local/nginx/html/index.html
mv /root/{index.html,poster.jpg} /usr/local/nginx/html/
wget https://cdn.jsdelivr.net/npm/@clappr/player@latest/dist/clappr.min.js -O /usr/local/nginx/html/clappr.min.js
wget https://cdn.jsdelivr.net/gh/clappr/clappr-level-selector-plugin@latest/dist/level-selector.min.js -O /usr/local/nginx/html/level-selector.min.js

systemctl enable nginx.service

snap install --classic certbot
certbot --nginx --nginx-server-root /usr/local/nginx/conf/ --nginx-ctl /usr/local/nginx/sbin/nginx -d "${SUBDOMAINNAME}.${DOMAINNAME}" -d "${DOMAINNAME}" -n --agree-tos --hsts --register-unsafely-without-email

service ssh restart