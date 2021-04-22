#!/bin/bash

blue(){
    echo -e "\033[34m\033[01m$1\033[0m"
}
green(){
    echo -e "\033[32m\033[01m$1\033[0m"
}
red(){
    echo -e "\033[31m\033[01m$1\033[0m"
}
yellow(){
    echo -e "\033[33m\033[01m$1\033[0m"
}

logcmd(){
    eval $1 | tee -ai /var/atrandys.log
}

cat >> /usr/src/atrandys.log <<-EOF
== Script: atrandys/xray/install.sh
== Time  : $(date +"%Y-%m-%d %H:%M:%S")
== OS    : $RELEASE $VERSION
== Kernel: $(uname -r)
== User  : $(whoami)
EOF
sleep 2s
check_port(){
    green "$(date +"%Y-%m-%d %H:%M:%S") ==== ���˿�"
    $systemPackage -y install net-tools
    Port80=`netstat -tlpn | awk -F '[: ]+' '$1=="tcp"{print $5}' | grep -w 80`
    Port443=`netstat -tlpn | awk -F '[: ]+' '$1=="tcp"{print $5}' | grep -w 443`
    if [ -n "$Port80" ]; then
        process80=`netstat -tlpn | awk -F '[: ]+' '$5=="80"{print $9}'`
        red "$(date +"%Y-%m-%d %H:%M:%S") - 80�˿ڱ�ռ��,ռ�ý���:${process80}\n== Install failed."
        exit 1
    fi
    if [ -n "$Port443" ]; then
        process443=`netstat -tlpn | awk -F '[: ]+' '$5=="443"{print $9}'`
        red "$(date +"%Y-%m-%d %H:%M:%S") - 443�˿ڱ�ռ��,ռ�ý���:${process443}.\n== Install failed."
        exit 1
    fi
}
install_nginx(){
    green "$(date +"%Y-%m-%d %H:%M:%S") ==== ��װnginx"
    wget http://nginx.org/keys/nginx_signing.key
    apt-key add nginx_signing.key
    echo "deb http://nginx.org/packages/mainline/debian/ jessie nginx
    deb-src http://nginx.org/packages/mainline/debian/ jessie nginx" >> /etc/apt/sources.list
    apt-get update
    apt-get install nginx
    if [ ! -d "/etc/nginx" ]; then
        red "$(date +"%Y-%m-%d %H:%M:%S") - ������nginxû�а�װ�ɹ�������ʹ�ýű��е�ɾ��xray���ܣ�Ȼ�������°�װ.\n== Install failed."
        exit 1
    fi
    
cat > /etc/nginx/nginx.conf <<-EOF
user  root;
worker_processes  1;
#error_log  /etc/nginx/error.log warn;
#pid    /var/run/nginx.pid;
events {
    worker_connections  1024;
}
http {
    include       /etc/nginx/mime.types;
    default_type  application/octet-stream;
    log_format  main  '\$remote_addr - \$remote_user [\$time_local] "\$request" '
                      '\$status \$body_bytes_sent "\$http_referer" '
                      '"\$http_user_agent" "\$http_x_forwarded_for"';
    #access_log  /etc/nginx/access.log  main;
    sendfile        on;
    #tcp_nopush     on;
    keepalive_timeout  120;
    client_max_body_size 20m;
    #gzip  on;
    include /etc/nginx/conf.d/*.conf;
}
EOF

cat > /etc/nginx/conf.d/default.conf<<-EOF
 server {
    listen       127.0.0.1:37212;
    server_name  $your_domain;
    root /usr/share/nginx/html;
    index index.php index.html index.htm;
}
 server {
    listen       127.0.0.1:37213 http2;
    server_name  $your_domain;
    root /usr/share/nginx/html;
    index index.php index.html index.htm;
}
    
server { 
    listen       0.0.0.0:80;
    server_name  $your_domain;
    root /usr/share/nginx/html/;
    index index.php index.html;
    #rewrite ^(.*)$  https://\$host\$1 permanent; 
}
EOF
    green "$(date +"%Y-%m-%d %H:%M:%S") ==== ���nginx�����ļ�"
    nginx -t
    #CHECK=$(grep SELINUX= /etc/selinux/config | grep -v "#")
    #if [ "$CHECK" != "SELINUX=disabled" ]; then
    #    loggreen "����Selinux����nginx"
    #    cat /var/log/audit/audit.log | grep nginx | grep denied | audit2allow -M mynginx  
    #    semodule -i mynginx.pp 
    #fi
    systemctl enable nginx.service
    systemctl restart nginx.service
    green "$(date +"%Y-%m-%d %H:%M:%S") - ʹ��acme.sh����https֤��."
    curl https://get.acme.sh | sh
    ~/.acme.sh/acme.sh  --issue  -d $your_domain  --webroot /usr/share/nginx/html/
    if test -s /root/.acme.sh/$your_domain/fullchain.cer; then
        green "$(date +"%Y-%m-%d %H:%M:%S") - ����https֤��ɹ�."
    else
        cert_failed="1"
        red "$(date +"%Y-%m-%d %H:%M:%S") - ����֤��ʧ�ܣ��볢���ֶ�����֤��."
    fi
    install_xray
}

install_xray(){ 
    green "$(date +"%Y-%m-%d %H:%M:%S") ==== ��װxray"
    mkdir /usr/local/etc/xray/
    mkdir /usr/local/etc/xray/cert
    bash <(curl -L https://raw.githubusercontent.com/XTLS/Xray-install/main/install-release.sh)
    cd /usr/local/etc/xray/
    rm -f config.json
    v2uuid=$(cat /proc/sys/kernel/random/uuid)
cat > /usr/local/etc/xray/config.json<<-EOF
{
    "log": {
        "loglevel": "warning"
    }, 
    "inbounds": [
        {
            "listen": "0.0.0.0", 
            "port": 443, 
            "protocol": "vless", 
            "settings": {
                "clients": [
                    {
                        "id": "$v2uuid", 
                        "level": 0, 
                        "email": "a@b.com",
                        "flow":"xtls-rprx-direct"
                    }
                ], 
                "decryption": "none", 
                "fallbacks": [
                    {
                        "dest": 37212
                    }, 
                    {
                        "alpn": "h2", 
                        "dest": 37213
                    }
                ]
            }, 
            "streamSettings": {
                "network": "tcp", 
                "security": "xtls", 
                "xtlsSettings": {
                    "serverName": "$your_domain", 
                    "alpn": [
                        "h2", 
                        "http/1.1"
                    ], 
                    "certificates": [
                        {
                            "certificateFile": "/usr/local/etc/xray/cert/fullchain.cer", 
                            "keyFile": "/usr/local/etc/xray/cert/private.key"
                        }
                    ]
                }
            }
        }
    ], 
    "outbounds": [
        {
            "protocol": "freedom", 
            "settings": { }
        }
    ]
}
EOF
cat > /usr/local/etc/xray/client.json<<-EOF
{
    "log": {
        "loglevel": "warning"
    },
    "inbounds": [
        {
            "port": 1080,
            "listen": "127.0.0.1",
            "protocol": "socks",
            "settings": {
                "udp": true
            }
        }
    ],
    "outbounds": [
        {
            "protocol": "vless",
            "settings": {
                "vnext": [
                    {
                        "address": "$your_domain",
                        "port": 443,
                        "users": [
                            {
                                "id": "$v2uuid",
                                "flow": "xtls-rprx-direct",
                                "encryption": "none",
                                "level": 0
                            }
                        ]
                    }
                ]
            },
            "streamSettings": {
                "network": "tcp",
                "security": "xtls",
                "xtlsSettings": {
                    "serverName": "$your_domain"
                }
            }
        }
    ]
}
EOF
    if [ -d "/usr/share/nginx/html/" ]; then
        cd /usr/share/nginx/html/ && rm -f ./*
        wget https://github.com/atrandys/trojan/raw/master/fakesite.zip
        unzip -o fakesite.zip
    fi
    systemctl enable xray.service
    sed -i "s/User=nobody/User=root/;" /etc/systemd/system/xray.service
    systemctl daemon-reload
    ~/.acme.sh/acme.sh  --installcert  -d  $your_domain   \
        --key-file   /usr/local/etc/xray/cert/private.key \
        --fullchain-file  /usr/local/etc/xray/cert/fullchain.cer \
        --reloadcmd  "chmod -R 777 /usr/local/etc/xray/cert && systemctl restart xray.service"

cat > /usr/local/etc/xray/myconfig.json<<-EOF
{
��ַ��${your_domain}
�˿ڣ�443
id��${v2uuid}
���ܣ�none
���أ�xtls-rprx-direct
�������Զ���
����Э�飺tcp
αװ���ͣ�none
�ײ㴫�䣺xtls
����֤����֤��false
}
EOF

    green "== ��װ���."
    if [ "$cert_failed" == "1" ]; then
        green "======nginx��Ϣ======"
        red "����֤��ʧ�ܣ��볢���ֶ�����֤��."
    fi    
    green "==xray�ͻ��������ļ����·��=="
    green "/usr/local/etc/xray/client.json"
    echo
    echo
    green "==xray���ò���=="
    cat /usr/local/etc/xray/myconfig.json
    green "���ΰ�װ�����Ϣ���£���nginx��xray������������ʾ��װ������"
    ps -aux | grep -e nginx -e xray
    
}

check_domain(){
    $systemPackage install -y wget curl unzip
    blue "Eenter your domain:"
    read your_domain
    real_addr=`ping ${your_domain} -c 1 | sed '1{s/[^(]*(//;s/).*//;q}'`
    local_addr=`curl ipv4.icanhazip.com`
    if [ $real_addr == $local_addr ] ; then
        green "����������ַ��VPS IP��ַƥ��."
        install_nginx
    else
        red "����������ַ��VPS IP��ַ��ƥ��."
        read -p "ǿ�ư�װ?������ [Y/n] :" yn
        [ -z "${yn}" ] && yn="y"
        if [[ $yn == [Yy] ]]; then
            sleep 1s
            install_nginx
        else
            exit 1
        fi
    fi
}

remove_xray(){
    green "$(date +"%Y-%m-%d %H:%M:%S") - ɾ��xray."
    systemctl stop xray.service
    systemctl disable xray.service
    systemctl stop nginx
    systemctl disable nginx
    if [ "$RELEASE" == "centos" ]; then
        yum remove -y nginx
    else
        apt-get -y autoremove nginx
        apt-get -y --purge remove nginx
        apt-get -y autoremove && apt-get -y autoclean
        find / | grep nginx | sudo xargs rm -rf
    fi
    rm -rf /usr/local/share/xray/ /usr/local/etc/xray/
    rm -f /usr/local/bin/xray
    rm -rf /etc/systemd/system/xray*
    rm -rf /etc/nginx
    rm -rf /usr/share/nginx/html/*
    rm -rf /root/.acme.sh/
    green "nginx & xray has been deleted."
    
}

function start_menu(){
    clear
    green " ====================================================="
    green " ������xray + tcp + xtlsһ����װ�ű�"
    green " ϵͳ��֧��debian8   "
    green " ���ߣ�atrandys  www.atrandys.com"
    green " ====================================================="
    echo
    green " 1. ��װ xray + tcp + xtls"
    green " 2. ���� xray"
    red " 3. ɾ�� xray"
    green " 4. �鿴���ò���"
    yellow " 0. Exit"
    echo
    read -p "��������:" num
    case "$num" in
    1)
    check_release
    check_port
    check_domain
    ;;
    2)
    bash <(curl -L https://raw.githubusercontent.com/XTLS/Xray-install/main/install-release.sh)
    systemctl restart xray
    ;;
    3)
    remove_xray 
    ;;
    4)
    cat /usr/local/etc/xray/myconfig.json
    ;;
    0)
    exit 1
    ;;
    *)
    clear
    red "Enter a correct number"
    sleep 2s
    start_menu
    ;;
    esac
}

start_menu