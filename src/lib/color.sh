#!/bin/bash
#
# color.sh : color vars & colored output & title modification
# This file is part of Yaourt (http://archlinux.fr/yaourt-en)

# Set teminal title.
title(){
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
parse_color_var ()
{
	local vars="BOLD BLINK RED GREEN YELLOW BLUE PURPLE CYAN"
	local col key val colors_array=(${1//:/ })
	for col in "${colors_array[@]}"; do
		[[ $col =~ ^[A-Za-z]+=[0-9\;]+$ ]] || continue
		key=${col%=*} val="\033[${col#$key=}m"
		[[ " ${vars[*]} " =~ " $key " ]] && eval C$key=\"$val\" || colors[$key]="$val"
	done
}

initcolor ()
{
	((!USECOLOR)) || [[ $COLORMODE = "nocolor" ]] && return
	C0="\033[0m" 
	# yaourt colors 
	local yaourt_colors="BOLD=1:BLINK=5:RED=1;31:GREEN=1;32:YELLOW=1;33:BLUE=1;34:PURPLE=1;35:CYAN=1;36"
	# package-query colors (packages listing)
	local pq_colors="no=0:other=1;35:testing=1;31:core=1;31:extra=1;32:local=1;33:nb=7;33:pkg=1:installed=1;33;7:votes=1;33;7:od=1;33;7"
	# env COLORS
	export PQ_COLORS+="$pq_colors:$yaourt_colors:$YAOURT_COLORS"
	((USECOLOR==2)) || [[ $COLORMODE = "lightbg" ]] && PQ_COLORS=${PQ_COLORS//33/36} # lightbg!
	parse_color_var "$PQ_COLORS"
	trap "echo -ne '\033[0m'" 0
}
plain(){
	echo -e "$CBOLD$*$C0" >&2
}
_showmsg(){
	echo -en "$1==> $2$C0$CBOLD$3$C0" >&2
}
msg(){
	_showmsg "$CGREEN" "" "$*\n"
}
warning(){
	_showmsg "$CYELLOW" "$(gettext 'WARNING: ')" "$*\n"
}
P_UNDERLINE=${P_INDENT// /-}
prompt(){
	local t="$*"
	t=${#t}
	_showmsg "$CYELLOW" "" "$*\n"
	_showmsg "$CYELLOW" "" "${P_UNDERLINE:4:$t}\n"
	_showmsg "$CYELLOW"
}
prompt2(){
	_showmsg "$CYELLOW" "" "$* "
}
error(){
	_showmsg "$CRED" "$(gettext 'ERROR: ')" "$*\n"
	return 1
}

# vim: set ts=4 sw=4 noet: 
