#!/bin/bash
set -x

# squid
# this comes first so terraform doesn't need to wait too long to copy to local
mkdir /etc/squid
cat | tee /etc/squid/squid.conf <<EOF
visible_hostname squid

#Handling HTTP requests
http_port 3128
http_port 3129 intercept
acl allowed_http_sites dstdomain .amazonaws.com
acl allowed_http_sites dstdomain .security.ubuntu.com
http_access allow allowed_http_sites

#Handling HTTPS requests
https_port 3130 cert=/etc/squid/ssl/squid.pem ssl-bump intercept
acl SSL_port port 443
http_access allow SSL_port
acl allowed_https_sites ssl::server_name .redhat.io
acl allowed_https_sites ssl::server_name .redhat.com
acl allowed_https_sites ssl::server_name .openshift.com
acl allowed_https_sites ssl::server_name .quay.io
acl allowed_https_sites ssl::server_name .amazonaws.com
acl step1 at_step SslBump1
acl step2 at_step SslBump2
acl step3 at_step SslBump3
ssl_bump peek step1 all
ssl_bump peek step2 allowed_https_sites
ssl_bump splice step3 allowed_https_sites
ssl_bump terminate step3 all

http_access deny all
EOF

# ssl pem
mkdir /etc/squid/ssl
openssl genrsa -out /etc/squid/ssl/squid.key 2048
openssl req -new -key /etc/squid/ssl/squid.key -out /etc/squid/ssl/squid.csr -subj "/C=XX/ST=XX/L=squid/O=squid/CN=squid"
openssl x509 -req -days 3650 -in /etc/squid/ssl/squid.csr -signkey /etc/squid/ssl/squid.key -out /etc/squid/ssl/squid.crt
cat /etc/squid/ssl/squid.key /etc/squid/ssl/squid.crt | tee /etc/squid/ssl/squid.pem
cat /etc/squid/ssl/squid.crt | tee /home/ec2-user/squid.crt

# Allow access to uid 31 (squid in container, unknown on host) to /var/log/squid/
mkdir /var/log/squid
chown 31:31 /var/log/squid/
chmod u+rwx /var/log/squid/

# Install latest Docker
dnf -y install dnf-plugins-core
dnf config-manager --add-repo https://download.docker.com/linux/rhel/docker-ce.repo
dnf -y install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
systemctl enable --now docker

# Pull squid image and run using config and cert setup above
docker pull karlhopkinsonturrell/squid-alpine
docker run -it --ulimit nofile=65535:65535 -d --net host \
    --mount type=bind,src=/etc/squid/squid.conf,dst=/etc/squid/squid.conf \
    --mount type=bind,src=/etc/squid/ssl,dst=/etc/squid/ssl \
    --mount type=bind,src=/var/log/squid/,dst=/var/log/squid/ \
    karlhopkinsonturrell/squid-alpine

# iptables
yum install -y iptables
yum install -y iptables-services
# Route inbound traffic into squid
iptables -F
iptables -X
iptables -t nat -F
iptables -t nat -X
iptables -t mangle -F
iptables -t mangle -X
iptables -t raw -F
iptables -t raw -X
iptables -t security -F
iptables -t security -X
iptables -P INPUT ACCEPT
iptables -P FORWARD ACCEPT
iptables -P OUTPUT ACCEPT
iptables -t nat -I PREROUTING 1 -p tcp --dport 80 -j REDIRECT --to-port 3129
iptables -t nat -I PREROUTING 1 -p tcp --dport 443 -j REDIRECT --to-port 3130
ip6tables -t nat -I PREROUTING 1 -p tcp --dport 80 -j REDIRECT --to-port 3129
ip6tables -t nat -I PREROUTING 1 -p tcp --dport 443 -j REDIRECT --to-port 3130
iptables-save >/etc/sysconfig/iptables
iptables-save -t nat >/etc/sysconfig/iptables
ip6tables-save >/etc/sysconfig/ip6tables
# Allow forward
sysctl net.ipv4.ip_forward=1
sysctl net.ipv6.conf.all.forwarding=1
sysctl net.ipv4.conf.all.send_redirects=0
systemctl enable --now iptables
