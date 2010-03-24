#!/bin/bash
#
#   Yaourt (Yet Another Outil Utilisateur): More than a Pacman frontend
#
#   Copyright (C) 2008, Julien MISCHKOWITZ wain@archlinux.fr
#   Homepage: http://www.archlinux.fr/yaourt-en
#   Based on:
#   yogurt from Federico Pelloni <federico.pelloni@gmail.com>
#   srcpac from Jason Chu  <jason@archlinux.org>
#   pacman from Judd Vinet <jvinet@zeroflux.org>
#
#       This program is free software; you can redistribute it and/or modify
#       it under the terms of the GNU General Public License as published by
#       the Free Software Foundation; either version 2 of the License, or
#       (at your option) any later version.
#       
#       This program is distributed in the hope that it will be useful,
#       but WITHOUT ANY WARRANTY; without even the implied warranty of
#       MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#       GNU General Public License for more details.
#       
#       You should have received a copy of the GNU General Public License
#       along with this program; if not, write to the Free Software
#       Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston,
#       MA 02110-1301, USA.
export TEXTDOMAINDIR=/usr/share/locale
export TEXTDOMAIN=yaourt
type gettext.sh > /dev/null 2>&1 && { . gettext.sh; } || eval_gettext () { echo "$1"; }

NAME="yaourt"
VERSION="0.9.2.6"
AUR_URL="http://aur.archlinux.org/packages.php?setlang=en&do_Search=SeB=nd&L=2&C=0&PP=100&K="
AUR_URL3="http://aur.archlinux.org/packages.php?setlang=en&ID="
ABS_URL="http://archlinux.org/packages/search/?category=all&limit=99000"
ABS_REPOS_URL="http://repos.archlinux.org/viewvc.cgi"
[ -z "$LC_ALL" ] && export LC_ALL=$LANG


###################################
### General functions           ###
###################################

usage(){
	echo "$(eval_gettext 'Usage: yaourt <operation> [...]')"
	echo "$(eval_gettext 'operations:')"
	echo -e "$(eval_gettext '\tyaourt (search pattern|package file)')"
	echo -e "$(eval_gettext '\tyaourt {-h --help}')"
	echo -e "$(eval_gettext '\tyaourt {-V --version}')"
	echo -e "$(eval_gettext '\tyaourt {-Q --query}   [options] [package(s)]')"
	echo -e "$(eval_gettext '\tyaourt {-R --remove}  [options] [package(s)]')"
	echo -e "$(eval_gettext '\tyaourt {-S --sync}    [options] [package(s)]')"
	echo -e "$(eval_gettext '\tyaourt {-U --upgrade} [options] [package(s)]')"
	echo -e "$(eval_gettext '\tyaourt {-C --clean}   [options]')"
	echo -e "$(eval_gettext '\tyaourt {-B --backup}  (save directory|restore file)')"
	echo -e "$(eval_gettext '\tyaourt {-G --getpkgbuild} package')"
	echo -e "$(eval_gettext '\tyaourt {--stats}')"
	return 0
}
version(){
	plain "$(eval_gettext 'yaourt $VERSION is a pacman frontend with AUR support and more')"
	echo "$(eval_gettext 'homepage: http://archlinux.fr/yaourt-en')"
	echo "$(eval_gettext '      Copyright (C) 2008 Julien MISCHKOWITZ <wain@archlinux.fr>')"
	echo "$(eval_gettext '      This program may be freely redistributed under')"
	echo "$(eval_gettext '      the terms of the GNU General Public License')"
	exit
}
pacman_queuing(){
	# from nesl247
	if [ -f "$LOCKFILE" ]; then
		msg $(eval_gettext 'Pacman is currently in use, please wait.')
		while [ -f "$LOCKFILE" ]; do
			sleep 3
		done
	fi
}
title(){
	if [ $TERMINALTITLE -eq 0 -o -z "$DISPLAY" ]; then
		return 0
	fi
	case $TERM in
		rxvt*|xterm*|aterm)
		echo -n -e "\033]0;yaourt: $@\007"
		;;
	esac
}
die(){
	# reset term title
	tput sgr0
	if [ $TERMINALTITLE -eq 1 -a ! -z "$DISPLAY" ]; then
		echo -n -e "\033]0;$TERM\007"
	fi
	exit $1
}

manage_error(){
	if [ $1 -ne 0 ]; then
		error_package[${#error_package[@]}]="$PKG"
		return 1
	fi
	return 0
}

# Check if sudo is allowed for given command
is_sudo_allowed()
{
	if (( SUDOINSTALLED )); then
		sudo -nl "$@" &> /dev/null || \
			(sudo -v && sudo -l "$@") &>/dev/null && return 0
	fi
	return 1
}

launch_with_su(){
	# try to launch $1 with sudo, else prompt for root password
	#msg "try to launch '${@}' with sudo"
	command=`echo $* | awk '{gsub(/LC_ALL=\"C\"/,""); print $1}'`

	if is_sudo_allowed "$command"; then
		#echo "Allowed to use sudo $command"
		sudo $@ || return 1
	else
		UID_ROOT=0
		if [ "$UID" -ne "$UID_ROOT" ]
		then
			# command output can be parsed
			echo -e $(eval_gettext 'You are not allowed to launch $command with sudo\nPlease enter root password') 1>&2 
		fi
		# hack: using tmp instead of YAOURTTMP because error file can't be removed without root password
		errorfile="/tmp/yaourt_error.$RANDOM"
		for i in 1 2 3; do 
			su --shell=/bin/bash --command "$* || touch $errorfile"
			if [ $? -eq 1 ] && [ ! -f "$errorfile" ]; then
				continue
			else
				[ -f "$errorfile" ] && return 1 || return 0
			fi
		done
		return 1
	fi
}

###################################
### Package database functions  ###
###################################
isinstalled(){
	pacman -Qq $1 &>/dev/null
}
isavailable(){
	package-query -1Siq $1 || package-query -1Sq -t provides $1
}
isprovided(){
	package-query -Qq -t provides $1 
}
pkgversion(){
	# searching for version of the given package
	#grep -srl --line-regexp --include="desc" "$1" "$PACMANROOT/local" | xargs grep -A 1 "^%VERSION%$" | tail -n 1
	package-query -Qif "%v" $1
}
pkgdescription(){
	package-query -1Sif "%d" $1
}
sourcerepository(){
	# find the repository where the given package came from
	package-query -1SQif "%r" $1 
}

prepare_orphan_list(){
	(( ! SHOWORPHANS )) && return
	# Prepare orphan list before upgrade and remove action
	mkdir -p "$YAOURTTMPDIR/orphans"
	ORPHANS_BEFORE="$YAOURTTMPDIR/orphans/orphans_before.$$"
	ORPHANS_AFTER="$YAOURTTMPDIR/orphans/orphans_after.$$"
	INSTALLED_BEFORE="$YAOURTTMPDIR/orphans/installed_before.$$"
	INSTALLED_AFTER="$YAOURTTMPDIR/orphans/installed_after.$$"
	# search orphans before removing or upgrading
	pacman -Qqt | LC_ALL=C sort > $ORPHANS_BEFORE
	# store package list before
	pacman -Q | LC_ALL=C sort > "$INSTALLED_BEFORE.full"
	cat "$INSTALLED_BEFORE.full" | awk '{print $1}' > $INSTALLED_BEFORE
}
show_new_orphans(){
	(( ! SHOWORPHANS )) && return
	# search for new orphans after upgrading or after removing (exclude new installed package)
	pacman -Qqt | LC_ALL=C sort > "$ORPHANS_AFTER.tmp"
	pacman -Q | LC_ALL=C sort > "$INSTALLED_AFTER.full"
	cat "$INSTALLED_AFTER.full" | awk '{print $1}'  > $INSTALLED_AFTER

	LC_ALL=C comm -1 -3 "$INSTALLED_BEFORE" "$INSTALLED_AFTER" > "$INSTALLED_AFTER.newonly"
	LC_ALL=C comm -2 -3 "$ORPHANS_AFTER.tmp" "$INSTALLED_AFTER.newonly" | awk '{print $1}' > $ORPHANS_AFTER

	# show new orphans after removing/upgrading
	neworphans=$(LC_ALL=C comm -1 -3 "$ORPHANS_BEFORE" "$ORPHANS_AFTER" | awk '{print $1}' )
	if [ ! -z "$neworphans" ]; then
		plain $(eval_gettext 'Packages that were installed as dependencies but are no longer required by any installed package:')
		list "$neworphans"
	fi

	# testdb
	LC_ALL=C testdb | grep -v "Checking the integrity of the local database"

	# save original of backup files (pacnew/pacsave)
	if [ "$MAJOR" != "remove" ] && [ $AUTOSAVEBACKUPFILE -eq 1 ] && ! diff "$INSTALLED_BEFORE.full" "$INSTALLED_AFTER.full" > /dev/null; then
		msg $(eval_gettext 'Searching for original config files to save')
		launch_with_su "pacdiffviewer --backup"
	fi

}
cleandatabase(){
	# search in /var/lib/pacman/ for repositories
	# parmis ces dépôts, quels sont les paquetages aussi présents sur le système
	# si les paquets sont installés sur le systèmes, est-ce bien de CE dépôt qu'ils viennent ?
	# if repository is not used => remove it
	title "$(eval_gettext 'clean pacman database')"
	echo "$(eval_gettext 'Please wait...')"
	repositories=( `LC_ALL="C"; pacman --debug 2>/dev/null| grep "debug: opening database '" | awk '{print $4}' |uniq| tr -d "'"| grep -v 'local'` )
	downloadedrepositories=( `ls --almost-all $PACMANROOT/sync | grep -v "\(lost+found\|.*.db.tar.gz\)"` )
	for repository in ${downloadedrepositories[@]}; do
		used=0
		for pkg in `ls "$PACMANROOT/sync/$repository"`;do
			if [ -d "$PACMANROOT/local/$pkg" ];then
				pkgname=$(grep -A 1 "%NAME%" -F "$PACMANROOT/local/$pkg/desc" | tail -n 1)
				if [ "$(sourcerepository $pkgname)" = "$repository" ]; then
					used=1
					break
				fi
			fi
		done

		if [ $used -eq 0 ];then
			for repoinconfig in ${repositories[@]}; do
				if [ "$repository" = "$repoinconfig" ]; then
					break
				fi
			done
			if [ "$repository" = "$repoinconfig" ]; then
				#echo $(eval_gettext '$repository peut être retiré du fichier pacman.conf')
				unused_repository[${#unused_repository[@]}]=$repository
			else
				#echo $(eval_gettext '$repository peut être supprimé')
				old_repository[${#old_repository[@]}]=$repository
			fi
			continue
		fi
	done

	if [ ${#old_repository[@]} -gt 0 ]; then
		msg $(eval_gettext 'Some directories in /var/lib/pacman/sync are no more used and should be removed:')
		echo ${old_repository[@]}
		prompt "$(eval_gettext 'Do you want to delete these directories ? ')$(yes_no 2)"
		if [ "`userinput`" = "Y" ]; then
			cd $PACMANROOT/sync
			launch_with_su "rm -r ${old_repository[*]}"
			if [ $? -eq 0 ]; then
				msg "$(eval_gettext 'Your database is now optimized')"
			else
				error $(eval_gettext 'Problem when deleting directories')
			fi
		fi
	fi

	if [ ${#unused_repository[@]} -gt 0 ]; then
		echo
		msg "$(eval_gettext 'Some repositories in pacman.conf are no more used and can be removed:')"
		echo ${unused_repository[@]}
	fi

}

###################################
### Search functions            ###
###################################

# Search for packages
# usage: search ($interactive, $result_file)
# return: none
search ()
{
	local interactive=${1:-0}
	local searchfile="$2"
	(( interactive )) && [ -z "$searchfile" ] && return 1
	i=1
	local search_option=""
	(( AURSEARCH )) && search_option="$search_option -A"
	[ "$MAJOR" = "query" ] && search_option="$search_option -Q" || search_option="$search_option -S"
	(( LIST )) && search_option="$search_option -l"
	(( GROUP )) && search_option="$search_option -g"
	(( SEARCH )) && search_option="$search_option -s"
	(( QUIET )) && package-query $search_option -f "%n" "${args[@]}" && return
	package-query $search_option -f "%n %r %v %l %g %w %o %d" "${args[@]}" |
	while read package repository version lversion group votes outofdate description ; do
		(( interactive )) && echo "${repository}/${package}" >> $searchfile
		line=`colorizeoutputline ${repository}/${NO_COLOR}${COL_BOLD}${package} ${COL_GREEN}${version}${NO_COLOR}`
		if [ "$lversion" != "-" ]; then
			line="$line ${COL_INSTALLED}["
			if [ "$lversion" = "$version" ];then
				line="$line$(eval_gettext 'installed')"
			else
				line="$line${COL_RED}$lversion${COL_INSTALLED} $(eval_gettext 'installed')"
			fi
			line="${line}]${NO_COLOR}"
		fi
		[ "$group" != "-" ] && \
			line="$line${NO_COLOR} $COL_GROUP($group)$NO_COLOR"
		[ "$outofdate" != "-" ] && [ $outofdate -eq 1 ] && \
			line="$line${NO_COLOR} ${COL_INSTALLED}($(eval_gettext 'Out of Date'))"
		[ "$votes" != "-" ] && \
			line="$line${NO_COLOR} $COL_NUMBER($votes)${NO_COLOR}"
		[ $interactive -eq 1 ] && echo -ne "${COL_NUMBER}${i}${NO_COLOR} "
		echo -e "$line"
		echo -e "  $COL_ITALIQUE$description$NO_COLOR"
		(( i ++ ))
	done

	cleanoutput
}	


###################################
### MAIN PROGRAM                ###
###################################
# Basic init and librairies
source /usr/lib/yaourt/basicfunctions.sh || exit 1 

# grab environement options
if [ `type -p sudo` ]; then SUDOINSTALLED=1; fi
if [ `type -p versionpkg` ]; then VERSIONPKGINSTALLED=1; fi
if [ `type -p aurvote` ]; then AURVOTEINSTALLED=1; fi
if [ `type -p customizepkg` ]; then CUSTOMIZEPKGINSTALLED=1; fi

# Refresh
# todo: find a better way to remove "y"
if [ "$MAJOR" = "sync" ] && (( REFRESH )); then
	title $(eval_gettext 'synchronizing package databases')
	(( REFRESH > 1 )) && _arg="-Syy" || _arg="-Sy"
	ARGSANS="${ARGSANS// -y / }"
	ARGSANS="${ARGSANS// --refresh / }"
	BUILDPROGRAM="${BUILDPROGRAM// -y / }"
	BUILDPROGRAM="${BUILDPROGRAM// --refresh / }"
	pacman_queuing;	launch_with_su $PACMANBIN $_arg
fi


# Action
case "$MAJOR" in
	remove)
		#msg "Remove"
		title $(eval_gettext 'remove packages')
		prepare_orphan_list
		# remove with pacman
		pacman_queuing;	launch_with_su "$PACMANBIN $ARGSANS ${args[*]}"
		show_new_orphans
		;;

	clean)
		#msg "Clean"
		(( CLEAN )) && _arg="-c" || _arg=""
		if (( CLEANDATABASE )); then
			cleandatabase
		else
			launch_with_su pacdiffviewer $_arg
		fi
		;;

	stats)
		loadlibrary pacman_conf
		loadlibrary alpm_stats
		tmp_files="$YAOURTTMPDIR/stats.$$"
		mkdir -p "$tmp_files" || die 1
		buildpackagelist
		#clear
		showpackagestats
		showrepostats
		showdiskusage
		;;

	getpkgbuild)
		title "$(eval_gettext 'get PKGBUILD')"
		loadlibrary aur
		loadlibrary abs
		# don't replace the file if exist
		if [ -f "./PKGBUILD" ]; then
			prompt "$(eval_gettext 'PKGBUILD file already exist. Replace ? ')$(yes_no 1)"
			[ "`userinput`" = "N" ] && die 1
		fi
		#msg "Get PKGBUILD for $PKG"
		build_or_get "$PKG"
		;;

	backup)
		loadlibrary alpm_backup
		[ -n "$savedir" ] && { save_alpm_db || die 1; }
		[ -n "$backupfile" ] && { restore_alpm_db || die 1; }
		;;
	
	sync)
		if (( GROUP )) || (( LIST )) || ((SEARCH)); then
			(( LIST )) && {
				title $(eval_gettext 'listing all packages in repos')
				msg $(eval_gettext 'Listing all packages in repos')
			}
			(( GROUP )) && title $(eval_gettext 'show groups')
			search 0
			cleanoutput
		elif (( QUERYWHICH )) && [ -n "$QUERYTYPE" ]; then
			if [ ${#args[@]} -lt 1 ]; then die 1; fi
			title $(eval_gettext 'query packages')
			loadlibrary alpm_query
			for arg in ${args[@]}; do
				msg $(eval_gettext 'packages which '$QUERYTYPE' on $arg:')
				searchforpackageswhich "$QUERYTYPE" "$arg"
			done
		elif (( CLEAN )); then 
			#msg "clean sources files"
			launch_with_su "$PACMANBIN $ARGSANS ${args[*]}"
		elif (( INFO )); then
			#msg "Information"
			loadlibrary aur
			for arg in ${args[@]}; do
				title $(eval_gettext 'Information for $arg')
				_repo="${arg%/*}"
				[ -z "$_repo" ] && _repo="$(package-query -1ASif "%r" "$arg")" 
				if [ "$_repo" = "aur" ]; then info_from_aur "${arg#*/}" ; else $PACMANBIN -Si $arg; fi
			done
		elif (( PRINTURIS )); then
			$PACMANBIN -Sp "${args[@]}"
		elif (( ! SYSUPGRADE )) && (( ! ${#args[@]} )) && (( ! REFRESH )); then
			prepare_orphan_list
			msg $(eval_gettext 'yaourt: no argument')
			pacman_queuing;	eval $PACMANBIN $ARGSANS
			show_new_orphans
		elif (( ! SYSUPGRADE )); then
			#msg "Install ($ARGSANS)"
			loadlibrary abs
			loadlibrary aur
			sync_packages
		elif (( SYSUPGRADE )); then
			#msg "System Upgrade"
			loadlibrary abs
			loadlibrary aur
			sysupgrade
			# Upgrade all AUR packages or all Devel packages
			(( DEVEL )) && upgrade_devel_package
			(( AURUPGRADE )) && upgrade_from_aur
			#show package which have not been installed
			if [ ${#error_package[@]} -gt 0 ]; then
				echo -e "${COL_YELLOW}" $(eval_gettext 'Following packages have not been installed:')"${NO_COLOR}"
				echo "${error_package[*]}"
			fi
			show_new_orphans
		fi
		;;

	query)
		# action = query
		loadlibrary alpm_query
		# query in a backup file or in current alpm db
		if [ ! -z "$BACKUPFILE" ]; then
			loadlibrary alpm_backup
			is_an_alpm_backup "$BACKUPFILE" || die 1
			title $(eval_gettext 'Query backup database')
			msg $(eval_gettext 'Query backup database')
			PACMANROOT="$backupdir/"
			eval $PACMANBIN --dbpath "$backupdir/" $ARGSANS ${args[*]}
		elif (( OWNER )); then
			search_which_package_owns
		elif (( DEPENDS )) && (( UNREQUIRED )); then
			search_forgotten_orphans
		elif (( SEARCH )); then
			AURSEARCH=0 search 0
		elif (( LIST )) || (( INFO )) || (( UPGRADES )) || (( CHANGELOG )); then
			# just run pacman -Ql or pacman -Qi
			eval $PACMANBIN $ARGSANS ${args[*]}
		else
			list_installed_packages
		fi
		;;
	
	interactivesearch)
		tmp_files="$YAOURTTMPDIR/search"
		mkdir -p $tmp_files || die 1
		searchfile=$tmp_files/interactivesearch.$$>$searchfile || die 1
		SEARCH=1 search 1 "$searchfile"
		[ ! -s "$searchfile" ] && die 0
		prompt $(eval_gettext 'Enter n° (separated by blanks, or a range) of packages to be installed')
		read -ea packagesnum
		(( ${#packagesnum[@]} )) && die 0
		for line in ${packagesnum[@]}; do
			if echo $line | grep -q "[0-9]-[0-9]"; then
				for multipackages in `seq ${line/-/ }`;do
					packages[${#packages[@]}]=$(sed -n ${multipackages}p $searchfile)
				done
			elif echo $line | grep -q "[0-9]"; then
				packages[${#packages[@]}]=$(sed -n ${line}p $searchfile)
			else
				die 1
			fi
		done
		$BUILDPROGRAM ${packages[@]}
		;;
	
	*)
		#msg "Other action"
		prepare_orphan_list
		pacman_queuing;	launch_with_su "$PACMANBIN $ARGSANS ${args[*]}" || { plain $(eval_gettext 'press a key to continue'); read; }
		show_new_orphans
		;;
esac
die $failed
