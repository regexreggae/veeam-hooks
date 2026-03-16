# Veeam MariaDB Docker Backup Hooks

Simple pre-freeze and post-thaw scripts for Veeam Linux guest processing.

The pre-freeze script creates a MariaDB dump from a Docker container before the VM snapshot.  
The post-thaw script optionally unfreezes a filesystem.

Dumps can optionally be compressed, validated and rotated.

---

# Repository Contents


veeam-pre-freeze-mariadb.sh
veeam-post-thaw-mariadb.sh
config/veeam-mariadb-backup.conf.example


---

# Installation

Create the target directories on the host:

```bash
sudo mkdir -p /opt/veeam-hooks/config
sudo mkdir -p /opt/veeam-hooks/secrets
sudo mkdir -p /opt/veeam-hooks/state

Copy the scripts:

sudo cp veeam-pre-freeze-mariadb.sh /opt/veeam-hooks/
sudo cp veeam-post-thaw-mariadb.sh /opt/veeam-hooks/

Set permissions:

sudo chmod 750 /opt/veeam-hooks/*.sh
sudo chown root:root /opt/veeam-hooks/*.sh
Configuration

Create the config file:

/opt/veeam-hooks/config/veeam-mariadb-backup.conf

Example:

DB_CONTAINER_NAME="it-blog_db_1"
DB_NAME="wp-blog"
DB_USER="backupuser"
DB_PASSWORD_FILE="/opt/veeam-hooks/secrets/mariadb_backup_password"

BACKUP_DIR="/srv/backups/mariadb"
STATE_DIR="/opt/veeam-hooks/state"

RETENTION_DAYS="14"
COMPRESS_DUMP="yes"

FREEZE_MOUNT=""

Create the password file:

/opt/veeam-hooks/secrets/mariadb_backup_password

Example content:

example_password

Set permissions:

sudo chmod 600 /opt/veeam-hooks/config/veeam-mariadb-backup.conf
sudo chmod 600 /opt/veeam-hooks/secrets/mariadb_backup_password
Veeam Configuration

In the VM backup job:

Enable Guest Processing and configure:

Pre-freeze script:
/opt/veeam-hooks/veeam-pre-freeze-mariadb.sh

Post-thaw script:
/opt/veeam-hooks/veeam-post-thaw-mariadb.sh
Logs

Scripts log to systemd journal.

Example:

journalctl -t veeam-pre-freeze-mariadb
journalctl -t veeam-post-thaw-mariadb
Manual Test

Run manually:

sudo /opt/veeam-hooks/veeam-pre-freeze-mariadb.sh

Check dump directory:

ls -lah /srv/backups/mariadb
Restore Example

Example restoring a dump:

gunzip -c mariadb_dump_<timestamp>.sql.gz \
| docker exec -i <container> mariadb -u root -p
Notes

fsfreeze is optional and disabled by default.
If used, it should normally target a dedicated mountpoint.
