#!/bin/bash
#
# alpm_backup.sh : Manage database backup/restore
# This file is part of Yaourt (http://archlinux.fr/yaourt-en)

# save alpm database (local directory only) in a tar.bz2 file
# $1: directory
save_alpm_db(){
	local savedir="$1" savefile="$1/pacman-$(date +%Y-%m-%d_%Hh%M).tar.bz2"
	msg $(eval_gettext 'Saving pacman database in $savedir')
	title $(eval_gettext 'Saving pacman database in $savedir')
	bsdtar -cjf "$savefile" -C "$PACMANDB" "local/" && \
	    msg $(eval_gettext 'Pacman database successfully saved in "$savefile"')
}

# test if file is an alpm database backup
# $1: file
is_an_alpm_backup(){
	title $(gettext 'Analysing backup file')
	msg $(gettext 'Analysing backup file')
	local backupdb="$YAOURTTMPDIR/backupdb"
	backupdir="$YAOURTTMPDIR/backup/$(md5sum "$1" | awk '{print $1}')"
	if [[ ! -d "$backupdir" ]]; then	# decompress backup only once
		mkdir -p "$backupdir" || return 1
		tar -xjf "$1" -C "$backupdir/"
	fi
	pacman_parse --dbpath "$backupdir/" --query | LC_ALL=C sort > "$backupdb"
	if [[ ! -s "$backupdb" ]]; then
		_file="$1"
		error $(eval_gettext '$_file is not a valid alpm database backup')
		return 1
	fi
	return 0
}

# restore alpm database from tar.bz2 file
# $1: file
restore_alpm_db(){
	local backupdb="$YAOURTTMPDIR/backupdb"
	local nowdb="$YAOURTTMPDIR/nowdb"
	local savedb="$YAOURTTMPDIR/backup/alpmdb$$"
	mkdir -p "$savedb" || return 1
	is_an_alpm_backup "$1" || return 1
	pacman_parse --query | LC_ALL=C sort > "$nowdb"
	msg $(gettext 'New packages installed since backup:')
	LC_ALL=C comm -13 "$backupdb" "$nowdb" 
	echo
	msg $(gettext 'Packages removed or ugpraded since backup:')
	LC_ALL=C comm -23 "$backupdb" "$nowdb" 
	echo
	title "$(gettext 'Warning! Do you want to restore this backup ?')"
	msg "$(gettext 'Warning! Do you want to restore this backup ?')"
	msg "$(eval_gettext '(local db will be saved in $savedb)')"
	prompt $(gettext 'If you want to restore this backup, type "yes"')
	read -e 
	[[ "$REPLY" != "$(gettext 'yes')" ]] && return 0
	msg $(gettext 'Deleting pacman DB')
	launch_with_su mv "$PACMANDB/local/" "$savedb"
	msg $(gettext 'Copying backup')
	launch_with_su mv "$backupdir/local/" "$PACMANDB/local" && \
		launch_with_su rm -rf  "$backupdir" 
	msg $(gettext 'Testing the new database')
	pacman_parse --query | LC_ALL=C sort > "$nowdb"
	if ! diff "$backupdb" "$nowdb" &> /dev/null; then
		warning $(gettext 'Your backup is not successfully restored')
	else
		msg $(gettext 'Your backup has been successfully restored')
		msg "$(cat "$nowdb" | wc -l) $(gettext 'packages found')"
	fi
	msg $(eval_gettext '(old database is saved in $savedb)')
}

# save ($1 is a dir) or restore ($1 is a file) alpm database
yaourt_backup()
{
	local dest="$1"
	[[ $dest ]] || dest="$(pwd)"
	if [[ -d "$dest" && -w "$dest" ]]; then
		save_alpm_db "$dest"
	elif [[ -f "$dest" && -r "$dest" ]]; then
		restore_alpm_db "$dest"
	else
		error $(gettext 'wrong argument')
	fi
}
# vim: set ts=4 sw=4 noet: 
