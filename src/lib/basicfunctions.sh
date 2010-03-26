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

# Run editor
# Usage: run_editor ($file, $default_answer)
# 	$file: file to edit 
# 	$default_answer: 0: don't ask	1 (default): Y	2: N
run_editor ()
{
	local edit_cmd=
	local file="$1"
	local default_answer=${2:-1}
	local answer='Y'
	if (( default_answer )); then
		prompt "$(eval_gettext 'Edit $file ?') $(yes_no $default_answer) $(eval_gettext '("A" to abort)')"
		local answer=$(userinput "YNA")
		echo
		[ "$answer" = "A" ] && echo -e "\n$(eval_gettext 'Aborted...')" && return 2
		if [ -z "$answer" ]; then
			(( default_answer )) && answer='Y' || answer='N'
		fi
		[ "$answer" = "N" ] && return 1
	fi
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
TMPDIR="/tmp"
COLORMODE=""
SHOWORPHANS=0
DIFFEDITCMD="vimdiff"

[ -r /etc/yaourtrc ] && source /etc/yaourtrc
[ -r ~/.yaourtrc ] && source ~/.yaourtrc
[ -n "$EXPORTDIR" ] && EXPORT=1
(( FORCEENGLISH )) && export LC_ALL=C
in_array "$COLORMODE" "${COLORMODES[@]}" || COLORMODE=""
[ -d "$TMPDIR" ] || { error $TMPDIR $(eval_gettext 'is not a directory'); die 1;}
[ -w "$TMPDIR" ] || { error $TMPDIR $(eval_gettext 'is not writable'); die 1;}
TMPDIR=$(readlink -e "$TMPDIR")
YAOURTTMPDIR="$TMPDIR/yaourt-tmp-$(id -un)"

