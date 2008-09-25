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

# download package from repos or grab PKGBUILD from repos.archlinux.org and run makepkg
install_from_abs(){
if [ $NOCONFIRM -eq 0 -a $SYSUPGRADE -eq 1 ]; then
	echo
	_pkgs="$*"
	echo "$(eval_gettext 'Source Targets:  $_pkgs')"
	echo -ne "\n$(eval_gettext 'Proceed with upgrade? ') $(yes_no 1) "
	PROCEED_UPGD=`userinput`
fi
if [ "$PROCEED_UPGD" = "N" ]; then return; fi
USETESTING=0
if { LC_ALL=C pacman --debug 2>/dev/null| grep -q "debug: opening database 'testing'"; }; then USETESTING=1;fi
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
	#pacman_queuing;	launch_with_su "$PACMANBIN $ARGSANS ${binariespackages[*]}"
	pacman_queuing;	launch_with_su "$PACMANBIN --sync $force $confirmation $nodeps $asdeps ${binariespackages[*]}"
fi

# Vote for community packages
if [ ${#communitypackages[@]} -gt 0 -a $AURVOTE -eq 1 ]; then
	for pkgname in ${communitypackages[@]}; do
		aurid=`findaurid $pkgname`
		vote_package "$pkgname" "$aurid"
	done

fi

}


#Downgrade all packages marked as "newer than extra/core/etc..."
sysdowngrade()
{
	if [ $DOWNGRADE -eq 1 ]; then
		msg $(eval_gettext 'Downgrading packages')
		title $(eval_gettext 'Downgrading packages')
		downgradelist=( `LC_ALL=C $PACMANBIN -Qu | grep "is newer than" | awk -F ":" '{print $2}'` )    
		if [ ${#downgradelist[@]} -gt 0 ]; then
			prepare_orphan_list
			SYSUPGRADE=2
			install_from_abs ${downgradelist[*]}
			show_new_orphans
		else
			echo $(eval_gettext 'No package to downgrade')
		fi
		die
	fi
}


# Searching for packages to update, buid from sources if necessary
sysupgrade()
{
	prepare_orphan_list
	if [ $SUDOINSTALLED -eq 1 ] && sudo -l | grep "\(pacman\ *$\|ALL\)" 1>/dev/null; then
		sudo $PACMANBIN --sync --sysupgrade --print-uris $NEEDED $IGNOREPKG 1>$YAOURTTMPDIR/sysupgrade
	elif [ "$UID" -eq 0 ]; then
		$PACMANBIN --sync --sysupgrade --print-uris $NEEDED $IGNOREPKG 1> $YAOURTTMPDIR/sysupgrade
	else
		launch_with_su "$PACMANBIN --sync --sysupgrade --print-uris $NEEDED $IGNOREPKG 1> $YAOURTTMPDIR/sysupgrade"
	fi
	
	if [ $? -ne 0 ]; then
		cat $YAOURTTMPDIR/sysupgrade
	fi
	packages=( `grep '://' $YAOURTTMPDIR/sysupgrade | sed -e "s/-i686.pkg.tar.gz$//" \
	-e "s/-[^ ]x86_64.pkg.tar.gz$//" -e "s/-any.pkg.tar.gz$//" -e "s/.pkg.tar.gz//" -e "s/^.*\///" -e "s/-[^-]*-[^-]*$//" | sort --reverse` )

	# Show various avertissements
	pacman -Qu | sed -n '1,/^$/p' | sed '/^$/d'

	# Specific upgrade: pacman and yaourt first. Ask to mount /boot for kernel26 or grub
	for package in ${packages[@]}; do
		case $package in
			pacman|yaourt)
			warning $(eval_gettext 'New version of $package detected')
			prompt $(eval_gettext 'Do you want to update $package first ? ')$(yes_no 1)
			[ "`userinput`" = "N" ] && continue
			echo
			msg $(eval_gettext 'Upgrading $package first')
			pacman_queuing; launch_with_su "$PACMANBIN -S $package"
		        die 0
			;;
			grub|kernel26*)
			if [ `ls /boot/ | wc -l` -lt 2 ]; then
				warning $(eval_gettext 'New version of $package detected')
				prompt $(eval_gettext 'Please mount your boot partition first then press ENTER to continue')
				read
			fi
			;;
		esac
	done


	### classify pkg to upgrade, filtered by category "new release", "new version", "new pkg"
	pkg_repository_name_ver=( `grep "://" $YAOURTTMPDIR/sysupgrade | sed -e "s/^.*\///" -e "s/-i686.pkg.tar.gz$//" -e "s/-[^ ]x86_64.pkg.tar.gz$//" -e "s/-any.pkg.tar.gz$//" -e "s/.pkg.tar.gz//" -e "s/-[a-z0-9_.]*-[a-z0-9.]*$/##&/" | sort`)
	for pkg in ${pkg_repository_name_ver[@]}; do
		pkgname=`echo $pkg| awk -F '##' '{print $1}'`
		repository=`sourcerepository $pkgname`
		rversion=`echo $pkg| awk -F '##' '{print $2}' | sed 's/^-//'`
		if `isinstalled $pkgname`; then
			lversion=`pkgversion $pkgname`
			lrel=${lversion#*-}
			rrel=${rversion#*-}
			lver=${lversion%-*}
			rver=${rversion%-*}
			if [ "$rver" = "$lver" ] && `is_x_gt_y $rrel $lrel`; then
				# new release not a new version
				newrelease[${#newrelease[@]}]="$repository##$pkgname##$rver##$lrel##$rrel"
			else
			        # new version
			        newversion[${#newversion[@]}]="$repository##$pkgname##$lversion##$rversion"
			fi
		else
			# new package (not installed at this time)
			newpkgs[${#newpkgs[@]}]="$repository##$pkgname##$rversion"
		fi
	done

	# Show result
	showupgradepackage lite
        
	# Show detail on upgrades
	if [ ${#packages[@]} -gt 0 ]; then                                                                                                           
		if [ $NOCONFIRM -eq 0 ]; then
			CONTINUE_INSTALLING="V"
			while [ "$CONTINUE_INSTALLING" = "V" -o "$CONTINUE_INSTALLING" = "C" ]; do
				echo
				echo -e "${COL_ARROW}==>  ${NO_COLOR}${COL_BOLD}"$(eval_gettext 'Continue installing ''$PKG''? ') $(yes_no 1)"${NO_COLOR}" >&2
				prompt $(eval_gettext '[V]iew package detail   [M]anualy select packages')
				CONTINUE_INSTALLING=$(userinput "YNVM")
				echo
				if [ "$CONTINUE_INSTALLING" = "V" ]; then
					showupgradepackage full
				elif [ "$CONTINUE_INSTALLING" = "M" ]; then
					showupgradepackage manual
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
					( $edit_prog $YAOURTTMPDIR/sysuplist )
					wait
					declare args="$YAOURTTMPDIR/sysuplist"
					SYSUPGRADE=2
					sync_packages
					die 0
				elif [ "$CONTINUE_INSTALLING" = "N" ]; then
					die 0
				fi
			done
		fi
	fi  

	# ok let's do real sysupgrade
	if [ ${#packages[@]} -gt 0 ]; then
		# List packages to build
		if [ $BUILD -eq 1 -o $CUSTOMIZEPKGINSTALLED -eq 1 ] && [ $DOWNLOAD -eq 0 ]; then
			for package in ${packages[@]}; do
				if [ $BUILD -eq 1 -o -f "/etc/customizepkg.d/$package" ]; then
					packagesfromsource[${#packagesfromsource[@]}]=$package
				fi
			done
		fi
		# Show package list before building
		if [ ${#packagesfromsource[@]} -gt 0 ]; then
			eval $PACMANBIN --query --sysupgrade $NEEDED $IGNOREPKG
			if [ $NOCONFIRM -eq 0 ]; then
				echo -n $(eval_gettext 'Proceed with installation? ')$(yes_no 1)
				proceed=`userinput`
			fi
		fi
		# Build some packages if needed, then launch pacman classic sysupgrade
		if [ "$proceed" != "N" ]; then
			if [ ${#packagesfromsource[@]} -gt 0 ]; then
				BUILD=1
				install_from_abs "${packagesfromsource[*]}"
			fi
			if [ ${#packages[@]} -gt ${#packagesfromsource[@]} ]; then
				pacman_queuing;	launch_with_su "$PACMANBIN $ARGSANS"
			fi
		fi
	#else
		# Nothing to update. Show various infos
		#eval $PACMANBIN --query --sysupgrade $NEEDED $IGNOREPKG
	fi
}

## show package to upgrade
showupgradepackage()
{
	# $1=full or $1=lite or $1=manual
	if [ "$1" = "manual" ]; then
		> $YAOURTTMPDIR/sysuplist
		local separator="################################################"
	fi

	# show new release
	if [ ${#newrelease[@]} -gt 0 ]; then
		echo
		declare newrelease=`echo -e ${newrelease[*]} | tr ' ' '\n' | sort`
		if [ "$1" = "manual" ]; then
			echo -e "$separator\n# $(eval_gettext 'Package upgrade only (new release):')\n$separator" >> $YAOURTTMPDIR/sysuplist
		else
			msg $(eval_gettext 'Package upgrade only (new release):')
		fi
		for line in ${newrelease[@]}; do
			repository=`echo $line| awk -F '##' '{print $1}'`
			pkgname=`echo $line| awk -F '##' '{print $2}'`
			rver=`echo $line| awk -F '##' '{print $3}'`
			lrel=`echo $line| awk -F '##' '{print $4}'`
			rrel=`echo $line| awk -F '##' '{print $5}'`
			if [ "$1" = "manual" ]; then
				echo -e "\n$repository/$pkgname version $rver release $lrel -> $rrel"  >> $YAOURTTMPDIR/sysuplist
				echo "#    `pkgdescription $pkgname`" >> $YAOURTTMPDIR/sysuplist
			else
				echo -e `colorizeoutputline $repository/$NO_COLOR$COL_BOLD$pkgname`"$NO_COLOR version $COL_GREEN$rver$NO_COLOR release $COL_BOLD$lrel$NO_COLOR -> $COL_RED$rrel$NO_COLOR"
				[ "$1" = "full" ] && echo -e "    $COL_ITALIQUE`pkgdescription $pkgname`$NO_COLOR"
			fi
		done
	fi
	
	# show new version
	if [ ${#newversion[@]} -gt 0 ]; then
		echo
		declare newversion=`echo -e ${newversion[*]} | tr ' ' '\n' | sort`
		if [ "$1" = "manual" ]; then
			echo -e "\n\n$separator\n# $(eval_gettext 'Software upgrade (new version) :')\n$separator" >> $YAOURTTMPDIR/sysuplist
		else
			msg $(eval_gettext 'Software upgrade (new version) :')
		fi
		for line in ${newversion[@]}; do
			repository=`echo $line| awk -F '##' '{print $1}'`
			pkgname=`echo $line| awk -F '##' '{print $2}'`
			lversion=`echo $line| awk -F '##' '{print $3}'`
			rversion=`echo $line| awk -F '##' '{print $4}'`
			if [ "$1" = "manual" ]; then
                        	echo -e "\n$repository/$pkgname $lversion -> $rversion" >> $YAOURTTMPDIR/sysuplist
				echo "#    `pkgdescription $pkgname`" >> $YAOURTTMPDIR/sysuplist
			else
                        	echo -e `colorizeoutputline $repository/$NO_COLOR$COL_BOLD$pkgname`$NO_COLOR" $COL_GREEN$lversion$NO_COLOR -> $COL_RED$rversion$NO_COLOR"
				[ "$1" = "full" ] && echo -e "    $COL_ITALIQUE`pkgdescription $pkgname`$NO_COLOR"
			fi
		done
	fi

        # show new package
        if [ ${#newpkgs[@]} -gt 0 ]; then
        	echo
		declare newpkgs=`echo -e ${newpkgs[*]} | tr ' ' '\n' | sort`
		if [ "$1" = "manual" ]; then
			echo -e "\n$separator\n# $(eval_gettext 'New package :')\n$separator" >> $YAOURTTMPDIR/sysuplist
		else
			msg $(eval_gettext 'New package :')
		fi
		for line in ${newpkgs[@]}; do
			repository=`echo $line| awk -F '##' '{print $1}'`
			pkgname=`echo $line| awk -F '##' '{print $2}'`
			### Searching for package which depends on 'new package'
			requiredbypkg=$(eval_gettext 'not found')
			for pkg in ${pkg_repository_name_ver[@]%\#\#*}; do
				if [ "$pkg" != "$pkgname" ] && `LC_ALL=C pacman -Si $pkg |grep -m1 -A15 "^Repository"| sed -e '1,/^Provides/d' -e '/^Optional\ Deps/,$d'\
				       | grep -q "\ $pkgname[ >=<]"`; then
					requiredbypkg=$pkg
					break
				fi
			done

			if [ "$1" = "manual" ]; then
				echo -e "\n$repository/$pkgname $rversion" >> $YAOURTTMPDIR/sysuplist
				echo "#    `pkgdescription $pkgname` $(eval_gettext '(required by $requiredbypkg)')" >> $YAOURTTMPDIR/sysuplist
			else
				echo -e `colorizeoutputline $repository/$NO_COLOR$COL_BOLD$pkgname`" $COL_GREEN$rversion $COL_RED $(eval_gettext '(required by $requiredbypkg)')$NO_COLOR"
				[ "$1" = "full" ] && echo -e "    $COL_ITALIQUE`pkgdescription $pkgname`$NO_COLOR"
			fi
		done
	fi
}

# Sync packages
sync_packages()
{
	# Install from a list of packages
	if [ -f "${args[0]}" ] && file -b "${args[0]}" | grep -qi text ; then
		if [ $SYSUPGRADE -eq 0 ]; then 
			title $(eval_gettext 'Installing from a list of a packages')
			msg $(eval_gettext 'Installing from a list of a packages ($_pkg_list)')
		fi
		_pkg_list=${args[0]}
		AURVOTE=0
		args=( `cat "${args[0]}" | grep -v "^#" | awk '{print $1}'` ) 
	fi

	# Install from arguments
	prepare_orphan_list
	for arg in ${args[@]}; do
		if `isavailable ${arg#*/}` && [ $AUR -eq 0 -a ! "$(echo $arg | grep "^aur/")" ]; then
			repos_package[${#repos_package[@]}]=${arg}
		else
			install_from_aur "${arg#aur/}" || failed=1
		fi
	done
	[ ${#repos_package[@]} -gt 0 ] && install_from_abs "${repos_package[*]}"
	show_new_orphans
}

upgrade_devel_package(){
	tmp_files="$YAOURTTMPDIR/search/"
	mkdir -p $tmp_files
	local i=0
	title $(eval_gettext 'upgrading SVN/CVS/HG/GIT package')
	msg $(eval_gettext 'upgrading SVN/CVS/HG/GIT package')
	loadlibrary pacman_conf
	create_ignorepkg_list || error $(eval_gettext 'list ignorepkg in pacman.conf')
	for PKG in $(pacman -Qq | grep "\-\(svn\|cvs\|hg\|git\|bzr\|darcs\)")
	do
		if grep "^${PKG}$" $tmp_files/ignorelist > /dev/null; then
			echo -e "${PKG}: ${COL_RED} "$(eval_gettext '(ignored from pacman.conf)')"${NO_COLOR}"
		else
			devel_package[$i]=$PKG
			(( i ++ ))
		fi
	done
	[ $i -lt 1 ] && return 0
	plain "\n---------------------------------------------"
	plain $(eval_gettext 'SVN/CVS/HG/GIT/BZR packages that can be updated from ABS or AUR:')
	echo "${devel_package[@]}"
	if [ $NOCONFIRM -eq 0 ]; then
		prompt $(eval_gettext 'Do you want to update these packages ? ') $(yes_no 1)
		[ "`userinput`" = "N" ] && return 0
	fi
	for PKG in ${devel_package[@]}; do
		local repository=`sourcerepository $PKG`
		case $repository in
			core|extra|unstable|testing|community)	
			BUILD=1
			repos_package[${#repos_package[@]}]=${PKG}
			;;
			*)	       
			install_from_aur "$PKG" 
			;;
		esac
	done
	[ ${#repos_package[@]} -gt 0 ] && install_from_abs "${repos_package[*]}"
}
