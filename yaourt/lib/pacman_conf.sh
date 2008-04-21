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


# take the list of activated repositories from pacman.conf
list_repositories(){
		repositories=( `LC_ALL="C"; pacman --debug 2>/dev/null| grep "debug: opening database '" | awk '{print $4}' |uniq| tr -d "'"| grep -v 'local'` )
}

# list all ignorepkg from pacman.conf
create_ignorepkg_list(){
	LC_ALL="C" pacman --debug 2>/dev/null | grep "^debug: config: IgnorePkg:" |awk '{print $4}' > $tmp_files/ignorelist
}
