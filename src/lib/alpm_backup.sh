#!/bin/bash
#===============================================================================
#
#          FILE: alpm_backup.sh
# 
#   DESCRIPTION: yaourt's library to manage backup
# 
#       OPTIONS:  ---
#  REQUIREMENTS:  ---
#          BUGS:  ---
#         NOTES:  ---
#        AUTHOR:   Julien MISCHKOWITZ (wain@archlinux.fr) 
#       VERSION:  1.0
#===============================================================================


# save alpm database (local directory only) in a tar.bz2 file
save_alpm_db(){
	msg $(eval_gettext 'Saving pacman database in $savedir')
	title $(eval_gettext 'Saving pacman database in $savedir')
	local curentdir=`pwd`
	if ! [[ -d "$savedir" && -w "$savedir" ]]; then
		error $(eval_gettext '$savedir is not a writable directory')
		return 1
	fi
	cd $savedir 
	savefile="`pwd`/pacman-`date +%Y-%m-%d_%Hh%M`.tar.bz2"
	cd "$PACMANROOT" 
	tar -cjf "$savefile" "local/"
	(( ! $? )) && msg $(eval_gettext 'Pacman database successfully saved in "$savefile"')
	cd $curentdir 
	return 0
}

# test if file is an alpm database backup
is_an_alpm_backup(){
	title $(gettext 'Analysing backup file')
	msg $(gettext 'Analysing backup file')
	backupdir="$YAOURTTMPDIR/backup/$$"
	mkdir -p "$backupdir"
	tar xjf $1 -C "$backupdir/"
	$PACMANBIN --dbpath "$backupdir/" --query | LC_ALL=C sort > "$YAOURTTMPDIR/backup/backupdb"
	if [[ ! -s "$YAOURTTMPDIR/backup/backupdb" ]]; then
		_file=$1
		error $(eval_gettext '$_file is not a valid alpm database backup')
		return 1
	fi
	return 0
}

# restore alpm database from tar.bz2 file
restore_alpm_db(){
	if ! is_an_alpm_backup "$backupfile"; then
		return 1
	fi
	$PACMANBIN --query | LC_ALL=C sort > "$YAOURTTMPDIR/backup/nowdb"
	msg $(gettext 'New packages installed since backup:')
	LC_ALL=C comm -1 -3 "$YAOURTTMPDIR/backup/backupdb" "$YAOURTTMPDIR/backup/nowdb" 
	echo
	msg $(gettext 'Packages removed or ugpraded since backup:')
	LC_ALL=C comm -2 -3 "$YAOURTTMPDIR/backup/backupdb" "$YAOURTTMPDIR/backup/nowdb" 
	echo
	title "$(gettext 'Warning! Do you want to restore this backup ?')"
	_pid=$$
	msg "$(gettext 'Warning! Do you want to restore this backup ?')"
	msg "$(eval_gettext '\n(local db will be saved in $YAOURTTMPDIR/alpmdb$_pid/)')"
	prompt $(gettext 'If you want to restore this backup, type "yes"')
	read -e 
	[[ "$REPLY" != "$(gettext 'yes')" ]] && return 0
	msg $(gettext 'Deleting pacman DB')
	launch_with_su mv $PACMANROOT/local/ $YAOURTTMPDIR/alpmdb$$
	msg $(gettext 'Copying backup')
	launch_with_su mv $backupdir/local/ $PACMANROOT/local
	msg $(gettext 'Testing the new database')
	$PACMANBIN --query | LC_ALL=C sort > "$YAOURTTMPDIR/backup/nowdb"
	if ! diff "$YAOURTTMPDIR/backup/backupdb" "$YAOURTTMPDIR/backup/nowdb" &> /dev/null; then
	       warning $(gettext 'Your backup is not successfully restored')
	else
		msg $(gettext 'Your backup has been successfully restored')
		echo "`$PACMANBIN -Q | wc -l` packages found"
	fi
	echo $(eval_gettext '(old database is saved in $YAOURTTMPDIR/alpmdb$_pid)')
}

