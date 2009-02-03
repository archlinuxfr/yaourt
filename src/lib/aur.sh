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

# get info for aur package from json RPC interface and store it in jsoninfo variable for later use
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

while true; do
	prompt $(eval_gettext 'Edit the PKGBUILD (highly recommended for security reasons) ? ')$(yes_no 1)$(eval_gettext '("A" to abort)')
	EDIT_PKGBUILD=$(userinput "YNA")
	echo
	if [ "$EDIT_PKGBUILD" = "A" ]; then
		echo $(eval_gettext 'Aborted...')
		return 1
	elif [ "$EDIT_PKGBUILD" != "N" ]; then
		edit_file ./PKGBUILD
	else
		break
	fi
done
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

# search for keyword on AUR an list result
search_on_aur(){
	#msg "Search for $1 on AUR"
	_pkg=`echo $1 | sed 's/ AND / /'`
	title $(eval_gettext 'searching for $_pkg on AUR')
	[ "$MAJOR" = "interactivesearch" ] && i=$(($(wc -l $searchfile | awk '{print $1}')+1))
	# grab info from json rpc url and exclude community packages, then parse result
	wget -q -O - "http://aur.archlinux.org/rpc.php?type=search&arg=$1" | sed 's/{"ID":/\n/g' | sed '1d'| grep -Fv '"URLPath":""' |
	while read jsoninfo; do
		# exclude first line
		[ $(echo $jsoninfo | awk -F '"[:,]"' '{print NF}') -lt 10 ] && continue
		package=$(parsejsoninfo Name)
		version=$(parsejsoninfo Version)
		description=$(parsejsoninfo Description)
		numvotes=$(parsejsoninfo NumVotes)
		outofdate=$(parsejsoninfo OutOfDate)
		line="${COL_ITALIQUE}${COL_REPOS}aur/${NO_COLOR}${COL_BOLD}${package} ${COL_GREEN}${version}"
		if isinstalled $package; then
			lversion=`pkgversion $package`
			if [ "$lversion" = "$version" ];then
				line="$line ${COL_INSTALLED}[$(eval_gettext 'installed')]"
			else
				line="$line ${COL_INSTALLED}[${COL_RED}$lversion${COL_INSTALLED} $(eval_gettext 'installed')]"
			fi
		fi
		if [ $outofdate -eq 1 ]; then
			line="$line${NO_COLOR} ${COL_INSTALLED}($(eval_gettext 'Out of Date'))"
		fi
		if [ "$MAJOR" = "interactivesearch" ]; then
			line="${COL_NUMBER}${i}${NO_COLOR} $line"
			echo "aur/${package}" >> $searchfile 
			(( i ++ ))
		fi
		echo -e "$line$NO_COLOR $COL_NUMBER($numvotes)${NO_COLOR}"
		echo -e "    ${COL_ITALIQUE}$description${NO_COLOR}"
	done
	cleanoutput
}

# scrap html page to show user's comments
aurcomments(){
	wget --quiet "${AUR_URL3}${1}" -O - \
	| tr '\r' '\n' | sed -e '/-- End of main content --/,//d' \
	-e 's|<[^<]*>||g' \
	-e 's|&quot;|"|g' \
	-e 's|&lt;|<|g' \
	-e 's|&gt;|>|g' \
	-e '/^\t*$/d' \
	-e '/^ *$/d' > ./aurpage
	if [ $AURCOMMENT -eq 1 ]; then
		numcomment=0
		rm -rf ./comments || error $(eval_gettext 'can not remove old comments')
		mkdir -p comments
		cat ./aurpage | sed -e '1,/^Tarball ::/d' -e '/^$/d' |
		while read line; do
			if echo $line |grep -q "Comment by:"; then
				(( numcomment ++ ))
				if [ $numcomment -gt $MAXCOMMENTS -a $MAXCOMMENTS -ne 0 ]; then
					msg $(eval_gettext 'Last $MAXCOMMENTS comments ordered by date ($ORDERBY):')
					break
				fi
			fi
			echo $line >> comments/$numcomment
		done

		numcomment=`ls comments/ | wc -l`
		if [ $numcomment -gt $MAXCOMMENTS -a $MAXCOMMENTS -ne 0 ]; then
			limit=$MAXCOMMENTS
		else
			limit=$numcomment
		fi      
		if [ "$ORDERBY" = "asc" ]; then
			liste=`seq $limit -1 1`
		elif [ "$ORDERBY" = "desc" ]; then
			liste=`seq 1 1 $limit`
		fi
		for comment in ${liste[*]}; do
			if [ -f "comments/$comment" ]; then
				cat comments/$comment |
				while read line; do
					echo -e ${line/#Comment by:/\\n${COL_YELLOW}Comment by:}$NO_COLOR
				done
			fi
		done
	fi
	echo
	grep "First Submitted" ./aurpage | sed "s/First/\n      &/" |sort
}

# find ID for given package 
findaurid(){
	wget -q -O - "http://aur.archlinux.org/rpc.php?type=info&arg=$1"| sed -e 's/^.*{"ID":"//' -e 's/",".*$//'| sed '/^$/d'
}

# Check if this package has been voted on AUR, and vote for it
vote_package(){
	if [ $AURVOTEINSTALLED -eq 0 ]; then
		echo -e "${COL_ITALIQUE}"$(eval_gettext 'If you like this package, please install aurvote\nand vote for its inclusion/keeping in [community]')"${NO_COLOR}"
	else
		echo
		_pkg=$1
		msg $(eval_gettext 'Checking vote status for $_pkg')
		pkgvote=`aurvote --id --check "$1/$2"`
		if [ "${pkgvote}" = "already voted" ]; then
			_pkg=$1
			echo $(eval_gettext 'You have already voted for $_pkg inclusion/keeping in [community]')
		elif [ "$pkgvote" = "not voted" ]; then
			echo
			if [ $NOCONFIRM -eq 0 ]; then
				_pkg=$1
				prompt $(eval_gettext 'Do you want to vote for $_pkg inclusion/keeping in [community] ? ')$(yes_no 1)
				VOTE=`userinput`
			fi
			if [ "$VOTE" != "N" ]; then
				aurvote --id --vote "$1/$2"
			fi
		else
			echo $pkgvote
		fi
	fi

}

# give to user all info to build and install Unsupported package from AUR
install_from_aur(){
	pkgname=
	pkgdesc=
	pkgver=
	pkgrel=
	runasroot=0
	failed=0
	DEP_AUR=( )
	local PKG="$1"
	title $(eval_gettext 'Installing $PKG from AUR')
	UID_ROOT=0
	if [ "$UID" -eq "$UID_ROOT" ]
	then
		runasroot=1
		warning $(eval_gettext 'Building unsupported package as root is dangerous.\n Please run yaourt as a non-privileged user.')
		sleep 2
	fi

	wdir="$YAOURTTMPDIR/aur-$PKG"

	if [ -d "$wdir" ]; then
		msg $(eval_gettext 'Resuming previous build')
	else
		mkdir -p "$wdir" || { error $(eval_gettext 'Unable to create directory $wdir.'); return 1; }
	fi
	cd "$wdir/"

	# Initialize jsoninfo & exclude package moved into community repository	
	initjsoninfo $PKG || { echo -e "${COL_YELLOW}"$(eval_gettext '$PKG not found on AUR')"${NO_COLOR}"; continue; }
	
	# grab comments and info from aur page
	echo
	aurid=$(parsejsoninfo ID)
	version=$(parsejsoninfo Version)
	description=$(parsejsoninfo Description)
	numvotes=$(parsejsoninfo NumVotes)
	outofdate=$(parsejsoninfo OutOfDate)
	msg $(eval_gettext 'Downloading $PKG PKGBUILD from AUR...')
	wget -q "http://aur.archlinux.org/packages/$PKG/$PKG.tar.gz" || { error $(eval_gettext '$PKG not found in AUR.'); return 1; }
	tar xfvz "$PKG.tar.gz" > /dev/null || return 1
	cd "$PKG/"
	aurcomments $aurid
	echo -e "${COL_BOLD}${PKG} ${version} ${NO_COLOR}: ${description}"
	echo -e "${COL_BOLD}${COL_BLINK}${COL_RED}"$(eval_gettext '( Unsupported package: Potentally dangerous ! )')"${NO_COLOR}"

	# Customise PKGBUILD
	[ $CUSTOMIZEPKGINSTALLED -eq 1 ] && customizepkg --modify
	##### / Download tarball for unsupported

	# Edit PKGBUILD, then read PKGBUILD to find deps
	if [ $EDITPKGBUILD -eq 0 ]; then
		find_pkgbuild_deps || return 1
	fi
	edit=1
	loop=0
	while [ $EDITPKGBUILD -eq 1 -a $edit -eq 1 ]; do
		edit=0
		prompt $(eval_gettext 'Edit the PKGBUILD (highly recommended for security reasons) ? ')$(yes_no 1)$(eval_gettext '("A" to abort)')
		EDIT_PKGBUILD=$(userinput "YNA")
		echo
		if [ "$EDIT_PKGBUILD" = "A" ]; then
			echo $(eval_gettext 'Aborted...')
			return 1
		elif [ "$EDIT_PKGBUILD" != "N" ]; then
			edit=1
			edit_file ./PKGBUILD
		fi
		if [ $loop -lt 1 -o $edit -eq 1 ]; then
		       	find_pkgbuild_deps || return 1
		fi
		(( loop ++))
	done
	
	# if install variable is set in PKGBUILD, propose to edit file(s)
	edit=1
	while [ -f "${install[0]}" -a $EDITPKGBUILD -eq 1 -a $edit -eq 1 ]; do
		echo 
		warning $(eval_gettext 'This PKGBUILD contains install file that can be dangerous.')
		for installfile in ${install[@]}; do
			edit=0
			list $installfile
			prompt $(eval_gettext 'Edit $installfile (highly recommended for security reasons) ? ')$(yes_no 1) $(eval_gettext '("A" to abort)')
			EDIT_INSTALLFILE=$(userinput "YNA")
			echo
			if [ "$EDIT_INSTALLFILE" = "A" ]; then
				echo $(eval_gettext 'Aborted...')
				return 1
			elif [ "$EDIT_INSTALLFILE" != "N" ]; then
				edit=1
			fi
			if [ $edit -eq 1 ]; then
				edit_file $installfile
			fi
		done
	done

	if [ $NOCONFIRM -eq 0 ]; then
		prompt $(eval_gettext 'Continue the building of $PKG ? ')$(yes_no 1)
		if [ "`userinput`" = "N" ]; then
			return 0
		fi
	fi

	echo
	# install new dependencies from AUR
	if [ ${#DEP_AUR[@]} -gt 0 ]; then
		msg $(eval_gettext 'Building missing dependencies from AUR:')
		local depindex=0
		for newdep in ${DEP_AUR[@]}; do
			echo $BUILDPROGRAM --asdeps "$newdep"
			read
			$BUILDPROGRAM --asdeps "$newdep"
			if `isinstalled $newdep`; then
				failed=0
			else
				failed=1
			fi

			# remove dependencies if failed 
			if [ $failed -eq 1 ]; then
				if [ $depindex -gt 0 ]; then
					warning $(eval_gettext 'Dependencies have been installed before the failure')
					$YAOURTCOMMAND -Rcsn "${DEP_AUR[@]:0:$depindex}"
					plain $(eval_gettext 'press a key to continue')
					read
				fi
				break
			fi
			(( depindex ++ ))
		done
	fi
	echo

	# if dep's building not failed; search for sourceforge mirror
	[ $failed -ne 1 ] && sourceforge_mirror_hack

	# compil PKGBUILD if dep's building not failed
	[ $failed -ne 1 ] && build_package
	retval=$?
	if [ $retval -eq 1 ]; then
		manage_error 1 || return 1
	elif [ $retval -eq 90 ]; then
		return 0
	fi

	# Install, export, copy package after build 
	[ $failed -ne 1 ] && install_package

	# Check if this package has been voted on AUR, and vote for it
	if [ $AURVOTE -eq 1 ]; then
		vote_package "$pkgname" "$aurid"
	fi

	#msg "Delete $wdir"
	rm -rf "$wdir" || warning $(eval_gettext 'Unable to delete directory $wdir.')
	cleanoutput
	echo
	return $failed
}

upgrade_from_aur(){
	title $(eval_gettext 'upgrading AUR unsupported packages')
	tmp_files="$YAOURTTMPDIR/search/"
	mkdir -p $tmp_files
	loadlibrary pacman_conf
	create_ignorepkg_list || error $(eval_gettext 'list ignorepkg in pacman.conf')
	# Search for new version on AUR
	local iNum=0
	msg $(eval_gettext 'Searching for new version on AUR')
	for PKG in $(pacman -Qqm)
	do
		echo -n "$PKG: "
		initjsoninfo $PKG || { echo -e "${COL_YELLOW}"$(eval_gettext 'not found on AUR')"${NO_COLOR}"; continue; }
		local_version=`pkgversion $PKG`
		aur_version=`parsejsoninfo Version`
		if `is_x_gt_y $aur_version $local_version`; then
			echo -en "${COL_GREEN}${local_version} => ${aur_version}${NO_COLOR}"
			if grep "^${PKG}$" $tmp_files/ignorelist > /dev/null; then
				echo -e "${COL_RED} "$(eval_gettext '(ignoring package upgrade)')"${NO_COLOR}"
			else
				echo 
				aur_package[$iNum]=$PKG
				(( iNum ++ ))
			fi
		elif [ $local_version != $aur_version ]; then
			echo -e " (${COL_RED}local=$local_version ${NO_COLOR}aur=$aur_version)"
		else
			if [ `parsejsoninfo "OutOfDate"` -eq 1 ]; then
				echo -e $(eval_gettext "up to date ")"${COL_RED}($local_version "$(eval_gettext 'flagged as out of date')")${NO_COLOR}"
			else
				echo $(eval_gettext 'up to date ')
			fi
		fi
	done
	cleanoutput

	[ $iNum -lt 1 ] && return 0

	# upgrade yaourt first
	for package in ${aur_package[@]}; do
		if [ "$package" = "yaourt" ]; then
			warning $(eval_gettext 'New version of $package detected')
			prompt $(eval_gettext 'Do you want to update $package first ? ')$(yes_no 1)
			[ "`userinput`" = "N" ] && break
			echo
			msg $(eval_gettext 'Upgrading $package first')
			install_from_aur "$package" || error $(eval_gettext 'unable to update $package')
			die 0
		fi
	done

	plain "\n---------------------------------------------"
	plain $(eval_gettext 'Packages that can be updated from AUR:')
	echo "${aur_package[*]}"
	if [ $NOCONFIRM -eq 0 ]; then
		prompt $(eval_gettext 'Do you want to update these packages ? ')$(yes_no 1)
		[ "`userinput`" = "N" ] && return 0
		echo
	fi
	for PKG in ${aur_package[@]}; do
		install_from_aur "$PKG" || error $(eval_gettext 'unable to update $PKG')
	done
	cleanoutput
}
find_pkgbuild_deps (){
	unset DEPS DEP_AUR
	readPKGBUILD
	if [ -z "$pkgname" ]; then
		echo $(eval_gettext 'Unable to read PKGBUILD for $PKG')
		return 1
	fi
	for dep in $(echo "${depends[@]} ${makedepends[@]}" | tr -d '\\')
	do
		DEPS[${#DEPS[@]}]=$(echo $dep | sed 's/=.*//' \
		| sed 's/>.*//' \
		| sed 's/<.*//')
	done
	[ ${#DEPS[@]} -eq 0 ] && return 0

	echo
	msg "$(eval_gettext '$PKG dependencies:')"
	DEP_PACMAN=0

	for dep in ${DEPS[@]}; do
		if isinstalled $dep; then echo -e " - ${COL_BOLD}$dep${NO_COLOR}" $(eval_gettext '(already installed)'); continue; fi
		if isprovided $dep; then echo -e " - ${COL_BOLD}$dep${NO_COLOR}" $(eval_gettext '(package that provides ${dep} already installed)'); continue; fi
		if isavailable $dep; then echo -e " - ${COL_BLUE}$dep${NO_COLOR}" $(eval_gettext '(package found)'); DEP_PACMAN=1; continue; fi
		echo -e " - ${COL_YELLOW}$dep${NO_COLOR}" $(eval_gettext '(building from AUR)') 
		DEP_AUR[${#DEP_AUR[@]}]=$dep 
	done

}

