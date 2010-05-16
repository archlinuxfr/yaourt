#!/bin/bash
#
# color.sh : color vars & colored output & title modification
# This file is part of Yaourt (http://archlinux.fr/yaourt-en)

COLORMODES=( textonly nocolor lightbg )
title(){
	(( ! TERMINALTITLE )) || [[ ! $DISPLAY ]] && return 0
	case $TERM in
		rxvt*|xterm*|aterm)
		echo -n -e "\033]0;yaourt: $@\007"
		;;
	esac
}
initcolor(){
	# no special caracter for textonly mode
	[[ "$COLORMODE" = "textonly" ]] && return 0
	# no color on exit (even on user interrupt)
	trap "echo -e '\e[0m'" 0
	# font type
	COL_BOLD="\033[1m"
	COL_INVERT="\033[7m"
	COL_BLINK="\033[5m"
	NO_COLOR="\033[0m"

	# No italic out of Xorg or under screen
	[[ $DISPLAY && "${TERM:0:6}" != "screen" ]] && COL_ITALIQUE="\033[3m"

	# Color list
	case $COLORMODE in
		"lightbg")
			COL_WHITE="\033[1;37m"
			COL_RED="\033[1;31m"
			COL_CYAN="\033[1;36m"
			COL_GREEN="\033[1;32m"
			COL_PINK="\033[1;35m"
			COL_BLUE="\033[1;34m"
			COL_BLACK="\033[1;30m"
			COL_MAGENTA="\033[1;35m"
			COL_YELLOW="$COL_CYAN"
			;;
		*)
			COL_WHITE="\033[1;37m"
			COL_YELLOW="\033[1;33m"
			COL_RED="\033[1;31m"
			COL_CYAN="\033[1;36m"
			COL_GREEN="\033[1;32m"
			COL_PINK="\033[1;35m"
			COL_BLUE="\033[1;34m"
			COL_BLACK="\033[1;30m"
			COL_MAGENTA="\033[1;35m"
		;;
	esac

	# Color functions
	COL_REPOS[core]=$COL_RED
	COL_REPOS[extra]=$COL_GREEN
	COL_REPOS[local]=$COL_YELLOW
	COL_REPOS[community]=$COL_PINK
	COL_REPOS[testing]=$COL_RED
	COL_REPOS[aur]=$COL_MAGENTA
	COL_O_REPOS="$COL_MAGENTA"
	COL_INSTALLED="$COL_INVERT$COL_YELLOW" 
	COL_ARROW="$COL_YELLOW"
	COL_NUMBER="$COL_INVERT$COL_YELLOW"
	COL_GROUP="$COL_BLUE"
}
plain(){
	echo -e "${COL_BOLD}$*${NO_COLOR}" >&2
}
_showmsg(){
	echo -en "$1==> $2$NO_COLOR$COL_BOLD$3$NO_COLOR" >&2
}
msg(){
	_showmsg "$COL_GREEN" "" "$*\n"
}
warning(){
	_showmsg "$COL_YELLOW" "$(gettext 'WARNING: ')" "$*\n"
}
P_UNDERLINE=${P_INDENT// /-}
prompt(){
	local t="$*"
	t=${#t}
	_showmsg "$COL_ARROW" "" "$*\n"
	_showmsg "$COL_ARROW" "" "${P_UNDERLINE:4:$t}\n"
	_showmsg "$COL_ARROW"
}
prompt2(){
	_showmsg "$COL_ARROW" "" "$*"
}
error(){
	_showmsg "$COL_RED" "$(gettext 'ERROR: ')" "$*\n"
	return 1
}

# vim: set ts=4 sw=4 noet: 
