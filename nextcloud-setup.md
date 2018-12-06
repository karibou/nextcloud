# Nextcloud setup
  * From a new server where /data is the mount point of a large disk:
  * Install docker-ce from instruction on web
  * Install docker-compose
  * Install git
  * Create nextcloud directory

The installation uses one **docker-compose.yml** file from the nextcloud
(git repository)https://github.com/nextcloud/docker.git


```
cd /data
mkdir /data/nextcloud
git clone https://github.com/nextcloud/docker.git
cd docker/.examples/docker-compose/with-nginx-proxy/mariadb/apache
cp -pr . /data/nextcloud
cat << EOF > /data/nextcloud/db.env
MYSQL_PASSWORD={your db password}
MYSQL_DATABASE=nextcloud
MYSQL_USER=nextcloud
EOF

source /data/nextcloud/db.env
```

## docker-compose
```
version: '3'

services:
  db:
    image: mariadb
    command: --transaction-isolation=READ-COMMITTED --binlog-format=ROW
    restart: always
    volumes:
      - /data/nextcloud/volumes/mysql:/var/lib/mysql
    environment:
      - MYSQL_ROOT_PASSWORD=${MYSQL_PASSWORD}
    env_file:
      - db.env

  app:
    image: nextcloud:apache
    restart: always
    volumes:
      - /data/nextcloud/volumes/html:/var/www/html
    environment:
      - VIRTUAL_HOST=caricloud.ddns.net
      - LETSENCRYPT_HOST=caricloud.ddns.net
      - LETSENCRYPT_EMAIL=bouchard.louis@gmail.com
      - MYSQL_HOST=db
    env_file:
      - db.env
    depends_on:
      - db
    networks:
      - proxy-tier
      - default

  proxy:
    build: ./proxy
    restart: always
    ports:
      - 80:80
      - 443:443
    labels:
      com.github.jrcs.letsencrypt_nginx_proxy_companion.nginx_proxy: "true"
    volumes:
      - /data/nextcloud/volumes/certs:/etc/nginx/certs:ro
      - /data/nextcloud/volumes/vhost.d:/etc/nginx/vhost.d
      - /data/nextcloud/volumes/nginx:/usr/share/nginx/html
      - /var/run/docker.sock:/tmp/docker.sock:ro
    networks:
      - proxy-tier

  letsencrypt-companion:
    image: jrcs/letsencrypt-nginx-proxy-companion
    restart: always
    volumes:
      - /data/nextcloud/volumes/certs:/etc/nginx/certs
      - /data/nextcloud/volumes/vhost.d:/etc/nginx/vhost.d
      - /data/nextcloud/volumes/nginx:/usr/share/nginx/html
      - /var/run/docker.sock:/var/run/docker.sock:ro
    networks:
      - proxy-tier
    depends_on:
      - proxy

networks:
  proxy-tier:
```
## Start and configure

Run `docker-compose up -d` and connect to the server. Use
the following information :

  * Select a password for the Admin user
  * db name : *nextcloud*
  * password : *selected MYSQL_PASSWORD*
  * db user : *nextcloud*
  * db host : *db*
Wait for the configuration to finish

## Setup

Create a group named *famille*
Create users :
  * louis
  * nathalie
  * alice
  * fanny

## Create users

Create each user and login so the user environment is created on the
server.

## Migrate Dropbox data

Install the dropbox CLI from
https://www.dropboxwiki.com/tips-and-tricks/using-the-official-dropbox-command-line-interface-cli
into /usr/local/bin
Run
  * `dropbox start`
  * `dropox status`
and follow the link to enable sychronization

Once synchronized, copy the `Dropbox` files in the `Nextcloud` file
structure :

  * rsync -av Dropbox/ /data/nextcloud/html/data/louis/files
  * chown -R www-data:www-data /data/nextcloud/html/data/nathalie
  * chown -R www-data:www-data /data/nextcloud/html/data/alice
  * chown -R www-data:www-data /data/nextcloud/html/data/louis

## Synchronize nextcloud data

This has to be done in the nextcloud container :
```
# docker-compose ps

Ports
--------------------------------------------------------------------------------------------
nextcloud_app_1_e1fb6596e208   /entrypoint.sh apache2-for ...   Up
0.0.0.0:4242->80/tcp
nextcloud_db_1_cb109db65606
3306/tcp

root:/data/nextcloud/html/data# docker exec -u www-data -ti nextcloud_app_1_e1fb6596e208 bash
www-data@364409291b46:~/html$ php ./console.php files:scan --all
```
## Backup script

The following script is adapted from one found on the net :

```
#!/bin/bash

# NextCloud to Amazon S3 Backup Script
# Author: Autoize (autoize.com)

# This script creates an incremental backup of your NextCloud instance to Amazon S3.
# Amazon S3 is a highly redundant block storage service with versioning and lifecycle management features.

# Requirements
# - Amazon AWS Account and IAM User with AmazonS3FullAccess privilege
# - Python 2.x and Python PIP - sudo apt-get install python && wget https://bootstrap.pypa.io/get-pip.py && sudo python get-pip.py
# - s3cmd installed from PyPI - sudo pip install s3cmd

# Name of Amazon S3 Bucket
s3_bucket='s3_bucket_name'

# Path to NextCloud installation
nextcloud_dir='/data/nextcloud'

# Docker identifiers
compose_file=$nextcloud_dir/docker-compose.yml

nextcloud_container=$(docker-compose -f $compose_file ps | grep _app_ | cut -d' ' -f1)
db_container=$(docker-compose -f $compose_file ps | grep _db_ | cut -d' ' -f1)

# Path to NextCloud data directory
data_dir='/data/nextcloud/volumes/html/data'

# MySQL/MariaDB Database credentials
source /data/nextcloud/db.env

# Check if running as root

if [ "$(id -u)" != "0" ]; then
   echo "This script must be run as root" 1>&2
   exit 1
fi

echo 'Started'
date +'%a %b %e %H:%M:%S %Z %Y'

# Put NextCloud into maintenance mode. 
# This ensures consistency between the database and data directory.

docker exec -ti -u www-data $nextcloud_container php occ maintenance:mode --on

# Dump database and backup to S3

now=$(date +%Y%m%d%H%M)
docker exec -ti $db_container mysqldump --single-transaction -u$MYSQL_USER -p$MYSQL_PASSWORD $MYSQL_DATABASE > /data/backup/nextcloud_$now.sql
#s3cmd put nextcloud.sql s3://$s3_bucket/NextCloudDB/nextcloud.sql

# Sync data to S3 in place, then disable maintenance mode 
# NextCloud will be unavailable during the sync. This will take a while if you added much data since your last backup.

# If upload cache is in the default subdirectory, under each user's folder (Default)
#s3cmd sync --recursive --preserve --exclude '*/cache/*' $data_dir s3://$s3_bucket/

# If upload cache for all users is stored directly as an immediate subdirectory of the data directory
# s3cmd sync --recursive --preserve --exclude 'cache/*' $data_dir s3://$s3_bucket/

tar --exclude='*/cache/*' -czf /data/backup/nextcloud_$now.tgz $nextcloud_dir/proxy $nextcloud_dir/volumes/html/config/config.php $data_dir
docker exec -ti -u www-data $nextcloud_container php occ maintenance:mode --off
cp $nextcloud_dir/db.env /data/backup/db.env
cp /data/backup/db.env /home/caribou/backup
cp $nextcloud_dir/docker-compose.yml /data/backup/docker-compose-$now.yml
cp /data/backup/docker-compose-$now.yml /home/caribou/backup/last-docker-compose.yml
cp /data/backup/nextcloud_$now.sql /home/caribou/backup/last_db_backup.sql
cp /data/backup/nextcloud_$now.tgz /home/caribou/backup/last_backup.tgz


date +'%a %b %e %H:%M:%S %Z %Y'
echo 'Finished'
```
Add the script in the root's crontab so it is run once a day :

```
sudo cp nextcloud_backup.sh /root
cat << EOF > /root/crontab
@daily /root/nextcloud_backup.sh > /dev/null 2>&1
crontab /root/crontab
```
## Restore from backups

Copy the content of the $HOME/backup directory to the location where the
nextcloud service will be restored.

Follow the instructions in the **setup** section up to **Start and configure**
to set up the new nextcloud service by adapting the **docker-compose.yml**
to the new domain.

Start the service but **DO NOT LOGIN** to the nextcloud webpage.
Just start the container once and then shut them down.

Start the db container and copy the database backup in the container :

```
source /data/nextcloud/db.env
docker-compose up -d db
docker-compose ps
nextcloud_db_1_a669799ee60b   docker-entrypoint.sh --tra ...   Up      3306/tcp
docker cp $HOME/backup/last_db_backup.sql nextcloud_db_1_a669799ee60b:last_db_backup.sql
```
Restore the backup of the database :
```
docker exec -ti nextcloud_db_1_a669799ee60b mysql -u$MYSQL_USER -p$MYSQL_PASSWORD $MYSQL_DATABASE
MariaDB [nextcloud]> \! last_db_backup.sql
MariaDB [nextcloud]> \q
```

Restore the backed up files :

```
cd /
tar xf $HOME/backup/last_backup.tgz
```

Edit the */data/nextcloud/volumes/html/config/config.php* to set the **trusted_domains** to the
fqdn of the new server
