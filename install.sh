#!/bin/bash

cp -f borg-backup-lib.sh /usr/lib/


mkdir -p /var/borg-backup-script/lock_dir/
mkdir -p /var/borg-backup-script/cache_last_backup
mkdir -p /etc/borg-backup-script
cp -f example /etc/borg-backup-script/example
cp -f borg-backup-script /usr/bin/borg-backup-script
chmod 700 /usr/bin/borg-backup-script


if [ -d "/usr/lib/nagios/plugins" ]; then
    cp -f "check_last_borgbackup.sh" "/usr/lib/nagios/plugins/check_last_borgbackup.sh"
    chmod 755 "/usr/lib/nagios/plugins/check_last_borgbackup.sh"
fi

cp borg-backup-script@.service /etc/systemd/system
