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

# search in sync db for packages wich depends on/conflicts whith/provides argument
searchforpackageswhich(){
	local action="$1"
	local name="$2"
	case "$action" in
		depends) _msg='Packages which depend on $name:';;
		conflicts) _msg='Packages which conflict with $name:';;
		replaces) _msg='Packages which replace $name:';;
		provides) _msg='Packages which provide $name:';;
	esac
	msg $(eval_gettext "$_msg")
	if [[ "$MAJOR" = "query" ]]; then
		_opt=(-Qf '%s %n %v -') 
	else
		_opt=(-Sf '%r %n %v %l')
	fi
	pkgquery "${_opt[@]}" --query-type $action "$name" |
	while read repo pkgname pkgver lver; do
		pkg_output "$repo" "$pkgname" "$pkgver" "$lver"
		echo -e "$pkgoutput"
	done
}

search_which_package_owns(){
	for arg in ${args[@]}; do
		title $(eval_gettext 'Searching wich package owns "$arg"')
		argpath=$(type -p "$arg") || argpath="$arg"
		$PACMANBIN "${PACMAN_C_ARG[@]}" -Qo "$argpath"
	done
}

# searching for packages installed as dependecy from another packages, but not required anymore
search_forgotten_orphans(){
	local orphans
	msg "$(gettext 'Packages installed as dependencies but are no longer required by any installed package')"
	AUR_SEARCH=0 search 0
	[[ $PKGSFOUND ]] || return
	prompt "$(eval_gettext 'Do you want to remove these packages (with -Rcs options) ? ') $(yes_no 2)"
	useragrees "YN" "N" || su_pacman -Rcs "${PKGSFOUND[@]#*/}"
}
# vim: set ts=4 sw=4 noet: 
