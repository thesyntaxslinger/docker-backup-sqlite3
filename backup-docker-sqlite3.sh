#!/bin/bash

set -euo pipefail

# =================== CONFIG ===================
# REMOTE CONFIG
DOCKER_LOCATION="/path/to/remote/files"
SSH_HOST="1.1.1.1"
SSH_PORT="58686"
SSH_USER="root"

# LOCAL CONFIG
BACKUP_LOCATION="/path/to/local/backup/location"
# =================== CONFIG ===================

_tempfile=$(mktemp)
touch "$_tempfile.2" "$_tempfile.3"
chmod 0600 "$_tempfile.2" "$_tempfile.3"

echo "============================================================="
echo -e "Starting script. This will usually hang...\nCheck output in another terminal window on remote with 'htop' + tab button.\nLook for find command."

# get all the files
ssh "$SSH_USER"@"$SSH_HOST" -p "$SSH_PORT" "find \"$DOCKER_LOCATION\" -type f -exec file -e ascii -e encoding -e tokens -e cdf -e compress -e csv -e elf -e json -e simh -e tar -e text {} \;" > "$_tempfile"
# sort them if it found any files
grep 'SQLite 3' "$_tempfile" | awk '{print $1}' | sed -E 's/:$//' > "$_tempfile.2" || true # .2 is what we are doing bc cbf
if [[ -f "$_tempfile.2" && ! -s "$_tempfile.2" ]]; then
  echo "File was empty! There must be no DB's!"
fi
echo "============================================================="
echo -e "\n\n\n\n"

# make new file for rsync
sed "s|$DOCKER_LOCATION.||g" "$_tempfile.2" > "$_tempfile.3" 
# do the rsync command with the exclusion
echo "============================================================="
echo "Starting rsync command with exclusions for sqlite3."
rsync -avz --delete --exclude "*-wal" --exclude="*-shm" --exclude-from="$_tempfile.3" -e "ssh -p \"$SSH_PORT\"" "$SSH_USER"@"$SSH_HOST":"$DOCKER_LOCATION"/ "$BACKUP_LOCATION"/
echo "============================================================="

# backup sql

echo -e "\n\n\n\n"
echo "============================================================="
echo "Starting backups of sqlite3 files."
if [[ -f "$_tempfile.2" && ! -s "$_tempfile.2" ]]; then
  echo "File was empty! There must be no DB's!"
  echo "Exiting..."
  exit 0
fi
while IFS= read -r _file; do
  ssh -n "$SSH_USER"@"$SSH_HOST" -p "$SSH_PORT" "
    sqlite3 \"$_file\" \".backup $_file.backup\" 
  "
  _localfile=$(echo "$_file" | sed "s|$DOCKER_LOCATION|$BACKUP_LOCATION|g")
  rsync -az --delete -e "ssh -p \"$SSH_PORT\"" "$SSH_USER"@"$SSH_HOST":"$_file.backup" "$_localfile"
  ssh -n "$SSH_USER"@"$SSH_HOST" -p "$SSH_PORT" "rm \"$_file.backup\""
  echo "$_file > $_localfile"
done < "$_tempfile.2"
echo "============================================================="


rm -f "$_tempfile" "$_tempfile.2" "$_tempfile.3"
