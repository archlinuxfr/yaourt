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
loadlibrary pkgbuild
# Get sources in current dir
aur_get_pkgbuild ()
{
	[ -z "$1" ] && return 1
	local pkg=${1#*/}
	local pkgurl=${2:-$(package-query -Aif "%u" "$pkg")} 
	if [ -z "$pkgurl" ]; then
		error $(eval_gettext '$pkg not found in AUR.');
		return 1;
	fi
	wget "$pkgurl" -O "$pkg.tar.gz"
	bsdtar -s "/$pkg//" -xvf "$pkg.tar.gz"
	rm "$pkg.tar.gz"
}

# Grab info for package on AUR Unsupported
info_from_aur() {
title "Searching info on AUR for $1"
PKG=$1
tmpdir="$YAOURTTMPDIR/$PKG"
mkdir -p $tmpdir
cd $tmpdir
wget -O PKGBUILD -q http://aur.archlinux.org/packages/$PKG/$PKG/PKGBUILD || { echo "$PKG not found in repos nor in AUR"; return 1; }
run_editor PKGBUILD 1 || return 1
read_pkgbuild || return 1
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

# scrap html page to show user's comments
aurcomments(){
	wget --quiet "${AUR_URL3}$1" -O - \
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
				prompt "$(eval_gettext 'Do you want to vote for $_pkg inclusion/keeping in [community] ? ')$(yes_no 1)"
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
	local PKG="$1"
	title $(eval_gettext 'Installing $PKG from AUR')
	wdir="$YAOURTTMPDIR/aur-$PKG"
	if [ -d "$wdir" ]; then
		msg $(eval_gettext 'Resuming previous build')
	else
		mkdir -p "$wdir" || { error $(eval_gettext 'Unable to create directory $wdir.'); return 1; }
	fi
	cd "$wdir/"
	aurid=""
	eval $(package-query -Aei $PKG -f "aurid=%i;version=%v;numvotes=%w;outofdate=%o;pkgurl=%u;description=\"%d\"")
	[ -z "$aurid" ] && return 1
	
	# grab comments and info from aur page
	echo
	msg $(eval_gettext 'Downloading $PKG PKGBUILD from AUR...')
	[ -d "$PKG" ] || mkdir "$PKG" || return 1
	cd "$PKG" && aur_get_pkgbuild "$PKG" "$PKGURL" || return 1
	aurcomments $aurid
	echo -e "${COL_BOLD}${PKG} ${version} ${NO_COLOR}: ${description}"
	echo -e "${COL_BOLD}${COL_BLINK}${COL_RED}"$(eval_gettext '( Unsupported package: Potentally dangerous ! )')"${NO_COLOR}"

	# Customise PKGBUILD
	[ $CUSTOMIZEPKGINSTALLED -eq 1 ] && customizepkg --modify

	edit_pkgbuild 1 1 || return 1

	if [ $NOCONFIRM -eq 0 ]; then
		prompt "$(eval_gettext 'Continue the building of $PKG ? ')$(yes_no 1)"
		if [ "`userinput`" = "N" ]; then
			return 0
		fi
	fi

	echo

	build_package 
	manage_error $? || return 1
	install_package 
	manage_error $? || return 1

	# Check if this package has been voted on AUR, and vote for it
	[ $AURVOTE -eq 1 ] && vote_package "$pkgname" "$aurid"

	#msg "Delete $wdir"
	rm -rf "$wdir" || warning $(eval_gettext 'Unable to delete directory $wdir.')
	cleanoutput
	echo
	return 0
}

upgrade_from_aur(){
	title $(eval_gettext 'upgrading AUR unsupported packages')
	tmp_files="$YAOURTTMPDIR/search/"
	mkdir -p $tmp_files
	loadlibrary pacman_conf
	create_ignorepkg_list || error $(eval_gettext 'list ignorepkg in pacman.conf')
	# Search for new version on AUR
	msg $(eval_gettext 'Searching for new version on AUR')
	inter_process="$(mktemp)"
	package-query -AQm -f "%n %l %v %o" | while read PKG local_version aur_version outofdate
	do
		echo -n "$PKG: "
		[ "$aur_version" = "-" ] && \
			{ echo -e "${COL_YELLOW}"$(eval_gettext 'not found on AUR')"${NO_COLOR}"; continue; }
		lrel=${local_version#*-}
		rrel=${aur_version#*-}
		lver=${local_version%-*}
		rver=${aur_version%-*}
		if  [ "$rver" = "$lver" ] &&  `is_x_gt_y $rrel $lrel` || `is_x_gt_y $rver $lver`; then
			echo -en "${COL_GREEN}${local_version} => ${aur_version}${NO_COLOR}"
			if grep "^${PKG}$" $tmp_files/ignorelist > /dev/null; then
				echo -e "${COL_RED} "$(eval_gettext '(ignoring package upgrade)')"${NO_COLOR}"
			else
				echo 
				echo $PKG >> "$inter_process"
			fi
		elif [ $local_version != $aur_version ]; then
			echo -e " (${COL_RED}local=$local_version ${NO_COLOR}aur=$aur_version)"
		else
			if [ $outofdate -eq 1 ]; then
				echo -e $(eval_gettext "up to date ")"${COL_RED}($local_version "$(eval_gettext 'flagged as out of date')")${NO_COLOR}"
			else
				echo $(eval_gettext 'up to date ')
			fi
		fi
	done
	cleanoutput

	aur_package=( $(cat "$inter_process" ) )
	rm "$inter_process"
	[ -n "$aur_package" ] || return 0
	# upgrade yaourt first
	for package in  ${aur_package[@]}; do
		if [ "$package" = "yaourt" ]; then
			warning $(eval_gettext 'New version of $package detected')
			prompt "$(eval_gettext 'Do you want to update $package first ? ')$(yes_no 1)"
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
		prompt "$(eval_gettext 'Do you want to update these packages ? ')$(yes_no 1)"
		[ "`userinput`" = "N" ] && return 0
		echo
	fi
	for PKG in ${aur_package[@]}; do
		install_from_aur "$PKG" || error $(eval_gettext 'unable to update $PKG')
	done
	cleanoutput
}


