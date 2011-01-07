#!/bin/bash
#
# alpm_query.sh : Query alpm database
# This file is part of Yaourt (http://archlinux.fr/yaourt-en)

# Query installed version
pkgversion()
{
	pkgquery -Qif "%v" "$1"
}

# Test if $1 is installed or provided by an installed package
isavailable()
{
	pkgquery -1Siq "$1" || pkgquery -1Sq --query-type provides "$1"
}

# Return package repository
sourcerepository()
{
	pkgquery -1SQif "%r" "$1" 
}

# Get pkgbase
get_pkgbase ()
{
	local pkgbase pkgname=$1 repo=$2 pkgver=$3
	[[ -z $repo || -z $pkgver ]] && read repo pkgver < <(pkgquery -Sif '%r %n' $pkgname)
	pkgbase=$(sed -n '/%BASE%/,/^$/ { /^[^%]/p}' "${P[dbpath]}/sync/$repo/$pkgname-$pkgver/desc" 2> /dev/null)
	echo ${pkgbase:-$pkgname}
}

# search in sync db for packages wich depends on/conflicts whith/provides argument
searchforpackageswhich(){
	local _opt _msg action="$1" name="$2"
	case "$action" in
		depends) _msg='Packages which depend on %s:';;
		conflicts) _msg='Packages which conflict with %s:';;
		replaces) _msg='Packages which replace %s:';;
		provides) _msg='Packages which provide %s:';;
	esac
	msg $(_gettext "$_msg" "$name")
	[[ "$MAJOR" = "query" ]] && _opt="-Q" || _opt="-S"
	pkgquery $_opt --query-type $action "$name"
}

# searching for packages installed as dependecy from another packages, but not required anymore
search_forgotten_orphans(){
	#msg "$(gettext 'Packages installed as dependencies but are no longer required by any installed package')"
	AURSEARCH=0 search 0
	[[ $PKGSFOUND ]] || return
	prompt "$(gettext 'Do you want to remove these packages (with -Rcs options) ? ') $(yes_no 2)"
	useragrees "YN" "N" || su_pacman -Rcs "${PKGSFOUND[@]#*/}"
}
# vim: set ts=4 sw=4 noet: 
