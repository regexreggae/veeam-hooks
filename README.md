# Veeam MariaDB Docker Backup Hooks

Simple pre-freeze and post-thaw scripts for Veeam Linux guest processing.

> [!WARNING]
> Use at your own risk

The pre-freeze script creates a MariaDB dump from a Docker container before the VM snapshot.  
The post-thaw script optionally unfreezes a filesystem.

Dumps can optionally be compressed, validated and rotated.

---

# Installation

Clone this repo:
`git clone https://github.com/regexreggae/veeam-hooks.git`
Afterwards cd into it - `cd veeam-hooks`

# Configuration
Assuming you are now in directory `veeam-hooks` as `root`, do as follows:

Create the config file: just rename `config/veeam-mariadb-backup.conf.example` to `config/veeam-mariadb-backup.conf` and insert your values.

Create the password file: just rename `secrets/mariadb_backup_password.example` to `secrets/mariadb_backup_password` and insert your value.

Set permissions so only root can read (if required):
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

Run manually - do this before your Veeam job runs so you know it works and the scripts exit with 0:
```
sudo /opt/veeam-hooks/veeam-pre-freeze-mariadb.sh
```
Check dump directory to see if the dumps get created:
```
ls -lah /srv/backups/mariadb
```
# Restoring from dump

Example restoring an entire dump:
> [!WARNING]
> This can potentially destroy your entire database and therefore your application - only execute if you know what you're doing!
```
gunzip -c mariadb_dump_<timestamp>.sql.gz \
| docker exec -e MYSQL_PWD='<root-db-pw>' -i <container> mariadb -u root
```
# Notes

`fsfreeze` is optional and disabled by default.
If used, it should normally target a dedicated mountpoint (provide path as value).
