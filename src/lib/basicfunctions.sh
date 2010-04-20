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

COLUMNS=$(tput cols)

# set misc path
initpath(){
	PACMANROOT=`LC_ALL=C pacman --verbose | grep 'DB Path' | awk '{print $4}'| sed "s/\/$//"`
	LOCKFILE="$PACMANROOT/db.lck"
	mkdir -p "$YAOURTTMPDIR"
}

# Load library but never reload twice the same lib
loadlibrary(){
	eval alreadyload=\$$1
	[[ "$alreadyload" ]] && return 0
	if [[ ! -f "/usr/lib/yaourt/$1.sh" ]]; then
		error "$1.sh file is missing"
		die 1
	fi
	source "/usr/lib/yaourt/$1.sh" || warning "problem in $1.sh library"
	eval $1=1
}

# Fill line
echo_fill ()
{
	printf -v_fill "%${COLUMNS}s" ""
	echo -e "$1${_fill// /$2}$3"
}

# Wrap output
# usage: str_wrap ($indent, $str)
# return: set $strwrap with wrapped content
str_wrap ()
{
	unset strwrap
	local indent=${1:-0} ; shift
	local str=($*) i=0 j=0 strout=""
	for s in "${str[@]}"; do
		strout+="$s "
		(( i+=${#s}+1 ))
		(( j++ ))
		if (( ${#str[$j]} )) && (( (i%COLUMNS)+indent+${#str[$j]}>COLUMNS-1 )); then
			printf -vout "%*s%s\n" $indent "" "$strout"
			strwrap+="$out"
			strout=""
			i=0
		fi
	done
	[[ $strout ]] && printf -vout "%*s%s" $indent "" "$strout" && strwrap+="$out"
}

echo_wrap ()
{
	str_wrap "$1" "$2"
	echo -e "$strwrap"
}

echo_wrap_next_line () 
{
	echo -en "$1"; shift
	local len=$1; shift
	local strout=""
	local i=0
	for str in "$@"; do
		str_wrap $len "$str"
		(( i++ )) || strwrap=${strwrap##*( )}
		strout+="$strwrap\n"
	done
	echo -en "$strout"
}

list_select ()
{
	local i=0
	for _line in "$@"; do
		(( i++ ))
		echo -e  "$COL_NUMBER$i$NO_COLOR $_line"
	done
	echo
}

# ask 
userinput() 
{
	local _key=${1:-YN}
	local default=${2:-Y}
	local answer
	if (( NOCONFIRM ));then 
		answer=$default
	else
		read -en $NOENTER
		[[ $REPLY ]] && answer=$(echo ${REPLY^^*} | tr "$(gettext $_key)" "$_key") || answer=$default
		[[ "${_key/$answer/}" = "$_key" ]] && answer=$default
	fi
	echo $answer
	[[ "$answer" = "$default" ]]
}

useragrees()
{
	userinput "$@" &> /dev/null
	local ret=$?
	echo 
	return $ret
}

yes_no ()
{
	case $1 in
	  1) echo $(gettext "[Y/n]");;
	  2) echo $(gettext "[y/N]");;
	  *) echo $(gettext "[y/n]");;
	esac
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
	[[ "$1" ]] || return 1 # Not Found
	local item
	for item in "$@"; do
		[[ "$item" = "$needle" ]] && return 0 # Found
	done
	return 1 # Not Found
}

# Run editor
# Usage: run_editor ($file, $default_answer)
# 	$file: file to edit 
# 	$default_answer: 0: don't ask	1 (default): Y	2: N
run_editor ()
{
	local edit_cmd
	local file="$1"
	local default_answer=${2:-1}
	local answer_str=" YN"
	local answer='Y'
	if (( default_answer )); then
		prompt "$(eval_gettext 'Edit $file ?') $(yes_no $default_answer) $(gettext '("A" to abort)')"
		local answer=$(userinput "YNA" ${answer_str:$default_answer:1})
		echo
		[[ "$answer" = "A" ]] && echo -e "\n$(gettext 'Aborted...')" && return 2
		[[ "$answer" = "N" ]] && return 1
	fi
	if [[ ! "$EDITOR" ]]; then
		echo -e ${COL_RED}$(gettext 'Please add \$EDITOR to your environment variables')
		echo -e ${NO_COLOR}$(gettext 'for example:')
		echo -e ${COL_BLUE}"export EDITOR=\"vim\""${NO_COLOR}" $(gettext '(in ~/.bashrc)')"
		echo $(gettext '(replace vim with your favorite editor)')
		echo
		echo -ne ${COL_ARROW}"==> "${NO_COLOR}$(eval_gettext 'Edit $file with: ')
		read -e EDITOR
		echo
	fi
	[[ "$(basename "$EDITOR")" = "gvim" ]] && edit_cmd="$EDITOR --nofork" || edit_cmd="$EDITOR"
	( $edit_cmd "$file" )
	wait
}

check_root ()
{
	if (( ! UID )); then
		runasroot=1
        warning $(gettext 'Building package as root is dangerous.\n Please run yaourt as a non-privileged user.')
		sleep 2
	else
		runasroot=0
	fi
}	

###################################
### MAIN OF INIT PROGRAM        ###
###################################
declare -A COL_REPOS	#TODO not its place
shopt -s extglob
loadlibrary color
# defautconfig
EDITFILES=1
DEVEL=0
DEVELBUILDDIR="/var/abs/local/yaourtbuild"
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
SHOWORPHANS=1
DIFFEDITCMD="vimdiff"

[[ -r /etc/yaourtrc ]] && source /etc/yaourtrc
[[ -r ~/.yaourtrc ]] && source ~/.yaourtrc
[[ -n "$EXPORTDIR" ]] && EXPORT=1
(( FORCEENGLISH )) && export LC_ALL=C
in_array "$COLORMODE" "${COLORMODES[@]}" || COLORMODE=""
[[ -d "$TMPDIR" ]] || { error $TMPDIR $(gettext 'is not a directory'); die 1;}
[[ -w "$TMPDIR" ]] || { error $TMPDIR $(gettext 'is not writable'); die 1;}
TMPDIR=$(readlink -e "$TMPDIR")
YAOURTTMPDIR="$TMPDIR/yaourt-tmp-$(id -un)"

