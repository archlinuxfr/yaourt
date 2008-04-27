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
	msg "Saving pacman database in $savedir"
	title "Saving pacman database in $savedir"
	if [ ! -w "$savedir" ]; then
		error "$savedir is not a writable directory"; return 1
	fi
	savefile="pacman-`date +%Y-%m-%d_%Hh%M`.tar.bz2"
	cd "$PACMANROOT"
	tar -cjf "$savedir/$savefile" "local/"
	[ $? -eq 0 ] && msg "Pacman database successfully saved in \"$savedir/$savefile\""
	cd - >/dev/null
	return 0
}

# test if file is an alpm database backup
is_an_alpm_backup(){
	title "Analysing backup file"
	msg "Analysing backup file"
	backupdir="$YAOURTTMPDIR/backup/$$"
	mkdir -p "$backupdir"
	tar xjf $1 -C "$backupdir/"
	eval $PACMANBIN --dbpath "$backupdir/" --query | sort > "$YAOURTTMPDIR/backup/backupdb"
	if [ ! -s "$YAOURTTMPDIR/backup/backupdb" ]; then
		error "$1 is not a valid alpm database backup"
		return 1
	fi
	return 0
}

# restore alpm database from tar.bz2 file
restore_alpm_db(){
	if ! is_an_alpm_backup "$backupfile"; then
		return 1
	fi
	eval $PACMANBIN --query | sort > "$YAOURTTMPDIR/backup/nowdb"
	msg "New packages installed since backup:"
	comm -1 -3 "$YAOURTTMPDIR/backup/backupdb" "$YAOURTTMPDIR/backup/nowdb" 
	echo
	msg "Packages removed or ugpraded since backup:"
	comm -2 -3 "$YAOURTTMPDIR/backup/backupdb" "$YAOURTTMPDIR/backup/nowdb" 
	echo
	title "Warning! Do you want to restore this backup ?"
	msg "Warning! Do you want to restore this backup ?\n(local db will be saved in $YAOURTTMPDIR/alpmdb$$/)"
	prompt "If you want to restore this backup, type \"yes\"" 
	read -e
	[ "$REPLY" != "yes" ] && return 0
	msg "Deleting pacman DB"
        launch_with_su "mv $PACMANROOT/local/ $YAOURTTMPDIR/alpmdb$$"
	msg "Copying backup"
	launch_with_su "mv $backupdir/local/ $PACMANROOT/local"
	msg "Testing the new database"
	eval $PACMANBIN --query | sort > "$YAOURTTMPDIR/backup/nowdb"
	if [ `diff "$YAOURTTMPDIR/backup/backupdb" "$YAOURTTMPDIR/backup/nowdb" | wc -l` -gt 0 ]; then
	       warning "Your backup is not successfully restored"	
	else
	       msg "Your backup has been successfully restored"
	       echo "`$PACMANBIN -Q | wc -l` packages found"
	fi
	echo "(old database is saved in $YAOURTTMPDIR/alpmdb$$)"
}

