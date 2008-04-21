#!/bin/bash
#===============================================================================
#
#          FILE: aur.sh
# 
#   DESCRIPTION: yaourt's library to access Arch User Repository
# 
#       OPTIONS:  ---
#  REQUIREMENTS:  ---
#          BUGS:  ---
#         NOTES:  ---
#        AUTHOR:   Julien MISCHKOWITZ (wain@archlinux.fr) 
#       VERSION:  1.0
#===============================================================================

# get info for aur package from json RPC interface and store it in jsonfinfo variable for later use
initjsoninfo(){
unset jsoninfo
jsoninfo=`wget -q -O - "http://aur.archlinux.org/rpc.php?type=info&arg=$1"`
if  echo $jsoninfo | grep -q '"No result found"' || [ -z "$jsoninfo" ]; then
	return 1
else
	return 0
fi
}

#Get value from json (in memory):  ID, Name, Version, Description, URL, URLPath, License, NumVotes, OutOfDate
parsejsoninfo(){
	echo $jsoninfo | sed -e 's/^.*[{,]"'$1'":"//' -e 's/"[,}].*$//'
}

# return 0 if package is on AUR Unsupported else 1
is_unsupported(){
	initjsoninfo $1 || return 1
	[ ! -z "`parsejsoninfo URLPath`" ] && return 0
	return 1
}


# return 0 if package is on AUR Community else 1
is_in_community(){
	initjsoninfo $1 || return 1
	[ -z "`parsejsoninfo URLPath`" ] && return 0
	return 1
}

# Grab info for package on AUR Unsupported
info_from_aur() {
title "Searching info on AUR for $1"
PKG=$1
tmpdir="$YAOURTTMPDIR/$PKG"
mkdir -p $tmpdir
cd $tmpdir
wget -O PKGBUILD -q http://aur.archlinux.org/packages/$PKG/$PKG/PKGBUILD || { echo "$PKG not found in repos nor in AUR"; return 1; }
readPKGBUILD
if [ -z "$pkgname" ]; then
       echo "Unable to read $PKG's PKGBUILD"
       return 1
fi
echo "Repository	: AUR Unsupported"
echo "Name		: $pkgname"
echo "Version		: $pkgver-$pkgrel"
echo "url		: $url"
echo -n "Provides	: "; if [[ ! -z "${provides[@]}" ]]; then echo "${provides[@]}"; else echo "None"; fi
echo -n "Depends On	: "; if [[ ! -z "${depends[@]}" ]]; then echo "${depends[@]}"; else echo "None"; fi
echo -n "Conflicts With	: "; if [[ ! -z "${conflicts[@]}" ]]; then echo "${conflicts[@]}"; else echo "None"; fi
echo -n "Replaces	: "; if [[ ! -z "${replaces[@]}" ]]; then echo "${replaces[@]}"; else echo "None"; fi
echo "Description	: $pkgdesc"
echo "Last update	: `ls -l --time-style="long-iso" PKGBUILD | awk '{print $6" "$7}'`"
echo
}
