#/bin/bash

set -e

GECICI_DIZIN=$(mktemp -d)
trap "rm -rf $GECICI_DIZIN" EXIT 

# Yetkili kullanıcı(root) denetimi yapılıyor.
[[ ! 0 == $(id -u) ]] && exit 100

case "$1" in
	10)
		TOMCAT_SURUM="TOMCAT_100";;
	9)
		TOMCAT_SURUM="TOMCAT_90";;
	8.5)
		TOMCAT_SURUM="TOMCAT_85";;
	*)
		echo 'Desteklenen sürümler: 10, 9, 8.5' && exit 2;;
esac

# Apache Tomcat Sürümleri
TOMCAT_100="https://dlcdn.apache.org/tomcat/tomcat-10/v10.0.27/bin/apache-tomcat-10.0.27.tar.gz"
TOMCAT_90="https://dlcdn.apache.org/tomcat/tomcat-9/v9.0.68/bin/apache-tomcat-9.0.68.tar.gz"
TOMCAT_85="https://dlcdn.apache.org/tomcat/tomcat-8/v8.5.83/bin/apache-tomcat-8.5.83.tar.gz"

# Gerekli paketler denetlenip kuruluyor
test -z $(command -v wget) && apt install -y wget
test -z $(command -v java) && apt install -y default-jdk

# Tomcat indiriliyor
wget ${!TOMCAT_SURUM} -O "${GECICI_DIZIN}/tomcat-${TOMCAT_SURUM}.tar.gz"

# Varsa kurulu olan Tomcat hizmeti durdurulup tomcat kullanıcısı tekrar oluşturuluyor
systemctl disable tomcat.service || true
systemctl stop tomcat.service || true
[[ $(id tomcat) && $(deluser tomcat && rm -rf /opt/tomcat) ]]
useradd -r -m -d /opt/tomcat -U -s /bin/false tomcat

# Tomcat ilgili dizine çıkartılıp sahiplik ve izinleri ayarlanıyor
tar -xzf "${GECICI_DIZIN}/tomcat-${TOMCAT_SURUM}.tar.gz" -C "${GECICI_DIZIN}"
mv -fu ${GECICI_DIZIN}/apache-tomcat-*/* "/opt/tomcat/"
chmod +x /opt/tomcat/bin/*.sh
chown -R tomcat:tomcat /opt/tomcat

# Hizmet dosyası oluşturulup devreye alınıyor
mkdir -p /etc/systemd/system/
cat > /etc/systemd/system/tomcat.service << EOF
[Unit]
Description=Tomcat
After=network.target

[Service]
Type=forking

User=tomcat
Group=tomcat

Environment="JAVA_OPTS=-Djava.security.egd=file:///dev/urandom"
Environment="CATALINA_BASE=/opt/tomcat"
Environment="CATALINA_HOME=/opt/tomcat"
Environment="CATALINA_PID=/opt/tomcat/temp/tomcat.pid"
Environment="CATALINA_OPTS=-Xms512M -Xmx1024M -server -XX:+UseParallelGC"

ExecStart=/opt/tomcat/bin/startup.sh
ExecStop=/opt/tomcat/bin/shutdown.sh

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable tomcat.service
systemctl start tomcat.service
systemctl status --no-pager tomcat.service
