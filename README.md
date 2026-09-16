# Kişisel ve iş için kullandığım betikler

## certbot-ilkbyte-dns01

Debian bağımlılıkları: `certbot`, `curl`, `jq`, `bind9-dnsutils`.
Betiği çalıştırılabilir olarak `/usr/local/bin/certbot-ilkbyte-dns01` konumuna kurun.
Anahtarları depoya yazmadan `/etc/default/certbot-ilkbyte-dns01` dosyasında tanımlayın;
dosyanın sahibi `root`, izinleri `0600` olmalı:

```bash
ACCESS_KEY="ERISIM_ANAHTARI"
SECRET_KEY="GIZLI_ANAHTAR"
```

Önce `--dry-run` ile sınama ortamında doğrulayın. Başarılı olduğunda gerçek sertifika
almak için bu seçeneği kaldırın:

```bash
certbot certonly --dry-run --manual --preferred-challenges dns \
	-d "oktayaktogan.com.tr" -d "*.oktayaktogan.com.tr" \
	--manual-auth-hook "certbot-ilkbyte-dns01 -r add" \
	--manual-cleanup-hook "certbot-ilkbyte-dns01 -r delete"
```

Doğrulama kancası (authentication hook), aynı isimdeki diğer TXT değerlerini korur
ve kaydı tüm yetkili DNS sunucularında görene kadar bekler. Temizlik kancası
(cleanup hook) yalnızca `CERTBOT_VALIDATION` ile belirtilen değeri siler.
Elle silmede de `-v` zorunludur; değersiz toplu silme yapılmaz.
İsteğe bağlı `WAIT_ATTEMPTS=30`, `WAIT_INTERVAL=10` ve `DNS_SERVER` ayarları
aynı yapılandırma dosyasına eklenebilir. `DNS_SERVER` verilirse yetkili sunucular
yerine bu sunucu sorgulanır.

Alt alan adlarında DNS bölgesini açıkça belirtin: örneğin `api.example.com` için
her iki kancada `-d example.com -s api` kullanın.
Eski `-t` seçeneği uyarı verir; belgelenmiş API'de yaşam süresi (TTL) parametresi
yoktur, `record_priority` öncelik alanıdır.
[İlkbyte DNS API belgesi](https://apidocs.ilkbyte.com/docs/2.0/domain/manage).

Çevrimdışı regresyon sınamaları (regression tests), gerçek API ve DNS değişikliği yapmaz:

```bash
python3 -B -m unittest discover -s tests -p test_certbot_ilkbyte_dns01.py -v
shellcheck certbot-ilkbyte-dns01
```
