#!/bin/bash
#set -x
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
type gettext.sh > /dev/null 2>&1 && { . gettext.sh; } || {
	eval_gettext () { echo "$1"; }
	gettext () { echo "$1"; }
}

NAME="yaourt"
VERSION="0.9.3.2"


###################################
### General functions           ###
###################################

usage(){
	echo "$(gettext 'Usage: yaourt <operation> [...]')"
	echo "$(gettext 'operations:')"
	echo -e "\t$(gettext 'yaourt (search pattern|package file)')"
	echo -e "\t$(gettext 'yaourt {-h --help}')"
	echo -e "\t$(gettext 'yaourt {-V --version}')"
	echo -e "\t$(gettext 'yaourt {-Q --query}   [options] [package(s)]')"
	echo -e "\t$(gettext 'yaourt {-R --remove}  [options] [package(s)]')"
	echo -e "\t$(gettext 'yaourt {-S --sync}    [options] [package(s)]')"
	echo -e "\t$(gettext 'yaourt {-U --upgrade} [options] [package(s)]')"
	echo -e "\t$(gettext 'yaourt {-C --clean}   [options]')"
	echo -e "\t$(gettext 'yaourt {-B --backup}  (save directory|restore file)')"
	echo -e "\t$(gettext 'yaourt {-G --getpkgbuild} package')"
	echo -e "\t$(gettext 'yaourt {--stats}')"
	return 0
}
version(){
	plain "$(gettext "yaourt $VERSION is a pacman frontend with AUR support and more")"
	echo "$(gettext 'homepage: http://archlinux.fr/yaourt-en')"
	exit
}
die(){
	local ret=${1:-0}
	# reset term title
	tput sgr0
	(( TERMINALTITLE )) && [[ $DISPLAY ]] &&  echo -n -e "\033]0;$TERM\007"
	exit $ret
}

# Unset package information
free_pkg ()
{
	unset repo pkgname pkgver lver group outofdate votes pkgdesc
}

# usage: pkg_output repo pkgname pkgver lver group outofdate votes pkgdesc
pkg_output()
{
	pkgoutput=""
	[[ ${1#-} ]] && pkgoutput+="${COL_REPOS[$1]:-$COL_O_REPOS}$1/$NO_COLOR"
	[[ $2 ]] && pkgoutput+="${COL_BOLD}$2 ${COL_GREEN}$3${NO_COLOR}"
	if [[ ${4#-} ]]; then
		pkgoutput+=" ${COL_INSTALLED}["
		[[ "$4" != "$3" ]] && pkgoutput+="${COL_RED}$4${COL_INSTALLED}"
		pkgoutput+="$(gettext 'installed')]${NO_COLOR}"
	fi
	[[ ${5#-} ]] && pkgoutput+=" $COL_GROUP($5)$NO_COLOR"
	[[ "$6" = "1" ]] && pkgoutput+=" ${COL_INSTALLED}($(gettext 'Out of Date'))$NO_COLOR"
	[[ ${7#-} ]] && pkgoutput+=" $COL_NUMBER($7)${NO_COLOR}"
	if [[ $8 ]]; then
		str_wrap 4 "$8"
		pkgoutput+="\n$COL_ITALIQUE$strwrap$NO_COLOR"
	fi
}

manage_error(){
	(( ! $# )) || (( ! $1 )) && return 0
	error_package+=("$PKG")
	return 1
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
	#msg "try to launch '${@}' with sudo"
	command=$1
	if is_sudo_allowed "$@"; then
		#echo "Allowed to use sudo $command"
		sudo "$@" || return 1
	else
		(( $UID )) && echo -e $(eval_gettext 'You are not allowed to launch $command with sudo\nPlease enter root password') 1>&2 
		# hack: using tmp instead of YAOURTTMP because error file can't be removed without root password
		errorfile="/tmp/yaourt_error.$RANDOM"
		for i in 1 2 3; do 
			su --shell=/bin/bash --command "$* || touch $errorfile"
			(( $? )) && [[ ! -f "$errorfile" ]] && continue
			[ -f "$errorfile" ] && return 1 || return 0
		done
		return 1
	fi
}

# Define programs arguments
# Usage: program_arg ($dest, $arg)
#	$dest: 1: pacman -S  2: makepkg 4: yaourt -S
program_arg ()
{
	local dest=$1; shift
	(( $dest & 1 )) && PACMAN_S_ARG+=("$@")
	(( $dest & 2 )) && MAKEPKG_ARG+=("$@")
	(( $dest & 4 )) && YAOURT_ARG+=("$@")
	(( $dest & 8 )) && PACMAN_Q_ARG+=("$@")
}

# Wait if lock exists, then launch pacman as root
su_pacman ()
{
	# from nesl247
	if [[ -f "$LOCKFILE" ]]; then
		msg $(gettext 'Pacman is currently in use, please wait.')
		while [[ -f "$LOCKFILE" ]]; do
			sleep 3
		done
	fi
	launch_with_su $PACMANBIN "$@"
}

# Launch pacman and exit
pacman_cmd ()
{
	(( ! $1 )) && exec $PACMANBIN "${ARGSANS[@]}"
	prepare_orphan_list
	su_pacman "${ARGSANS[@]}"  
	local ret=$?
	(( ! ret )) && show_new_orphans
	exit $ret
}


###################################
### Package database functions  ###
###################################
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
	awk '{print $1}' "$INSTALLED_BEFORE.full"> $INSTALLED_BEFORE
}
show_new_orphans(){
	(( ! SHOWORPHANS )) && return
	# search for new orphans after upgrading or after removing (exclude new installed package)
	pacman -Qqt | LC_ALL=C sort > "$ORPHANS_AFTER.tmp"
	pacman -Q | LC_ALL=C sort > "$INSTALLED_AFTER.full"
	awk '{print $1}' "$INSTALLED_AFTER.full" > $INSTALLED_AFTER

	LC_ALL=C comm -1 -3 "$INSTALLED_BEFORE" "$INSTALLED_AFTER" > "$INSTALLED_AFTER.newonly"
	LC_ALL=C comm -2 -3 "$ORPHANS_AFTER.tmp" "$INSTALLED_AFTER.newonly" > $ORPHANS_AFTER

	# show new orphans after removing/upgrading
	neworphans=$(LC_ALL=C comm -1 -3 "$ORPHANS_BEFORE" "$ORPHANS_AFTER" )
	if [[ "$neworphans" ]]; then
		plain $(gettext 'Packages that were installed as dependencies but are no longer required by any installed package:')
		list "$neworphans"
	fi

	# Test local database
	testdb 

	# save original of backup files (pacnew/pacsave)
	if [[ "$MAJOR" != "remove" ]] && (( AUTOSAVEBACKUPFILE )) && ! diff "$INSTALLED_BEFORE.full" "$INSTALLED_AFTER.full" > /dev/null; then
		msg $(gettext 'Searching for original config files to save')
		launch_with_su pacdiffviewer --backup
	fi

}
###################################
### Handle actions              ###
###################################

# Search for packages
# usage: search ($interactive, $lite)
# interactive:1 -> line number
# lite: 1 -> don't print description
# return: global var PKGSFOUND
search ()
{
	local interactive=${1:-0}
	local lite=${2:-0}
	local i=1
	local search_option="${PACMAN_Q_ARG[@]}"
	local format
	(( SEARCH )) && search_option+=" -s" && lite=0
	(( lite )) && format="%1 %n %s %v - - - %g" || format="%1 %n %s %v %l %w %o %g  %d"
	[[ "$MAJOR" = "query" ]] && search_option+=" -Q" || search_option+=" -S"
	(( AURSEARCH )) && search_option+=" -A"
	(( ! SEARCH )) && [[ $args ]] && search_option+=" -i"
	(( QUIET )) && { package-query $search_option -f "%n" "${args[@]}"; return; }
	(( DATE && ! interactive )) && > "$YAOURTTMPDIR/instdate"
	local cmd=(package-query $search_option -f "$format")
	pkgdesc=""
	unset PKGSFOUND
	while read _date pkgname repo pkgver lver votes outofdate group_desc; do 
		group=${group_desc%%  *}
		(( lite )) || pkgdesc=${group_desc#*  }
		PKGSFOUND+=("${repo}/${pkgname}")
		pkg_output "$repo" "$pkgname" "$pkgver" "$lver" \
			"$group" "$outofdate" "$votes" "$pkgdesc"
		if (( interactive )); then
			pkgoutput="${COL_NUMBER}${i}${NO_COLOR} $pkgoutput"
			(( i ++ ))
		fi
		(( DATE && ! interactive )) && echo -e "$_date $pkgoutput" >> "$YAOURTTMPDIR/instdate" || \
			echo -e "$pkgoutput"
	done < <("${cmd[@]}" "${args[@]}")
	if (( DATE && ! interactive )); then
		sort $YAOURTTMPDIR/instdate | awk '{
			printf("%s: %s\n", strftime("%X %x",$1), substr ($0, length($1)+1));
			}'
	fi
}	
# Handle special query
yaourt_query_type ()
{
	title $(gettext 'query packages')
	loadlibrary alpm_query
	for arg in ${args[@]}; do
		searchforpackageswhich "$QUERYTYPE" "$arg"
	done
}
	
# Handle sync
yaourt_sync ()
{
	if (( GROUP || LIST || SEARCH)); then
		(( LIST )) && {
			title $(gettext 'listing all packages in repo(s)')
			msg $(gettext 'Listing all packages in repo(s)')
		}
		(( GROUP )) && title $(gettext 'show groups')
		search 0
		cleanoutput
		return
	elif (( SYSUPGRADE )); then
		loadlibrary abs
		loadlibrary aur
		prepare_orphan_list
		sysupgrade
		# Upgrade all AUR packages or all Devel packages
		(( DEVEL )) && upgrade_devel_package
		(( AURUPGRADE )) && upgrade_from_aur
		show_new_orphans
		return
	fi
	[[ ! $args ]] && { (( ! REFRESH )) && pacman_cmd 1; }
	if [[ $QUERYTYPE ]]; then
		yaourt_query_type
		return
	elif (( INFO )); then
		loadlibrary aur
		for arg in ${args[@]}; do
			title $(eval_gettext 'Informations for $arg')
			_repo="${arg%/*}"
			[[ $_repo = $arg ]] && _repo="$(package-query -1ASif "%r" "$arg")" 
			[[ "$_repo" = "aur" ]] && info_from_aur "${arg#*/}" || abs_pkg+=("$arg") 
		done
		[[ $abs_pkg ]] && $PACMANBIN -S "${PACMAN_S_ARG[@]}" "${abs_pkg[@]}"
		return
	fi
	loadlibrary abs
	loadlibrary aur
	prepare_orphan_list
	sync_packages
	show_new_orphans
	#show package which have not been installed
	if [[ $error_package ]]; then
		warning "$(gettext 'Following packages have not been installed:')"
		echo_wrap 4 "${error_package[*]}"
	fi
}

# Handle query
yaourt_query ()
{
	loadlibrary alpm_query
	# query in a backup file or in current alpm db
	if [[ $BACKUPFILE ]]; then
		loadlibrary alpm_backup
		is_an_alpm_backup "$BACKUPFILE" || die 1
		title $(gettext 'Query backup database')
		msg $(gettext 'Query backup database')
		$PACMANBIN --dbpath "$backupdir/" -Q "${PACMAN_Q_ARG[@]}" "${args[@]}"
		return
	fi
	(( LIST || UPGRADES || INFO )) && pacman_cmd 0
	if (( OWNER )); then
		# pacman will call "which" on futur version
		search_which_package_owns
	elif (( DEPENDS && UNREQUIRED )); then
		search_forgotten_orphans
	elif [[ $QUERYTYPE ]]; then
		yaourt_query_type
	else
		title $(gettext "Query installed packages")
		msg $(gettext "Query installed packages")
		AURSEARCH=0 search 0 1
		#list_installed_packages
	fi
}

###################################
### MAIN PROGRAM                ###
###################################
# Basic init and librairies
YAOURTBIN=$0
source /usr/lib/yaourt/basicfunctions.sh || exit 1 

unset MAJOR ROOT NEWROOT NODEPS SEARCH BUILD REFRESH SYSUPGRADE \
	AUR HOLDVER IGNORE IGNOREPKG IGNOREARCH CLEAN LIST INFO \
	CLEANDATABASE DATE UNREQUIRED FOREIGN OWNER GROUP QUERYTYPE \
	QUIET SUDOINSTALLED AURVOTEINSTALLED CUSTOMIZEPKGINSTALLED EXPLICITE \
	DEPENDS PACMAN_S_ARG MAKEPKG_ARG YAOURT_ARG PACMAN_Q_ARG failed 

# Grab environement options
{
	type -p sudo && SUDOINSTALLED=1
	type -p aurvote && AURVOTEINSTALLED=1
	type -p customizepkg && CUSTOMIZEPKGINSTALLED=1
} &> /dev/null


# Explode arguments (-Su -> -S -u)
ARGSANS=("$@")
unset OPTS
arg=$1
while [[ $arg ]]; do
	if [[ ${arg:0:1} = "-" && ${arg:1:1} != "-" ]]; then
		OPTS+=("-${arg:1:1}")
		(( ${#arg} > 2 )) && arg="-${arg:2}" || { shift; arg=$1; }
	else
		OPTS+=("$arg"); shift; arg=$1
	fi
done
set -- "${OPTS[@]}"
unset arg
unset OPTS

while [[ $1 ]]; do
	case "$1" in
		-R|--remove|-U|--upgrade|-w|--downloadonly)	pacman_cmd 1 ;;
		--asdeps|--needed)  program_arg 1 $1;;
		-c|--clean)         (( CLEAN ++ ));;
		--deps)             DEPENDS=1; program_arg 8 $1;;
		-d)                 DEPENDS=1; NODEPS=1; program_arg 15 $1;;
		-e|--explicit)      EXPLICITE=1; program_arg 8 $1;;
		-m|--foreign)       FOREIGN=1; program_arg 8 $1;;
		-g|--groups)        GROUP=1; program_arg 8 $1;;
		-i|--info)          INFO=1; program_arg 9 $1;;
		-c|--changelog)     pacman_cmd 0;;
		-l|--list)          LIST=1; program_arg 8 $1;;
		--noconfirm)        NOCONFIRM=1; EDITFILES=0; program_arg 7 $1;;
		--nodeps)           NODEPS=1; program_arg 7 $1;;
		-o|--owner)         OWNER=1;;
		-Q|--query)         MAJOR="query";;
		-y|--refresh)       (( REFRESH ++ ));;
		-r|--root)          ROOT=1; shift; NEWROOT="$1"; _opt="'$1'";;
		-S|--sync)          MAJOR="sync";;
		--sysupgrade)       SYSUPGRADE=1; (( UPGRADES ++ ));;
		-t|--unrequired)    UNREQUIRED=1; program_arg 8 $1;;
		-u|--upgrades)      (( UPGRADES ++ ));;
		--holdver)          HOLDVER=1; program_arg 6 $1;;
		-A|--ignorearch)    IGNOREARCH=1; program_arg 6 $1;;
		--aur)              AUR=1; AURUPGRADE=1; AURSEARCH=1;;
		-B|--backup)        MAJOR="backup"; 
			savedir=$(pwd)
			if [[ ${2:0:1} != "-" ]]; then
				[ -d "$2" ] && savedir="$( readlink -e "$2")"
				[ -f "$2" ] && backupfile="$( readlink -e "$2")"
				[[ -z "$savedir" && -z "$backupfile" ]] && error $(gettext 'wrong argument') && die 1
				shift
			fi
			;;
		--backupfile)       COLORMODE="textonly"; shift; BACKUPFILE="$1";;
		-b|--build)         BUILD=1; program_arg 4 $1;;
		-C)                 MAJOR="clean";;
		--conflicts)        QUERYTYPE="conflicts";;
		--database)         CLEANDATABASE=1;;
		--date)             DATE=1;;
		--depends)          QUERYTYPE="depends";;
		--devel)            DEVEL=1;;
		--export)           EXPORT=1; program_arg 4 $1; shift; EXPORTDIR="$1"; program_arg 4 $1;;
		-f|--force)         FORCE=1; program_arg 7 $1;;
		-G|--getpkgbuild)   MAJOR="getpkgbuild"; shift; PKG="$1";;
		-h|--help)          usage; exit 0;;
		--lightbg)          COLORMODE="lightbg";;
		--nocolor)          COLORMODE="nocolor";;
		--provides)         QUERYTYPE="provides";;
		--replaces)         QUERYTYPE="replaces";;
		-s|--search)        SEARCH=1; program_arg 8 $1;;
		--stats)            MAJOR="stats";;
		--sucre)            MAJOR="sync"
			FORCE=1; SYSUPGRADE=1; REFRESH=1; 
			AURUPGRADE=1; DEVEL=1; NOCONFIRM=2; EDITFILES=0
			program_arg 1 "--noconfirm" "--force";;
		--textonly)         COLORMODE="textonly";;
		--tmp)              program_arg 4 $1; shift; TMPDIR="$1"; program_arg 4 $1;;
		-V|version)         version; exit 0;;
		-q)                 QUIET=1; program_arg 5 $1;;

		*)                  args+=("$1") ;; 
	esac
	shift
done

if ! [[ "$MAJOR" ]]; then
	[[ $args ]] || pacman_cmd 0
	# If no action and files as argument, act like -U *
	for file in "${args[@]}"; do
		[[ "${file%.pkg.tar.*}" != "$file" && -r "$file" ]] && filelist+=("$file")
	done
	if [[ $filelist ]]; then
		args=( "${filelist[@]}" )
		MAJOR="upgrade"
	else
		# Interactive search else.
		MAJOR="interactivesearch"
	fi
fi

[[ "$BACKUPFILE" && ! -r "$BACKUPFILE" ]] && { error $(eval_gettext 'Unable to read $BACKUPFILE file'); die 1; }

(( ! SYSUPGRADE && UPGRADES )) && [[ "$MAJOR" = "sync" ]] && SYSUPGRADE=1
if (( EXPORT )); then
	[ -d "$EXPORTDIR" ] || { error $EXPORTDIR $(gettext 'is not a directory'); die 1;}
	[ -w "$EXPORTDIR" ] || { error $EXPORTDIR $(gettext 'is not writable'); die 1;}
	EXPORTDIR=$(readlink -e "$EXPORTDIR")
fi


[ -d "$TMPDIR" ] || { error $TMPDIR $(gettext 'is not a directory'); die 1;}
[ -w "$TMPDIR" ] || { error $TMPDIR $(gettext 'is not writable'); die 1;}
TMPDIR=$(readlink -e "$TMPDIR")
YAOURTTMPDIR="$TMPDIR/yaourt-tmp-$(id -un)"
[[ $COLORMODE ]] && program_arg 4  "--$COLORMODE"
initpath
initcolor

# Refresh
if [[ "$MAJOR" = "sync" ]] && (( REFRESH )); then
	title $(gettext 'synchronizing package databases')
	(( REFRESH > 1 )) && _arg="-Syy" || _arg="-Sy"
	su_pacman $_arg
fi


# Action
case "$MAJOR" in
	clean)
		(( CLEAN )) && _arg="-c" || _arg=""
		if (( CLEANDATABASE )); then
			echo "Option depreceated, please use '{pacman,yaourt} -Sc[c]' instead"
			su_pacman $PACMANBIN -Sc
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
		showpackagestats
		showrepostats
		showdiskusage
		;;

	getpkgbuild)
		title "$(gettext 'get PKGBUILD')"
		loadlibrary aur
		loadlibrary abs
		# don't replace the file if exist
		if [[ -f "./PKGBUILD" ]]; then
			prompt "$(gettext 'PKGBUILD file already exist. Replace ? ')$(yes_no 1)"
			useragrees || die 1
		fi
		#msg "Get PKGBUILD for $PKG"
		build_or_get "$PKG"
		;;

	backup)
		loadlibrary alpm_backup
		if [[ $backupfile ]]; then
			restore_alpm_db || die 1
		elif [[ $savedir ]]; then 
			save_alpm_db || die 1
		fi
		;;
	
	sync) yaourt_sync ;;
	query) yaourt_query ;;
	
	interactivesearch)
		SEARCH=1 search 1 
		[[ $PKGSFOUND ]] || die 0
		prompt $(gettext 'Enter n° (separated by blanks, or a range) of packages to be installed')
		read -ea packagesnum
		[[ $packagesnum ]] || die 0
		for line in ${packagesnum[@]/,/ }; do
			(( line )) || die 1	# not a number, range neither 
			(( ${line%-*}-1 < ${#PKGSFOUND[@]} )) || die 1	# > no package corresponds
			if [[ ${line/-/} != $line ]]; then
				for ((i=${line%-*}-1; i<${line#*-}; i++)); do packages+=(${PKGSFOUND[$i]}); done
			else
				packages+=(${PKGSFOUND[$((line - 1))]})
			fi
		done
		echo 
		exec $YAOURTBIN -S "${YAOURT_ARG[@]}" "${packages[@]}"
		;;
	*) pacman_cmd 0 ;;
esac
die $failed

# vim: set ts=4 sw=4 noet: 
