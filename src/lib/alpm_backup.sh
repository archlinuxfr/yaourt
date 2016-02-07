#!/bin/bash
#
# alpm_backup.sh : Manage database backup/restore
# This file is part of Yaourt (http://archlinux.fr/yaourt-en)

# save alpm database (local directory only) in a tar.bz2 file
# $1: directory
save_alpm_db() {
	local savedir="$1" savefile="$1/pacman-$(date +%Y-%m-%d_%Hh%M).tar.bz2"
	msg $(_gettext 'Saving pacman database in %s' "$savedir")
	title $(_gettext 'Saving pacman database in %s' "$savedir")
	bsdtar -cjf "$savefile" -C "${P[dbpath]}" "local/" && \
	    msg $(_gettext 'Pacman database successfully saved in %s' "$savefile")
}

# test if file is an alpm database backup
# $1: file
is_an_alpm_backup() {
	title $(gettext 'Analysing backup file')
	msg $(gettext 'Analysing backup file')
	local backupdb="$YAOURTTMPDIR/backupdb"
	backupdir="$YAOURTTMPDIR/backup/$(md5sum "$1" | awk '{print $1}')"
	if [[ ! -d "$backupdir" ]]; then	# decompress backup only once
		mkdir -p "$backupdir" || return 1
		bsdtar -xjf "$1" -C "$backupdir/"
		ln -s "${P[dbpath]}/sync" "$backupdir/"
	fi
	pacman_parse --dbpath "$backupdir/" --query | LC_ALL=C sort > "$backupdb"
	if [[ ! -s "$backupdb" ]]; then
		error $(_gettext '%s is not a valid alpm database backup' "$1")
		return 1
	fi
	return 0
}

# restore alpm database from tar.bz2 file
# $1: file
restore_alpm_db() {
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
	msg "$(_gettext '(local db will be saved in %s)' "$savedb")"
	prompt $(gettext 'If you want to restore this backup, type "yes"')
	read -e
	[[ "$REPLY" != "$(gettext 'yes')" ]] && return 0
	msg $(gettext 'Deleting pacman DB')
	launch_with_su mv "${P[dbpath]}/local/" "$savedb"
	msg $(gettext 'Copying backup')
	launch_with_su mv "$backupdir/local/" "${P[dbpath]}/local" && \
		launch_with_su rm -rf  "$backupdir"
	msg $(gettext 'Testing the new database')
	pacman_parse --query | LC_ALL=C sort > "$nowdb"
	if ! diff "$backupdb" "$nowdb" &> /dev/null; then
		warning $(gettext 'Your backup is not successfully restored')
	else
		msg $(gettext 'Your backup has been successfully restored')
		msg "$(cat "$nowdb" | wc -l) $(gettext 'packages found')"
	fi
	msg $(_gettext '(old database is saved in %s)' "$savedb")
}

# save ($1 is a dir) or restore ($1 is a file) alpm database
yaourt_backup() {
	local dest="$1"
	[[ $dest ]] || dest="$PWD"
	if [[ -d "$dest" && -w "$dest" ]]; then
		save_alpm_db "$dest"
	elif [[ -f "$dest" && -r "$dest" ]]; then
		restore_alpm_db "$dest"
	else
		error $(gettext 'wrong argument')
	fi
}

# vim: set ts=4 sw=4 noet:
