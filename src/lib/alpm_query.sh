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
	package-query -SQ --query-type $action $name -f "%s %n %v %l" |
	while read repo pkgname pkgver lver; do
		display_pkg
		echo -e $pkgoutput
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
	AUR_SEARCH=0 search 0 1
	[[ $PKGSFOUND ]] || return
	prompt "$(eval_gettext 'Do you want to remove these packages (with -Rcs options) ? ') $(yes_no 2)"
	useragrees "YN" "N" || su_pacman -Rcs "${PKGSFOUND[@]#*/}"
}

