#!/bin/bash
#
# pacman_conf.sh: parse and query pacman.conf file
# This file is part of Yaourt (http://archlinux.fr/yaourt-en)

# This file use global variables
# PKGS_IGNORED: IgnoredPkg + IgnoredGroup (exploded) in pacman.conf
# HoldPkg, SyncFirst ... 

parse_pacman_conf()
{
	unset PKGS_IGNORED IgnorePkg IgnoreGroup HoldPkg SyncFirst
	eval $(pacman_parse --debug | 
		sed -n  -e 's/"/\\"/g' \
		  -e 's/debug: config: \([a-zA-Z]\+\): \(.*\)/\1+=("\2")/p'
	)
	IGNOREPKG+=("${IgnorePkg[@]}")
	PKGS_IGNORED=("${IGNOREPKG[@]}")
	IGNOREGRP+=("${IgnoreGroup[@]}")
	[[ $IGNOREGRP ]] && PKGS_IGNORED+=($(pacman_parse -Sqg "${IGNOREGRP[@]}"))
	return 0
}

is_package_ignored ()
{
	if [[ " ${PKGS_IGNORED[@]} " =~ " $1 " ]]; then
		(($2)) && echo -e "$1: $CRED "$(gettext '(ignoring package upgrade)')"$C0"
		return 0
	fi
	return 1
}

# Parse pacman.conf when library is loaded.
parse_pacman_conf
# vim: set ts=4 sw=4 noet: 
