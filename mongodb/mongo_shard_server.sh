#!/bin/bash -x
## Mongo Shard Server Build Script
##  Prerequisites:
##    - Create 64 bit EC2 instance using Ubuntu 9.10 EBS root AMI
##    - Attach a EBS volume used for data storage to /dev/sdf

# Add Mongo repository
sed -i '$ a deb http://downloads.mongodb.org/distros/ubuntu 9.10 10gen' /etc/apt/sources.list
apt-key adv --keyserver keyserver.ubuntu.com --recv 7F0CEB10

# Update and install XFS support and MongoDB
aptitude update
aptitude safe-upgrade -y
aptitude install xfsprogs -y
aptitude install mongodb-stable -y

# Format (if not already formatted) and mount EBS volume for database
mkfs.xfs /dev/sdf
mkdir /mnt/data
mount /dev/sdf /mnt/data

# Stop mongodb to make configuration changes
service mongodb stop

# Change mongodb startup script to start a shard server using our custom paths
rm /etc/init/mongodb.conf
cat > /etc/init/mongodb.conf << EOF
description "MongoDB Shard Server"

pre-start script
    mkdir -p /mnt/data/db/mongodb/
    chown -R mongodb:mongodb /mnt/data
end script

start on startup
stop on shutdown

exec start-stop-daemon --start --quiet --chuid mongodb --exec  /usr/bin/mongod -- --shardsvr --dbpath /mnt/data/db/mongodb --logpath /mnt/data/db/mongodb.log --logappend
EOF

# Install monit and monitor our MongoDB process
aptitude install monit;
sed -i '/startup/ c startup=1' /etc/default/monit;
rm /etc/monit/monitrc;
cat > /etc/monit/monitrc << EOF
set daemon 60
set logfile /var/log/monit.log
set httpd port 2812 and
  allow admin:monit
  
  check process mongodb with pidfile /mnt/data/db/mongodb/mongod.lock
    start program "/sbin/start mongodb"
    stop program "/sbin/stop mongodb"
    if failed port 27018 then restart
    if 5 restarts within 5 cycles then timeout
EOF

# Mount our EBS volumes using XFS and disable access time attribute for performance
sed -i '$ a /dev/sdf  /mnt/data  xfs  noatime  0  0' /etc/fstab

# Reboot the instance
reboot -h now