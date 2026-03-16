# Veeam MariaDB Docker Backup Hooks

Simple pre-freeze and post-thaw scripts for Veeam Linux guest processing.

The pre-freeze script creates a MariaDB dump from a Docker container before the VM snapshot.  
The post-thaw script optionally unfreezes a filesystem.

Dumps can optionally be compressed, validated and rotated.

---

# Installation

Create the target directories on the host:

```
sudo mkdir -p /opt/veeam-hooks/config
sudo mkdir -p /opt/veeam-hooks/secrets
sudo mkdir -p /opt/veeam-hooks/state
```
Copy the scripts:
```
sudo cp veeam-pre-freeze-mariadb.sh /opt/veeam-hooks/
sudo cp veeam-post-thaw-mariadb.sh /opt/veeam-hooks/
```
Set permissions:
```
sudo chmod 750 /opt/veeam-hooks/*.sh
sudo chown root:root /opt/veeam-hooks/*.sh
```
# Configuration

Create the config file: just rename `config/veeam-mariadb-backup.conf.example` to `config/veeam-mariadb-backup.conf` and insert your values.

Create the password file: just rename `secrets/mariadb_backup_password.example` to `secrets/mariadb_backup_password` and insert your value.

Set permissions so only root can read:
```
sudo chmod 600 /opt/veeam-hooks/config/veeam-mariadb-backup.conf
sudo chmod 600 /opt/veeam-hooks/secrets/mariadb_backup_password
```
# Veeam Configuration

In the VM backup job:

Enable Guest Processing and configure:

Pre-freeze script:
use the `/opt/veeam-hooks/veeam-pre-freeze-mariadb.sh` script

Post-thaw script:
use the `/opt/veeam-hooks/veeam-post-thaw-mariadb.sh` script

Make sure Veeam connects to your machine as root!

# Logs

Scripts log to systemd journal.

Example for how to check these logs:
```
journalctl -t veeam-pre-freeze-mariadb
journalctl -t veeam-post-thaw-mariadb
```
# Manual Test

Run manually:
```
sudo /opt/veeam-hooks/veeam-pre-freeze-mariadb.sh
```
Check dump directory:
```
ls -lah /srv/backups/mariadb
```
# Restoring from dump

Example restoring an entire dump:
```
gunzip -c mariadb_dump_<timestamp>.sql.gz \
| docker exec -e MYSQL_PWD='<root-db-pw>' -i <container> mariadb -u root
```
# Notes

`fsfreeze` is optional and disabled by default.
If used, it should normally target a dedicated mountpoint.
