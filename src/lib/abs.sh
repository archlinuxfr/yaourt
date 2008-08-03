#!/bin/bash
#===============================================================================
#
#          FILE: abs.sh
# 
#   DESCRIPTION: yaourt's library to access Arch Building System Repository
# 
#       OPTIONS:  ---
#  REQUIREMENTS:  ---
#          BUGS:  ---
#         NOTES:  ---
#        AUTHOR:   Julien MISCHKOWITZ (wain@archlinux.fr) 
#       VERSION:  1.0
#===============================================================================

# grab PKGBUILD from repos.archlinux.org and run makepkg
install_from_abs(){
#msg "install $* from source with abs or with pacman"
if [ $NOCONFIRM -eq 0 -a $SYSUPGRADE -eq 1 ]; then
	echo
	_pkgs="$*"
	echo "$(eval_gettext 'Source Targets:  $_pkgs')"
	echo -ne "\n$(eval_gettext 'Proceed with upgrade? ') $(yes_no 1) "
	PROCEED_UPGD=`userinput`
fi
if [ "$PROCEED_UPGD" = "N" ]; then return; fi
USETESTING=0
if { LC_ALL="C"; pacman --debug 2>/dev/null| grep -q "debug: opening database 'testing'"; }; then USETESTING=1;fi
for package in $@; do
	PKG=${package#*/}
	local repository=`sourcerepository $PKG`
	if [ "$repository" = "community" ]; then
		communitypackages[${#communitypackages[@]}]=$PKG
	fi
	if [ $BUILD -eq 0 -a ! -f "/etc/customizepkg.d/$PKG" ]; then
		binariespackages[${#binariespackages[@]}]=$package
		continue
	fi
	[ "$MAJOR" != "getpkgbuild" ] && msg "Building $PKG from sources"
	title $(eval_gettext 'Install $PKG from sources')
	failed=0

	# Build From AUR [Community] ?
	if [ -z "$repository" ]; then echo $(eval_gettext '$PKG was not found on abs'); manage_error 1 || continue; fi
	#if [ "$repository" = "testing" ]; then
	#       	repository="all"
	#fi
	
	# Manage specific Community and Testing packages
	if [ "$repository" = "community" ]; then 
		# Grab link to download pkgbuild from AUR Community
		[ "$MAJOR" != "getpkgbuild" ] && msg $(eval_gettext 'Searching Community AUR page for $PKG')
		aurid=`findaurid "$PKG"`
		if [ -z "$aurid" ]; then
                        echo $(eval_gettext '$pkgname was not found on AUR')
			manage_error 1 || continue
		fi
		[ "$MAJOR" != "getpkgbuild" ] && aurcomments $aurid $PKG
		# Crapy Hack waiting for AUR to be up to date with new repos.archlinux.org
		category=`wget -q "http://aur.archlinux.org/packages.php?ID=$aurid" -O - | grep 'community ::' | sed 's|<[^<]*>||g' | awk '{print $3}'`
		if [ -z "$category" ]; then
                        echo $(eval_gettext 'Link to subversion repository was not found on AUR page')
			manage_error 1 || continue
		fi
		# EndofHack
		url="$ABS_REPOS_URL/community/$category/$PKG/?root=community"
	else
		# Grab link to download pkgbuild from new repos.archlinux.org
		source /etc/makepkg.conf
		[ -z "$CARCH" ] && CARCH="i686"
		wget -q "${ABS_REPOS_URL}/$PKG/repos/" -O - > "$YAOURTTMPDIR/page.tmp"
		if [ $? -ne 0 ] || [ ! -s "$YAOURTTMPDIR/page.tmp" ]; then
			echo $(eval_gettext '$PKG was not found on abs repos.archlinux.org'); manage_error 1 || continue
		fi
		repos=( `grep "name=.*i686" "$YAOURTTMPDIR/page.tmp" | awk -F "\"" '{print $2}'` )
		# if package exists in testing branch and in current branch, select the right url
		if [ ${#repos[@]} -gt 1 -a $USETESTING -eq 1 ]; then
			url="$ABS_REPOS_URL/$PKG/repos/${repos[1]}/"
		else
			url="$ABS_REPOS_URL/$PKG/repos/${repos[0]}/"
		fi
	fi

	# Download Files on SVN package page
	wget -q "$url" -O "$YAOURTTMPDIR/page.tmp"
	manage_error $? || continue
	files=( `grep "name=.*href=\"/viewvc.cgi/" "$YAOURTTMPDIR/page.tmp" | awk -F "\"" '{print $2}'`)
	if [ ${#files[@]} -eq 0 ]; then echo "No file found for $PKG"; manage_error 1 || continue; fi
	echo
	if [ "$MAJOR" != "getpkgbuild" ]; then
		msg $(eval_gettext 'Retrieving PKGBUILD and local sources...')
		wdir="$YAOURTTMPDIR/abs-$PKG"
		if [ -d "$wdir" ]; then
			rm -rf "$wdir" || { error $(eval_gettext 'Unable to delete directory $wdir. Please remove it using root privileges.'); return 1; }
		fi
		mkdir -p "$wdir" || { error $(eval_gettext 'Unable to create directory $wdir.'); return 1; }
		cd $wdir
	fi

	for file in ${files[@]}; do
		echo -e "   ${COL_BLUE}-> ${NO_COLOR}${COL_BOLD}$(eval_gettext 'Downloading ${file} in build dir')${NO_COLOR}"
		if [ "$repository" = "community" ]; then
			eval $INENGLISH wget --tries=3 --waitretry=3 --no-check-certificate "$ABS_REPOS_URL/community/$category/$PKG/$file?root=community\&view=co" -O $file
		else
			eval $INENGLISH wget --tries=3 --waitretry=3 --no-check-certificate "${url}${file}?view=co" -O $file
		fi
	done

	[ "$MAJOR" = "getpkgbuild" ] && return 0

	if [ $UID -eq 0 ]; then
		runasroot=1
        	warning $(eval_gettext 'Building package as root is dangerous.\n Please run yaourt as a non-privileged user.')
		sleep 2
	else
		runasroot=0
	fi
	
	readPKGBUILD
	if [ -z "$pkgname" ]; then
       		echo $(eval_gettext 'Unable to read PKGBUILD for $PKG')
		manage_error 1 || continue
	fi
	
	msg "$pkgname $pkgver-$pkgrel $([ "$branchtags" = "TESTING" ] && echo -e "$COL_BLINK[TESTING]")"
	
	# Customise PKGBUILD
	[ $CUSTOMIZEPKGINSTALLED -eq 1 ] && customizepkg --modify

	# show deps
	find_pkgbuild_deps
	manage_error $? || continue

	if [ $EDITPKGBUILD -eq 1 ]; then
		prompt $(eval_gettext 'Edit the PKGBUILD ? ') $(yes_no 2) $(eval_gettext '("A" to abort)')
		EDIT_PKGBUILD=$(userinput "YNA")
		echo
	fi
	
	if [ "$EDIT_PKGBUILD" = "Y" -a "$EDIT_PKGBUILD" != "A" ]; then
		if [ -z "$EDITOR" ]; then
			echo -e ${COL_RED}$(eval_gettext 'Please add \$EDITOR to your environment variables')
			echo -e ${NO_COLOR}$(eval_gettext 'for example:')
			echo -e ${COL_BLUE}"export EDITOR=\"gvim\""${NO_COLOR}" $(eval_gettext '(in ~/.bashrc)')"
			echo $(eval_gettext '(replace gvim with your favorite editor)')
			echo
			echo -ne ${COL_ARROW}"==> "${NO_COLOR}$(eval_gettext 'Edit PKGBUILD with: ')
			read -e EDITOR
			echo
		fi
		if [ "$EDITOR" = "gvim" ]; then edit_prog="gvim --nofork"; else edit_prog="$EDITOR";fi
		( $edit_prog ./PKGBUILD )
		wait
		find_pkgbuild_deps
		prompt $(eval_gettext 'Continue the building of ''$PKG''? ')$(yes_no 1)
 		if [ "`userinput`" = "N" ]; then
			manage_error 1 || continue
		fi
	fi
	
	if [ "$EDIT_PKGBUILD" = "a" -o "$EDIT_PKGBUILD" = "A" ]; then
		echo
		echo $(eval_gettext 'Aborted...')
		manage_error 1 || continue
	fi
	# TODO: dependecies from AUR should be downloaded here

	# compil PKGBUILD if dep's building not failed
	build_package	
	retval=$?
	if [ $retval -eq 1 ]; then
		manage_error 1 || continue
	elif [ $retval -eq 90 ]; then
		continue
	fi

	# Install, export, copy package after build 
	install_package
	manage_error $? || continue
done

# Install precompiled packages
if [ ${#binariespackages[@]} -gt 0 ]; then
	pacman_queuing;	launch_with_su "$PACMANBIN $ARGSANS ${binariespackages[*]}"
fi

# Vote for community packages
if [ ${#communitypackages[@]} -gt 0 -a $AURVOTE -eq 1 ]; then
	for pkgname in ${communitypackages[@]}; do
		aurid=`findaurid $pkgname`
		vote_package "$pkgname" "$aurid"
	done

fi

}
