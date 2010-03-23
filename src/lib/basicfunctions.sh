#!/bin/bash
#===============================================================================
#
#          FILE: basicfunctions.sh
# 
#   DESCRIPTION: yaourt's basic functions
# 
#       OPTIONS:  ---
#  REQUIREMENTS:  ---
#          BUGS:  ---
#         NOTES:  ---
#        AUTHOR:   Julien MISCHKOWITZ (wain@archlinux.fr) 
#       VERSION:  1.0
#===============================================================================


# set misc path
initpath(){
	PACMANROOT=`LC_ALL=C pacman --verbose | grep 'DB Path' | awk '{print $4}'| sed "s/\/$//"`
	LOCKFILE="$PACMANROOT/db.lck"
	mkdir -p "$YAOURTTMPDIR"
}

# Load library but never reload twice the same lib
loadlibrary(){
	eval alreadyload=\$$1
	[ ! -z "$alreadyload" ] && return 0
	if [ ! -f "/usr/lib/yaourt/$1.sh" ]; then
		error "$1.sh file is missing"
		die 1
	fi
	source "/usr/lib/yaourt/$1.sh" || warning "problem in $1.sh library"
	eval $1=1
}

# ask 
userinput() 
{ 
	[ -z $1 ] && _key="YN" || _key=$1
	read -en $NOENTER
	echo $REPLY | tr '[[:lower:]]' '[[:upper:]]'  | tr "$(eval_gettext $_key)" "$_key"
}

_translate_me()
{
	# Used to detect string with poedit
	eval_gettext "YN"  # Yes, No
	eval_gettext "YAN" # Yes, All, No
	eval_gettext "YNA" # Yes, No, Abort
	eval_gettext "YNVC" # Yes, No, View package, Check package with namcap
	eval_gettext "YNVM" # Yes, No, View more infos, Manualy select packages
}

yes_no ()
{
	case $1 in
	  1) 
		  echo $(eval_gettext "[Y/n]")
			;;
	  2)
		  echo $(eval_gettext "[y/N]")
			;;
	  *)
		  echo $(eval_gettext "[y/n]")
			;;
	esac
}
		  
isnumeric(){
	if let $1 2>/dev/null; then return 0; else return 1; fi
}

is_x_gt_y(){
	[ $(vercmp "$1" "$2" 2> /dev/null) -gt 0 ]
}


##
# From makepkg.
#  usage : in_array( $needle, $haystack )
# return : 0 - found
#          1 - not found
##
in_array() {
	local needle=$1; shift
	[ -z "$1" ] && return 1 # Not Found
	local item
	for item in "$@"; do
		[ "$item" = "$needle" ] && return 0 # Found
	done
	return 1 # Not Found
}

run_editor ()
{
	local edit_cmd=
	local file="$1"
	if [ -z "$EDITOR" ]; then
		echo -e ${COL_RED}$(eval_gettext 'Please add \$EDITOR to your environment variables')
		echo -e ${NO_COLOR}$(eval_gettext 'for example:')
		echo -e ${COL_BLUE}"export EDITOR=\"vim\""${NO_COLOR}" $(eval_gettext '(in ~/.bashrc)')"
		echo $(eval_gettext '(replace vim with your favorite editor)')
		echo
		echo -ne ${COL_ARROW}"==> "${NO_COLOR}$(eval_gettext 'Edit $file with: ')
		read -e EDITOR
		echo
	fi
	[ "$(basename "$EDITOR")" = "gvim" ] && edit_cmd="$EDITOR --nofork" || edit_cmd="$EDITOR"
	( $edit_cmd "$file" )
	wait
}

# Edit file
# Usage:	edit_file ($file, $default_answer, $loop, $check_dep)
# 	$file: file to edit
# 	$default_answer: 1 (default): Y 	2: N
# 	$loop: 1: loop until answer 'no' 	0 (default) : no loop
# 	$check_dep: 1 (default): if file = PKGBUILD, check deps 
edit_file ()
{
	(( ! EDITFILES )) && return 0
	local file="$1"
	local default_answer=${2:-1}
	local loop=${3:-0}
	local check_dep=${4:-1}
	local iter=1

	while (( iter )); do
		prompt "$(eval_gettext 'Edit $file ?') $(yes_no $default_answer) $(eval_gettext '("A" to abort)')"
		local answer=$(userinput "YNA")
		echo
		if [ -z "$answer" ]; then
			(( default_answer )) && answer='Y' || answer='N'
		fi
		if [ "$answer" = "Y" ]; then
			run_editor "$file"
			(( ! loop )) && iter=0
		else
			iter=0
		fi
		if [ "$answer" != "A" -a "$file" = "PKGBUILD" ]; then
			read_pkgbuild || return 1
			(( check_dep )) && { check_deps; check_conflicts; }
		fi
	done
	
	if [ "$answer" = "A" ]; then
		echo
		echo $(eval_gettext 'Aborted...')
		return 1
	fi
	return 0
}

check_root ()
{
	if (( ! UID )); then
		runasroot=1
        warning $(eval_gettext 'Building package as root is dangerous.\n Please run yaourt as a non-privileged user.')
		sleep 2
	else
		runasroot=0
	fi
}	

# From makepkg.
# Modified: long options can take optional arguments (::)
# getopt like parser
# Usage: parse_options ($short_options, $long_options, ...)
parse_options() {
	local short_options=$1; shift;
	local long_options=$1; shift;
	local ret=0;
	local unused_options=""

	while [ -n "$1" ]; do
		if [ ${1:0:2} = '--' ]; then
			if [ -n "${1:2}" ]; then
				local match=""
				for i in ${long_options//,/ }; do
					if [ ${1:2} = ${i//:} ]; then
						match=$i
						break
					fi
				done
				if [ -n "$match" ]; then
					if [ ${match%:} = $match ] || [ ${match%::} != $match -a -z "$2" ]; then
						printf ' %s' "$1"
					else
						if [ -n "$2" ]; then
							printf ' %s' "$1"
							shift
							printf " '%s'" "$1"
						else
							echo "$NAME: option '$1' $(gettext "requires an argument")" >&2
							ret=1
						fi
					fi
				else
					echo "$NAME: $(gettext "unrecognized option") '$1'" >&2
					ret=1
				fi
			else
				shift
				break
			fi
		elif [ ${1:0:1} = '-' ]; then
			for ((i=1; i<${#1}; i++)); do
				if [[ "$short_options" =~ "${1:i:1}" ]]; then
					if [[ "$short_options" =~ "${1:i:1}:" ]]; then
						if [ -n "${1:$i+1}" ]; then
							printf ' -%s' "${1:i:1}"
							printf " '%s'" "${1:$i+1}"
						else
							if [ -n "$2" ]; then
								printf ' -%s' "${1:i:1}"
								shift
								printf " '%s'" "${1}"
							else
								echo "$NAME: option $(gettext "requires an argument") -- '${1:i:1}'" >&2
								ret=1
							fi
						fi
						break
					else
						printf ' -%s' "${1:i:1}"
					fi
				else
					echo "$NAME: $(gettext "invalid option") -- '${1:i:1}'" >&2
					ret=1
				fi
			done
		else
			unused_options="${unused_options} '$1'"
		fi
		shift
	done

	printf " --"
	if [ -n "$unused_options" ]; then
		for i in ${unused_options[@]}; do
			printf ' %s' "$i"
		done
	fi
	if [ -n "$1" ]; then
		while [ -n "$1" ]; do
			printf " '%s'" "${1}"
			shift
		done
	fi
	printf "\n"

	return $ret
}

###################################
### MAIN OF INIT PROGRAM        ###
###################################
loadlibrary color
# defautconfig
EDITFILES=1
DEVEL=0
EXPORTDIR=""
EXPORT=0
TERMINALTITLE=1
NOCONFIRM=0
FORCE=0
AURCOMMENT=1
AURUPGRADE=0
AURVOTE=1
AURSEARCH=1
AUTOSAVEBACKUPFILE=0
MAXCOMMENTS=5
NOENTER=1
ORDERBY="asc"
PACMANBIN="/usr/bin/pacman"
INENGLISH=""
TMPDIR="/tmp"
COLORMODE=""

[ -r /etc/yaourtrc ] && source /etc/yaourtrc
[ -r ~/.yaourtrc ] && source ~/.yaourtrc
[ -n "$EXPORTDIR" ] && EXPORT=1
(( FORCEENGLISH )) && INENGLISH="LC_ALL=C"
(( NOCONFIRM )) && EDITFILES=0
in_array "$COLORMODE" "${COLORMODES[@]}" || COLORMODE=""
PACMANBIN="$INENGLISH $PACMANBIN"

MAJOR=""
PRINTURIS=0
INFO=0
ROOT=0
NEWROOT=""
NODEPS=0
ASDEPS=0
SEARCH=0
BUILD=0
REFRESH=0
SYSUPGRADE=0
DOWNLOAD=0


AUR=0
HOLDVER=0
IGNORE=0
IGNOREPKG=""
IGNOREARCH=0
NEEDED=""
CLEAN=0
LIST=0
CLEANDATABASE=0
DATE=0
UNREQUIRED=0
CHANGELOG=0
FOREIGN=0
OWNER=0
GROUP=0
DOWNGRADE=""
QUERYTYPE=""
QUERYWHICH=0
QUIET=0
develpkg=0
failed=0
SUDOINSTALLED=0
VERSIONPKGINSTALLED=0
AURVOTEINSTALLED=0
CUSTOMIZEPKGINSTALLED=0
EXPLICITE=0
DEPENDS=0

# Parse Command Line Options.
OPT_SHORT_PACMAN="QRSUcdefgilmopqr:stuwy"
OPT_SHORT_YAOURT="BCGVbh"
OPT_SHORT="${OPT_SHORT_PACMAN}${OPT_SHORT_YAOURT}"
OPT_PACMAN="asdeps,changelog,clean,deps,downloadonly,explicit,foreign,groups"
OPT_PACMAN="$OPT_PACMAN,info,list,needed,noconfirm,nodeps,owner,print-uris,query,refresh"
OPT_PACMAN="$OPT_PACMAN,remove,root:,search,sync,sysupgrade,unrequired,upgrade,upgrades"
OPT_MAKEPKG="holdver,ignorearch"
OPT_YAOURT="aur,backup::,backupfile:,build,conflicts,database,date,depends,devel"
OPT_YAOURT="$OPT_YAOURT,export:,force,getpkgbuild,help,lightbg,nocolor,provides,replaces"
OPT_YAOURT="$OPT_YAOURT,stats,sucre,textonly,tmp:,version"
OPT_LONG="$OPT_PACMAN,$OPT_MAKEPKG,$OPT_YAOURT"
OPT_TEMP="$(parse_options $OPT_SHORT $OPT_LONG "$@" || echo 'PARSE_OPTIONS FAILED')"
if echo "$OPT_TEMP" | grep -q 'PARSE_OPTIONS FAILED'; then
	# This is a small hack to stop the script bailing with 'set -e'
	echo; usage 1; exit 1 # E_INVALID_OPTION;
fi
eval set -- "$OPT_TEMP"
unset OPT_SHORT OPT_LONG OPT_TEMP OPT_YAOURT OPT_MAKEPKG OPT_SHORT_YAOURT
ARGSANS=""
while true; do
	in_array "$1" ${OPT_PACMAN//,/ } && ARGSANS="$ARGSANS $1"
	[ ${OPT_SHORT_PACMAN/${1:1:1}/} != ${OPT_SHORT_PACMAN} ] && ARGSANS="$ARGSANS $1"
	case "$1" in
		--asdeps) 			ASDEPS=1;;
		--changelog)		CHANGELOG=1;;
		--clean)			CLEAN=1;;
		--deps)				DEPENDS=1;;
		-w|--downloadonly)	DOWNLOAD=1;;
		-e|--explicit)		EXPLICITE=1;;
		-m|--foreign)		FOREIGN=1;;
		-g|--groups)		GROUP=1;;
		-i|--info)			INFO=1;;
		-l|--list)			LIST=1;;
		--needed)			NEEDED=1;;
		--noconfirm)		NOCONFIRM=1;;
		-d|--nodeps)		NODEPS=1;;
		-p|print-uris)		PRINTURIS=1;;
		-Q|--query)			MAJOR="query";;
		-y|--refresh)		(( REFRESH ++ ));;
		-R|--remove)		MAJOR="remove";;
		-r|--root:)			ROOT=1; shift; NEWROOT="$1"; ARGSANS="$ARGSANS '$1'";;
		-S|--sync)			MAJOR="sync";;
		--sysupgrade)		SYSUPGRADE=1;;
		-t|	--unrequired)	UNREQUIRED=1;;
		-U|--upgrade)		MAJOR="upgrade";;
		-u|--upgrades)		(( UPGRADES ++ ));;
		--holdver)			HOLDVER=1;;
		--ignorearch)		IGNOREARCH=1;;
		--aur)				AUR=1; AURUPGRADE=1; AURSEARCH=1;;
		-B|--backup)		MAJOR="backup"; 
							savedir=$(pwd)
							if [ ${2:0:1} != "-" ]; then
								[ -d "$2" ] && savedir="$( readlink -f "$2")"
								[ -f "$2" ] && backupfile="$( readlink -f "$2")"
								shift
							fi
							;;
		--backupfile)		COLORMODE="textonly"; shift; BACKUPFILE="$1" ;;
		-b|--build)			BUILD=1;;
		--conflicts)		QUERYTYPE="conflicts";;
		--database)			CLEANDATABASE=1;;
		--date)				DATE=1;;
		--depends)			QUERYTYPE="depends";;
		--devel)			DEVEL=1;;
		--export)			EXPORT=1; shift; EXPORTDIR="$1";;
		-f|--force)			FORCE=1;;
		-G|--getpkgbuild)	MAJOR="getpkgbuild";;
		-h|--help)			usage; exit 0;;
		--lightbg)			COLORMODE="lightbg";;
		--nocolor)			COLORMODE="nocolor";;
		-o|--owner)			OWNER=1;;
		--provides)			QUERYTYPE="provides";;
		--replaces)			QUERYTYPE="replaces";;
		-s|--search)		SEARCH=1;;
		--stats)			MAJOR="stats";;
		--sucre)			MAJOR="sync"
							FORCE=1; SYSUPGRADE=1; REFRESH=1; 
							AURUPGRADE=1; DEVEL=1; NOCONFIRM=2; EDITFILES=0
							ARGSANS="-Su --noconfirm --force";;
		--textonly)			COLORMODE="textonly";;
		--tmp)				shift; TMPDIR="$1";;
		-V|version)			version; exit 0;;
		-q)					QUERYWHICH=1; QUIET=1;;

		--)					OPT_IND=0; shift; break;;
		*)					usage; exit 1 ;; 
	esac
	shift
done
unset OPT_PACMAN OPT_SHORT_PACMAN
args=( "$@" )
if [ -z "$MAJOR" ]; then
	[ -z "$args" ] && { usage; die 1; }
	declare -a filelist
	for file in "$args{[@]}"; do
		[ "${file%.pkg.tar.*}" != "$file" -a -r "$file" ] && \
			filelist[${#filelist[@]}]="$file"
	done
	if (( ${#filelist[@]} )); then
		args=( "${filelist[@]}" )
		MAJOR="upgrade"
	else
		MAJOR="interactivesearch"
	fi
fi


if [ "$MAJOR" != "query" -a -n "$BACKUPFILE" ]; then
	error $(eval_gettext '--backupfile can be used only with --query')
	die 1
fi

[ -z "$BACKUPFILE" ] || [ -r "$BACKUPFILE" ] || { error $(eval_gettext 'Unable to read $_file file'); die 1; }

(( ! SYSUPGRADE )) && (( UPGRADES )) && [ "$MAJOR" = "sync" ] && SYSUPGRADE=1
if (( EXPORT )); then
	[ -d "$EXPORTDIR" ] || { error $EXPORTDIR $(eval_gettext 'is not a directory'); die 1;}
	[ -w "$EXPORTDIR" ] || { error $EXPORTDIR $(eval_gettext 'is not writable'); die 1;}
fi


[ -d "$TMPDIR" ] || { error $TMPDIR $(eval_gettext 'is not a directory'); die 1;}
[ -w "$TMPDIR" ] || { error $TMPDIR $(eval_gettext 'is not writable'); die 1;}
YAOURTTMPDIR="$TMPDIR/yaourt-tmp-$(id -un)"

initpath
initcolor

