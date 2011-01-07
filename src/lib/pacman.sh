#!/bin/bash
#
# pacman.sh: pacman interactions
# This file is part of Yaourt (http://archlinux.fr/yaourt-en)

# This file use global variables
# PKGS_IGNORED: IgnoredPkg + IgnoredGroup (exploded) in pacman.conf
# HoldPkg, SyncFirst ... 

parse_pacman_conf()
{
	# Parse pacman configuration
	local P_CONF
	readarray -t P_CONF < <(
	pacman_parse --verbose | sed -n \
		-e 's|/ *$|/|' \
		-e 's/^Conf File *: //p' \
		-e 's/^DB Path *: //p' \
		-e 's/^Cache Dirs *: //p' \
		-e 's/^Lock File *: //p' \
		-e 's/^Log File *: //p' )
	PACMANDB=${P_CONF[1]}
	CACHEDIR=${P_CONF[2]}
	LOCKFILE=${P_CONF[3]}
	# Parse pacman options
	unset PKGS_IGNORED HoldPkg SyncFirst
	declare -a IgnorePkg=() IgnoreGroup=()
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

# Wait while pacman locks exists
pacman_queue()
{
	# from nesl247
	if [[ -f "$LOCKFILE" ]]; then
		msg $(gettext 'Pacman is currently in use, please wait.')
		while [[ -f "$LOCKFILE" ]]; do
			sleep 3
		done
	fi
}

# launch pacman as root
su_pacman ()
{
	pacman_queue; launch_with_su $PACMAN "${PACMAN_C_ARG[@]}" "$@"
}

# Launch pacman and exit
pacman_cmd ()
{
	(( ! $1 )) && exec $PACMAN "${ARGSANS[@]}"
	prepare_orphan_list
	pacman_queue; launch_with_su $PACMAN "${ARGSANS[@]}"  
	local ret=$?
	(( ! ret )) && show_new_orphans
	exit $ret
}

# Refresh pacman database
pacman_refresh ()
{
	local _arg
	title $(gettext 'synchronizing package databases')
	(( REFRESH > 1 )) && _arg="-Syy" || _arg="-Sy"
	su_pacman $_arg || exit $?
}


is_package_ignored ()
{
	if [[ " ${PKGS_IGNORED[@]} " =~ " $1 " ]]; then
		(($2)) && echo -e "$1: $CRED "$(gettext '(ignoring package upgrade)')"$C0"
		return 0
	fi
	return 1
}

# is_x_gt_y ($ver1,$ver2)
is_x_gt_y()
{
	[[ $(vercmp "$1" "$2" 2> /dev/null) -gt 0 ]]
}

# vim: set ts=4 sw=4 noet: 
