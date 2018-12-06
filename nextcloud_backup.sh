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
