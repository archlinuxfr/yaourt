#!/bin/bash
#===============================================================================
#
#          FILE: color.sh
# 
#   DESCRIPTION: yaourt's library to manage colors
# 
#       OPTIONS:  ---
#  REQUIREMENTS:  ---
#          BUGS:  ---
#         NOTES:  ---
#        AUTHOR:   Julien MISCHKOWITZ (wain@archlinux.fr) 
#       VERSION:  1.0
#===============================================================================
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
	if [[ "$COLORMODE" = "textonly" ]]; then
		TERMINALTITLE=0
		return 0
	else
		# font type
		COL_BOLD="\033[1m"
		COL_INVERT="\033[7m"
		COL_BLINK="\033[5m"
		NO_COLOR="\033[0m"

		# No italic out of Xorg or under screen
		if [[ "$DISPLAY"  && "${TERM:0:6}" != "screen" ]]; then
			COL_ITALIQUE="\033[3m"
			local _colitalique="\033[3m"
		fi
	fi


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
	COL_INSTALLED="$COL_INVERT$COL_YELLOW" # show [installed] packages
	COL_ARROW="$COL_YELLOW" # show ==>
	COL_NUMBER="$COL_INVERT$COL_YELLOW" # show number) in listing
	COL_GROUP="$COL_BLUE"
}
list(){
	echo -e "${COL_ARROW}$1${NO_COLOR}" >&2
}
plain(){
	echo -e "${COL_BOLD}$*${NO_COLOR}" >&2
}
msg(){
	echo -e "${COL_GREEN}==> ${NO_COLOR}${COL_BOLD}$*${NO_COLOR}" >&2
}
warning(){
	echo -e "${COL_YELLOW}==> WARNING: ${NO_COLOR}${COL_BOLD}$*${NO_COLOR}" >&2
}
prompt_info(){
	echo -e "${COL_ARROW}==> ${NO_COLOR}${COL_BOLD}$*${NO_COLOR}" >&2
}
prompt(){
	prompt_info "$*"
	echo -e "${COL_ARROW}==> ${NO_COLOR}${COL_BOLD}----------------------------------------------${NO_COLOR}" >&2
	echo -ne "${COL_ARROW}==>${NO_COLOR} " >&2
}
promptlight(){
	echo -ne "${COL_ARROW}==>${NO_COLOR} " >&2
}
error(){
	echo -e "${COL_RED}Error${NO_COLOR}: $*\n"
	return 1
}
cleanoutput(){
	(( ! TERMINALTITLE )) || [[ ! $DISPLAY ]] && return 0
	tput sgr0
}


