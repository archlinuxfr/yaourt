#!/bin/bash
#===============================================================================
#
#          FILE: alpm_query.sh
# 
#   DESCRIPTION: yaourt's library to query packages from alpm database
# 
#       OPTIONS:  ---
#  REQUIREMENTS:  ---
#          BUGS:  ---
#         NOTES:  ---
#        AUTHOR:   Julien MISCHKOWITZ (wain@archlinux.fr) 
#       VERSION:  1.0
#===============================================================================

# Query installed version
pkgversion()
{
	package-query -Qif "%v" $1
}

# Test if $1 is installed or provided by an installed package
isavailable()
{
	package-query -1Siq $1 || package-query -1Sq -query-type provides $1
}

# Return package repository
sourcerepository()
{
	package-query -1SQif "%r" $1 
}

# search in sync db for packages wich depends on/conflicts whith/provides argument
searchforpackageswhich(){
	local action=$1
	local name=$2
	msg $(eval_gettext 'packages which '$action' on $name:')
	free_pkg
	package-query -S --query-type $action $name -f "pkgname=%n;pkgver=%v;lver=%l" |
	while read _line; do
		eval $_line
		echo -e $(display_pkg)
	done
}

search_which_package_owns(){
	for arg in ${args[@]}; do
		title $(eval_gettext 'Searching wich package owns "$arg"')
		argpath=$(type -p "$arg") || argpath="$arg"
		$PACMANBIN -Qo "$argpath"
	done
}

# searching for packages installed as dependecy from another packages, but not required anymore
search_forgotten_orphans(){
	local orphans
	msg "$(gettext 'Packages installed as dependencies but are no longer required by any installed package')"
	for _line in $(package-query -Qdtf "pkgname=%n;pkgver=%l;"); do
		eval $_line
		orphans+=($pkgname)
		echo -e $(display_pkg)
	done
	[[ $orphans ]] || return
	prompt "$(eval_gettext 'Do you want to remove these packages (with -Rcs options) ? ') $(yes_no 2)"
	if [[ "$(userinput)" = "Y" ]]; then
		$PACMANBIN -Rcs "${orphans[@]}"
	fi
}

# list installed packages filtered by criteria
list_installed_packages(){
	local _msg="" _opt=""
	(( ${#args[@]} )) && _opt="-i" || _opt="-S"
	if (( DEPENDS )); then
		_opt="$_opt -d"
		_msg='List all packages installed as dependencies'
	elif (( EXPLICITE )); then
		(( UNREQUIRED )) && _msg="and not required by any package" && _opt="$_opt -t"
		_msg="List all packages explicitly installed $_msg"
		_opt="$_opt -e"
	elif (( UNREQUIRED )); then
		_msg='List all packages installed (explicitly or as depends) and not required by any package'
		_opt="$_opt -t"
	elif (( FOREIGN )); then
		_msg='List installed packages not found in sync db(s)'
		_opt="$_opt -m"
	elif (( GROUP )); then
		_msg='List all installed packages members of a group'
		_opt="$_opt -g"
	elif (( DATE )); then
		_msg='List last installed packages '
		> $YAOURTTMPDIR/instdate
	else
		_msg='List all installed packages'
	fi
	title $(gettext "$_msg")
	msg $(gettext "$_msg")
	package-query -Qxf "_date=%1;repo=%s;pkgname=%n;pkgver=%l;group=\"%g\"" $_opt "${args[@]}"|
	while read _line; do
		eval $_line
		_msg=$(display_pkg)
		(( DATE )) && echo -e "$_date $_msg" >> $YAOURTTMPDIR/instdate || echo -e $_msg 
	done 

	if (( DATE )); then
		sort $YAOURTTMPDIR/instdate | awk '{
			printf("%s: %s\n", strftime("%X %x",$1), substr ($0, length($1)+1));
			}'
	fi
}

