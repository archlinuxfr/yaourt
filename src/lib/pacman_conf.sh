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
# PKGS_IGNORED: IgnorePkg in pacman.conf

# take the list of activated repositories from pacman.conf
list_repositories(){
		repositories=( $(package-query -L) )
}

# list all ignorepkg from pacman.conf
create_ignorepkg_list(){
	PKGS_IGNORED=($(LC_ALL="C" pacman --debug 2>/dev/null |
		grep "^debug: config: IgnorePkg: " | awk '{print $NF}'))
	local ignored_grp=($(LC_ALL="C" pacman --debug 2>/dev/null |
		grep "^debug: config: IgnoreGroup: " | awk '{print $NF}'))
	[[ $ignored_grp ]] && PKGS_IGNORED+=($(pacman -Sgq ${ignored_grp[@]}))
}
