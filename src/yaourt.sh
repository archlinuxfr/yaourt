#!/bin/bash
#
# Yaourt (Yet Another Outil Utilisateur): More than a Pacman frontend
#
# Copyright (c) 2008-2010 Julien MISCHKOWITZ <wain@archlinux.fr>
# Copyright (c) 2010 tuxce <tuxce.net@gmail.com>
#
# This program is free software; you can redistribute it and/or modify it
# under the terms of the GNU Library General Public License as published
# by the Free Software Foundation; either version 2, or (at your option)
# any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <http://www.gnu.org/licenses/>.
#
#set -x
export TEXTDOMAINDIR=/usr/share/locale
export TEXTDOMAIN=yaourt
type gettext.sh > /dev/null 2>&1 && { . gettext.sh; } || {
	eval_gettext () { eval echo $1; }
	gettext () { echo "$1"; }
}

NAME="yaourt"
VERSION="0.9.4.4"


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
	echo "$(gettext "yaourt $VERSION is a pacman frontend with AUR support and more")"
	echo "$(gettext 'homepage: http://archlinux.fr/yaourt-en')"
	exit
}
die(){
	local ret=${1:-0}
	# reset term title
	(( TERMINALTITLE )) && [[ $DISPLAY ]] &&  echo -n -e "\033]0;$TERM\007"
	exit $ret
}

# usage: pkg_output repo pkgname pkgver lver group outofdate votes pkgdesc
T_INSTALLED="$(gettext 'installed')"
T_OUTOFDATE="$(gettext 'Out of Date')"
pkg_output()
{
	pkgoutput=""
	[[ ${1#-} ]] && pkgoutput+="${COL_REPOS[$1]:-$COL_O_REPOS}$1/$NO_COLOR"
	[[ $2 ]] && pkgoutput+="${COL_BOLD}$2 ${COL_GREEN}$3${NO_COLOR}"
	if [[ ${4#-} ]]; then
		pkgoutput+=" ${COL_INSTALLED}["
		[[ "$4" != "$3" ]] && pkgoutput+="${COL_RED}$4${COL_INSTALLED} "
		pkgoutput+="$T_INSTALLED]${NO_COLOR}"
	fi
	[[ ${5#-} ]] && pkgoutput+=" $COL_GROUP($5)$NO_COLOR"
	[[ "$6" = "1" ]] && pkgoutput+=" ${COL_INSTALLED}($T_OUTOFDATE)$NO_COLOR"
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
		(( SUDONOVERIF )) && return 0
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
# dest:
A_PS=1 A_M=2 A_Y=4 A_PQ=8 A_PC=16 A_PKC=32
program_arg ()
{
	local dest=$1; shift
	(( dest & A_PS ))  && PACMAN_S_ARG+=("$@")
	(( dest & A_M ))  && MAKEPKG_ARG+=("$@")
	(( dest & A_Y ))  && YAOURT_ARG+=("$@")
	(( dest & A_PQ ))  && PACMAN_Q_ARG+=("$@")
	(( dest & A_PC )) && PACMAN_C_ARG+=("$@")
	(( dest & A_PKC )) && PKGQUERY_C_ARG+=("$@")
}

# Wait while pacman locks exists
pacman_queue()
{
	# from nesl247
	if [[ -f "$LOCKFILE" ]]; then
		msg $(gettext 'Pacman is currently in use, please wait.')
		while [[ -f "$LOCKFILE" ]]; do
			sleep 3
		done
	fi
}
# launch pacman as root
su_pacman ()
{
	pacman_queue; launch_with_su $PACMANBIN "${PACMAN_C_ARG[@]}" "$@"
}

# Launch pacman and exit
pacman_cmd ()
{
	(( ! $1 )) && exec $PACMANBIN "${ARGSANS[@]}"
	prepare_orphan_list
	pacman_queue; launch_with_su $PACMANBIN "${ARGSANS[@]}"  
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
	pacman_parse -Qqt | LC_ALL=C sort > $ORPHANS_BEFORE
	# store package list before
	pacman_parse -Q | LC_ALL=C sort > "$INSTALLED_BEFORE.full"
	awk '{print $1}' "$INSTALLED_BEFORE.full"> $INSTALLED_BEFORE
}
show_new_orphans(){
	(( ! SHOWORPHANS )) && return
	# search for new orphans after upgrading or after removing (exclude new installed package)
	pacman_parse -Qqt | LC_ALL=C sort > "$ORPHANS_AFTER.tmp"
	pacman_parse -Q | LC_ALL=C sort > "$INSTALLED_AFTER.full"
	awk '{print $1}' "$INSTALLED_AFTER.full" > $INSTALLED_AFTER

	LC_ALL=C comm -1 -3 "$INSTALLED_BEFORE" "$INSTALLED_AFTER" > "$INSTALLED_AFTER.newonly"
	LC_ALL=C comm -2 -3 "$ORPHANS_AFTER.tmp" "$INSTALLED_AFTER.newonly" > $ORPHANS_AFTER

	# show new orphans after removing/upgrading
	neworphans=$(LC_ALL=C comm -1 -3 "$ORPHANS_BEFORE" "$ORPHANS_AFTER" )
	if [[ "$neworphans" ]]; then
		plain $(gettext 'Packages that were installed as dependencies but are no longer required by any installed package:')
		echo_wrap 4 "$neworphans"
	fi

	# Test local database
	testdb 

	# save original of backup files (pacnew/pacsave)
	if [[ "$MAJOR" != "remove" ]] && (( AUTOSAVEBACKUPFILE )) && ! \
		diff "$INSTALLED_BEFORE.full" "$INSTALLED_AFTER.full" > /dev/null; then
		msg $(gettext 'Searching for original config files to save')
		launch_with_su pacdiffviewer --backup
	fi

}
###################################
### Handle actions              ###
###################################

# Search for packages
# usage: search ($interactive)
# interactive:1 -> line number
# return: global var PKGSFOUND
search ()
{
	local interactive=${1:-0}
	local search_option="${PACMAN_Q_ARG[@]}"
	if [[ "$MAJOR" = "query" ]]; then
		search_option+=" -Q"
		((AUR && FOREIGN)) && search_option+=" -A"
	else
		DATE=0
		search_option+=" -S"
	fi
	if (( SEARCH )); then
		search_option+=" -s"
	else
		[[ $args ]] && (( ! GROUP )) && search_option+=" -i"
	fi
	(( AURSEARCH )) && search_option+=" -A"
	(( DATE )) && search_option+=" --sort 1"
	(( QUIET )) && { pkgquery $search_option -f "%n" "${args[@]}";return; }
	(( interactive )) && search_option+=" --number"
	{ readarray -t PKGSFOUND < <(pkgquery --get-res $search_option "${args[@]}" 3>&1 1>&2 ); } 2>&1
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

yaourt_install_packages ()
{
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
	
# Handle sync
yaourt_sync ()
{
	(( PRINT && REFRESH )) && pacman_cmd 1
	(( PRINT && ! REFRESH )) && pacman_cmd 0
	if (( GROUP || LIST || SEARCH)); then
		(( LIST )) && {
			title $(gettext 'listing all packages in repo(s)')
			msg $(gettext 'Listing all packages in repo(s)')
		}
		(( GROUP )) && title $(gettext 'show groups')
		search 0
		return
	elif (( SYSUPGRADE )); then
		loadlibrary abs
		loadlibrary aur
		prepare_orphan_list
		sysupgrade
		# Upgrade devel packages
		(( DEVEL )) && upgrade_devel_package
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
			if [[ "$_repo" = "$arg" || "$_repo" != "aur" ]]; then
				pacman_out -S "${PACMAN_S_ARG[@]}" "$arg" 2> /dev/null ||\
					 info_from_aur "${arg#*/}"
			else
				info_from_aur "${arg#*/}"
			fi
		done
		return
	fi
	yaourt_install_packages
}

# Handle query
yaourt_query ()
{
	if (( CHANGELOG || LIST || INFO || FILE )); then
		pacman_out -Q "${PACMAN_Q_ARG[@]}" "${args[@]}"
		return $?
	fi
	if (( DEPENDS && UNREQUIRED )); then
		loadlibrary alpm_query
		search_forgotten_orphans
	elif [[ $QUERYTYPE ]]; then
		yaourt_query_type
	else
		#title $(gettext "Query installed packages")
		#msg $(gettext "Query installed packages")
		AURSEARCH=0 search 0
	fi
}

###################################
### MAIN PROGRAM                ###
###################################
# Basic init and librairies
YAOURTBIN=$0
source /usr/lib/yaourt/basicfunctions.sh || exit 1 

unset MAJOR NODEPS SEARCH BUILD REFRESH SYSUPGRADE \
	AUR HOLDVER IGNOREGRP IGNOREPKG IGNOREARCH CLEAN CHANGELOG LIST INFO \
	DATE UNREQUIRED FOREIGN GROUP QUERYTYPE \
	QUIET SUDOINSTALLED AURVOTEINSTALLED CUSTOMIZEPKGINSTALLED EXPLICITE \
	DEPENDS PRINT PACMAN_S_ARG MAKEPKG_ARG YAOURT_ARG PACMAN_Q_ARG \
	PACMAN_C_ARG PKGQUERY_C_ARG failed 

# Grab environement options
{
	type -p sudo && SUDOINSTALLED=1
	type -p aurvote && AURVOTEINSTALLED=1
	type -p customizepkg && CUSTOMIZEPKGINSTALLED=1
} &> /dev/null

# makepkg check root
(( ! UID )) && program_arg $A_M "--asroot"

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
		-D|--database|-R|--remove|-U|--upgrade|-w|--downloadonly) pacman_cmd 1;;
		-o|--owns|--changelog|--check|-k|--file) pacman_cmd 0;;
		--config|--dbpath|-r|--root) program_arg $((A_PC | A_PKC)) "$1" "$2"; shift;;
		--cachedir|--logfile|--arch) program_arg $A_PC "$1" "$2"; shift;;
		--noprogressbar|--noscriptlet) program_arg $A_PC "$1";;
		--asdeps|--needed)  program_arg $A_PS $1;;
		-c|--clean)         (( CLEAN ++ )); (( CHANGELOG++ ));;
		--deps)             DEPENDS=1; program_arg $A_PQ $1;;
		-d)                 DEPENDS=1; NODEPS=1; program_arg $((A_PS | A_M | A_Y | A_PQ)) $1;;
		-e|--explicit)      EXPLICITE=1; program_arg $A_PQ $1;;
		-m|--foreign)       FOREIGN=1; program_arg $A_PQ $1;;
		-g|--groups)        GROUP=1; program_arg $A_PQ $1;;
		-i|--info)          INFO=1; program_arg $((A_PQ | A_PS)) $1;;
		-l|--list)          LIST=1; program_arg $A_PQ $1;;
		--noconfirm)        NOCONFIRM=1; program_arg $((A_PS | A_Y)) $1;;
		--nodeps)           NODEPS=1; program_arg $((A_PS | A_M | A_Y)) $1;;
		-Q|--query)         MAJOR="query";;
		-y|--refresh)       (( REFRESH ++ ));;
		-S|--sync)          MAJOR="sync";;
		--sysupgrade)       SYSUPGRADE=1; (( UPGRADES ++ ));;
		-t|--unrequired)    UNREQUIRED=1; program_arg $A_PQ $1;;
		-u|--upgrades)      (( UPGRADES ++ )); program_arg $A_PQ $1;;
		--holdver)          HOLDVER=1; program_arg $((A_M | A_Y)) $1;;
		-A|--ignorearch)    IGNOREARCH=1; program_arg $((A_M | A_Y)) $1;;
		--ignore)           program_arg $((A_PS | A_Y)) $1 "$2"; shift; IGNOREPKG+=("$1");;
		--ignoregroup)      program_arg $((A_PS | A_Y)) $1; shift; IGNOREGRP+=("$1");; 
		-a|--aur)           AUR=1; AURUPGRADE=1; AURSEARCH=1;;
		-B|--backup)        MAJOR="backup";;
		--backupfile)       shift; BACKUPFILE="$1";;
		-b|--build)         BUILD=1; program_arg $A_Y $1;;
		-C)                 MAJOR="clean";;
		--conflicts)        QUERYTYPE="conflicts";;
		--date)             DATE=1;;
		--depends)          QUERYTYPE="depends";;
		--devel)            DEVEL=1;;
		--export)           EXPORT=1; EXPORTSRC=1; program_arg $A_Y $1 "$2"; shift; EXPORTDIR="$1";;
		-f|--force)         FORCE=1; program_arg $((A_PS | A_M | A_Y)) $1;;
		-G|--getpkgbuild)   MAJOR="getpkgbuild"; shift; PKG="$1";;
		-h|--help)          usage; exit 0;;
		--lightbg)          COLORMODE="lightbg";;
		--nocolor)          COLORMODE="nocolor";;
		--provides)         QUERYTYPE="provides";;
		-p|--print)         PRINT=1; FILE=1; program_arg $A_PQ $1;;
		--file)             FILE=1; program_arg $A_PQ $1;;
		--print-format)     ;; # --print-format needs --print
		--pkg)              program_arg $((A_M)) $1 "$2"; shift;;
		--replaces)         QUERYTYPE="replaces";;
		-s|--search)        SEARCH=1; program_arg $A_PQ $1;;
		--stats)            MAJOR="stats";;
		--sucre)            MAJOR="sync"
			FORCE=1; SYSUPGRADE=1; REFRESH=1; 
			AURUPGRADE=1; DEVEL=1; NOCONFIRM=2
			program_arg $((A_PS | A_Y)) "--noconfirm" "--force";;
		--textonly)         COLORMODE="textonly";;
		--tmp)              program_arg $A_Y $1 "$2"; shift; TMPDIR="$1";;
		-V|version)         version; exit 0;;
		-q|--quiet)         QUIET=1; DETAILUPGRADE=0; program_arg $((A_PS | A_Y)) $1;;
		-*)                 pacman_cmd 0;;
		*)                  args+=("$1") ;; 
	esac
	shift
done

# Init colors (or not)
[[ -t 1 ]] || { COLORMODE="textonly" TERMINALTITLE=0; }
[[ $COLORMODE = "textonly" ]] && program_arg $A_M "-m" # no color for makepkg
[[ $COLORMODE ]] && program_arg $A_Y  "--$COLORMODE"
initcolor

# No options
if ! [[ "$MAJOR" ]]; then
	[[ $args ]] || pacman_cmd 0
	# If no action and files as argument, act like -U *
	for file in "${args[@]}"; do
		[[ "${file%.pkg.tar.*}" != "$file" && -r "$file" ]] && filelist+=("$file")
	done
	if [[ $filelist ]]; then
		args=( "${filelist[@]}" )
		su_pacman -U "${args[@]}"
		die $?
	else
		# Interactive search else.
		MAJOR="interactivesearch"
	fi
fi

# Init path, complete options and check some permissions
(( ! SYSUPGRADE && UPGRADES )) && [[ "$MAJOR" = "sync" ]] && SYSUPGRADE=1
(( EXPORT )) && [[ $EXPORTDIR ]] && { check_dir EXPORTDIR || die 1; }
check_dir TMPDIR || die 1
YAOURTTMPDIR="$TMPDIR/yaourt-tmp-$(id -un)"
# -Q --backupfile
[[ "$BACKUPFILE" ]] && if [[ -r "$BACKUPFILE" ]]; then
	loadlibrary alpm_backup 
	is_an_alpm_backup "$BACKUPFILE" || die 1
	program_arg $((A_PC | A_PKC)) "-b" "$backupdir"
else
	error $(eval_gettext 'Unable to read $BACKUPFILE file')
	die 1
fi
(( NOCONFIRM )) && { EDITFILES=0; BUILD_NOCONFIRM=1; }
initpath

# Refresh
if [[ "$MAJOR" = "sync" ]] && (( REFRESH && ! PRINT )); then
	title $(gettext 'synchronizing package databases')
	(( REFRESH > 1 )) && _arg="-Syy" || _arg="-Sy"
	su_pacman $_arg
fi


# Action
case "$MAJOR" in
	clean)
		(( CLEAN )) && _arg="-c" || _arg=""
		launch_with_su pacdiffviewer $_arg
		;;

	stats)
		loadlibrary alpm_stats
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
		yaourt_backup "${args[0]}"
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
				for ((i=${line%-*}-1; i<${line#*-}; i++)); do
					packages+=(${PKGSFOUND[$i]});
				done
			else
				packages+=(${PKGSFOUND[$((line - 1))]})
			fi
		done
		echo 
		args=("${packages[@]}")
		yaourt_install_packages
		;;
		
	*) pacman_cmd 0 ;;
esac
die $failed

# vim: set ts=4 sw=4 noet: 
