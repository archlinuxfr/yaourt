#!/bin/bash
#
# io.sh : Input/output functions
# This file is part of Yaourt (http://archlinux.fr/yaourt-en)

# This file should be included from outside a function.

COLUMNS=$(tput cols)
printf -v P_INDENT "%*s" ${COLUMNS:-0}
P_UNDERLINE=${P_INDENT// /-}
C0=''
declare -A C=()

# Fill line ($color_start,$content,$color_end)
echo_fill() {
	echo -e "$1${P_INDENT// /$2}$3"
}

# Wrap string
# usage: str_wrap ($indent, $str)
# return: set $strwrap with wrapped content
str_wrap() {
	local indent=${1:-0} ; shift
	(( indent > COLUMNS )) && { strwrap="$*"; return 0; }
	strwrap="${P_INDENT:0:$indent}$*"
	(( ${#strwrap} < COLUMNS-indent-1 )) && return 0 || { strwrap=""; set -- $*; }
	local i=0 k strout=""
	while [[ $1 ]]; do
		strout+="$1 "
		(( i+=${#1}+1 ))
		k=${#2}
		if (( k && (i%COLUMNS)+indent+k>COLUMNS-1 )); then
			strwrap+="${P_INDENT:0:$indent}$strout\n"
			strout=""
			i=0
		fi
		shift
	done
	strwrap+="${P_INDENT:0:$indent}$strout"
}

echo_wrap() {
	local strwrap
	str_wrap "$1" "$2"
	echo -e "$strwrap"
}

echo_wrap_next_line() {
	echo -en "$1"; shift
	local len=$1; shift
	local i=0 strout="" strwrap
	for str in "$@"; do
		str_wrap $len "$str"
		(( i++ )) || strwrap=${strwrap##*( )}
		strout+="$strwrap\n"
	done
	echo -en "$strout"
}


list_select() {
	local i=0 _line
	for _line in "$@"; do
		echo -e  "${C[nb]}$((++i))$C0 $_line"
	done
	echo
}

# ask
userinput() {
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

useragrees() {
	userinput "$@" >/dev/null
	local ret=$?
	echo
	return $ret
}

# ask while building
builduserinput()  { NOCONFIRM=$BUILD_NOCONFIRM userinput  "$@"; }
builduseragrees() { NOCONFIRM=$BUILD_NOCONFIRM useragrees "$@"; }

yes_no() {
	case $1 in
	  1) echo $(gettext "[Y/n]");;
	  2) echo $(gettext "[y/N]");;
	  *) echo $(gettext "[y/n]");;
	esac
}

# Set teminal title.
title() {
	(( ! TERMINALTITLE )) || [[ ! $DISPLAY ]] && return 0
	case $TERM in
		rxvt*|xterm*|aterm)
		echo -n -e "\033]0;yaourt: $@\007"
		;;
	esac
}


# parse_color_var ($1)
# $1 is a colon-separated list of keys
# ex: core=1;31:extra=1;32
parse_color_var() {
	local vars="BOLD BLINK RED GREEN YELLOW BLUE PURPLE CYAN"
	local col key val colors=(${1//:/ })
	for col in "${colors[@]}"; do
		[[ $col =~ ^[A-Za-z]+=[0-9\;]+$ ]] || continue
		key=${col%=*} val="\033[${col#$key=}m"
		[[ " ${vars[*]} " =~ " $key " ]] && eval C$key=\"$val\" || C[$key]="$val"
	done
}

init_color() {
	if ((!USECOLOR)); then
		program_arg $((A_M | A_PKC)) --nocolor
		program_arg $((A_PO)) --color never
		return
	fi
	if ((USECOLOR==2)); then
		program_arg $((A_PKC)) --color
		program_arg $((A_PO)) --color always
	else
		program_arg $((A_PO)) --color auto
	fi
	C0="\033[0m"
	# yaourt colors
	local yaourt_colors="BOLD=1:BLINK=5:RED=1;31:GREEN=1;32:YELLOW=1;33:BLUE=1;34:PURPLE=1;35:CYAN=1;36"
	# package-query colors (packages listing)
	local pq_colors="no=0:other=1;35:testing=1;31:core=1;31:extra=1;32:local=1;33:nb=7;33:pkg=1:installed=1;33;7:votes=1;33;7:od=1;33;7"
	# env COLORS
	export PQ_COLORS+="$pq_colors:$yaourt_colors:$YAOURT_COLORS"
	parse_color_var "$PQ_COLORS"
	cleanup_add echo -ne '\033[0m'
	((TERMINALTITLE)) && [[ $DISPLAY ]] && cleanup_add echo -ne "\033]0;$TERM\007"
}


_show_msg() { echo -en "$1==> $2$C0$CBOLD$3$C0" >&2; }
msg()       { _show_msg "$CGREEN" "" "$*\n"; }
warning()   { _show_msg "$CYELLOW" "$(gettext 'WARNING: ')" "$*\n"; }
prompt()    {
	local t="$*"
	t=${#t}
	_show_msg "$CYELLOW" "" "$*\n"
	_show_msg "$CYELLOW" "" "${P_UNDERLINE:4:$t}\n"
	_show_msg "$CYELLOW"
}
prompt2()   { _show_msg "$CYELLOW" "" "$* "; }
error()     { _show_msg "$CRED" "$(gettext 'ERROR: ')" "$*\n"; return 1; }

# vim: set ts=4 sw=4 noet:
