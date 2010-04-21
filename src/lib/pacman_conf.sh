#!/bin/bash
#===============================================================================
#
#          FILE:  pacman_conf.sh
# 
#   DESCRIPTION: yaourt's library to parse pacman configuration
# 
#       OPTIONS:  ---
#  REQUIREMENTS:  ---
#          BUGS:  ---
#         NOTES:  ---
#        AUTHOR:   Julien MISCHKOWITZ (wain@archlinux.fr) 
#       VERSION:  1.0
#===============================================================================

# This file use global variables
# repositories:	Respoitories configured in pacman.conf
# PKGS_IGNORED: IgnoredPkg + IgnoredGroup (exploded) in pacman.conf
# HoldPkg, SyncFirst ... 



# take the list of activated repositories from pacman.conf
list_repositories(){
		repositories=( $(package-query -L) )
}

parse_pacman_conf()
{
	unset PKGS_IGNORED IgnoredPkg IgnoredGroup HoldPkg SyncFirst
	eval $(LC_ALL=C pacman --debug | sed -n 's/debug: config: \([a-zA-Z]\+\): \(.*\)/\1+=(\2)/p')
	PKGS_IGNORED=("${IgnoredPkg[@]}" $(pacman -Qqg "${IgnoredGroup[@]}"))
}
