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

AUR_URL="http://aur.archlinux.org/"
AUR_PKG_URL="$AUR_URL/packages.php?setlang=en&ID="

loadlibrary pkgbuild
# Get sources in current dir
aur_get_pkgbuild ()
{
	[[ $1 ]] || return 1
	local pkg=${1#*/}
	(( $# > 1 )) && local pkgurl=$2 || local pkgurl=$(package-query -Aif "%u" "$pkg")
	if [[ ! "$pkgurl" ]]; then
		error $(eval_gettext '$pkg not found in AUR.');
		return 1;
	fi
	curl -s "$pkgurl" -o "$pkg.tar.gz"
	bsdtar -s "/$pkg//" -xvf "$pkg.tar.gz"
	rm "$pkg.tar.gz"
}

aur_show_info()
{
	echo -n "$(gettext "$1")"; shift; 
	[[ $* ]] && echo ": $*" || echo ": None"
}

# Grab info for package on AUR Unsupported
info_from_aur() {
	title "Searching info on AUR for $1"
	PKG=$1
	local tmpdir=$(mktemp -d --tmpdir="$YAOURTTMPDIR")
	cd $tmpdir
	curl -s -o PKGBUILD "$AUR_URL/packages/$PKG/$PKG/PKGBUILD" || { echo "$PKG not found in repos nor in AUR"; return 1; }
	if (( EDITFILES )); then
		run_editor PKGBUILD 1 
		(( $? == 2 )) && return 0
	fi
	read_pkgbuild || return 1
	eval $PKGBUILD_VARS
	aur_show_info "Repository     " "aur"
	aur_show_info "Name           " $pkgname
	aur_show_info "Version        " $pkgver-$pkgrel
	aur_show_info "URL            " $url
	aur_show_info "Licenses       " ${license[@]}
	aur_show_info "Groups         " ${groups[@]}
	aur_show_info "Provides       " ${provides[@]} 
	aur_show_info "Depends On     " ${depends[@]}
	aur_show_info "Optional Deps  " ${optdepends[@]}
	aur_show_info "Conflicts With " ${conflicts[@]}
	aur_show_info "Replaces       " ${replaces[@]}
	aur_show_info "Architecture   " ${arch[@]}
	aur_show_info "Last update    " $(ls -l --time-style="long-iso" PKGBUILD | awk '{print $6" "$7}')
	aur_show_info "Description    " $pkgdesc
	echo
}

# scrap html page to show user's comments
aurcomments(){
	(( ! AURCOMMENT )) && return
	curl -s "${AUR_PKG_URL}$1" | awk '
function striphtml (str)
{
	# strip tags and entities
	gsub (/<\/*[^>]+>/, "", str)
	gsub (/&[^;]+;/, "", str)
	gsub (/^[\t ]+/, "", str)
	return str
}
BEGIN {
	max='$MAXCOMMENTS'
	i=0
	comment=0
}
/<div class="comment-header">/ {
	line="\n'${COL_YELLOW}'"striphtml($0)"'${NO_COLOR}'"
}
/<\/blockquote>/ {
	comment=0
	com[i++]=line
}
{
	if (comment==1)
	{
		str=striphtml($0)
		if (str!="")
		line=line"\n"str
	}
}
/<blockquote class="comment-body">/ {
	comment=1
}
/[ \t]+First Submitted/ {
	first=striphtml($0)
}
END {
	if (i>max) i=max
	for (j=i;j>=0;j--)
		print com[j]
	print "\n"first
}'
}

# Check if this package has been voted on AUR, and vote for it
vote_package(){
	if (( ! AURVOTEINSTALLED )); then
		echo -e "${COL_ITALIQUE}"$(gettext 'If you like this package, please install aurvote\nand vote for its inclusion/keeping in [community]')"${NO_COLOR}"
		return
	fi
	echo
	local _pkg=$1
	msg $(eval_gettext 'Checking vote status for $_pkg')
	local pkgvote=`aurvote --id --check "$1/$2"`
	if [[ "${pkgvote}" = "already voted" ]]; then
		echo $(eval_gettext 'You have already voted for $_pkg inclusion/keeping in [community]')
	elif [[ "$pkgvote" = "not voted" ]]; then
		echo
		prompt "$(eval_gettext 'Do you want to vote for $_pkg inclusion/keeping in [community] ? ')$(yes_no 1)"
		useragrees || return
		aurvote --id --vote "$1/$2"
	else
		echo $pkgvote
	fi
}

# give to user all info to build and install Unsupported package from AUR
install_from_aur(){
	local PKG="$1"
	title $(eval_gettext 'Installing $PKG from AUR')
	wdir="$YAOURTTMPDIR/aur-$PKG"
	if [[ -d "$wdir" ]]; then
		msg $(gettext 'Resuming previous build')
	else
		mkdir -p "$wdir" || { error $(eval_gettext 'Unable to create directory $wdir.'); return 1; }
	fi
	cd "$wdir/"
	aurid=""
	eval $(package-query -Axi "$PKG" -f "aurid=%i;version=%v;numvotes=%w;outofdate=%o;pkgurl=%u;description=\"%d\"")
	[[ "$aurid" ]] || return 1
	
	# grab comments and info from aur page
	echo
	msg $(eval_gettext 'Downloading $PKG PKGBUILD from AUR...')
	[[ -d "$PKG" ]] || mkdir "$PKG" || return 1
	cd "$PKG" && aur_get_pkgbuild "$PKG" "$pkgurl" || return 1
	aurcomments $aurid
	echo -e "${COL_BOLD}${PKG} ${version} ${NO_COLOR}: ${description}"
	echo -e "${COL_BOLD}${COL_BLINK}${COL_RED}"$(gettext '( Unsupported package: Potentally dangerous ! )')"${NO_COLOR}"

	# Customise PKGBUILD
	(( CUSTOMIZEPKGINSTALLED )) && customizepkg --modify

	# Build, install/export
	package_loop 0 || { manage_error 1; return 1; }

	# Check if this package has been voted on AUR, and vote for it
	(( AURVOTE )) && vote_package "$pkgbase" "$aurid"

	#msg "Delete $wdir"
	rm -rf "$wdir" || warning $(eval_gettext 'Unable to delete directory $wdir.')
	cleanoutput
	echo
	return 0
}

upgrade_from_aur(){
	title $(gettext 'upgrading AUR unsupported packages')
	tmp_files="$YAOURTTMPDIR/search/"
	mkdir -p $tmp_files
	loadlibrary pacman_conf
	create_ignorepkg_list 
	# Search for new version on AUR
	msg $(gettext 'Searching for new version on AUR')
	inter_process="$(mktemp)"
	package-query -AQm -f "%n %l %v %o" | while read PKG lver pkgver outofdate
	do
		echo -n "$PKG: "
		[[ "$pkgver" = "-" ]] && \
			{ echo -e "${COL_YELLOW}"$(gettext 'not found on AUR')"${NO_COLOR}"; continue; }
		if  is_x_gt_y "$pkgver" "$lver"; then
			echo -en " ${COL_GREEN}${lver} => ${pkgver}${NO_COLOR}"
			if in_array "$PKG" "${PKGS_IGNORED[@]}"; then
				echo -en " ${COL_RED} "$(gettext '(ignoring package upgrade)')"${NO_COLOR}"
			else
				echo $PKG >> "$inter_process"
			fi
		elif [[ $lver != $pkgver ]]; then
			echo -en " (${COL_RED}local=$lver ${NO_COLOR}aur=$pkgver)"
		else
			echo -n $(gettext 'up to date ')
			(( outofdate )) && echo -en "${COL_RED}($lver "$(gettext 'flagged as out of date')")${NO_COLOR}"
		fi
		echo
	done
	cleanoutput

	aur_package=( $(cat "$inter_process" ) )
	rm "$inter_process"
	[[ $aur_package ]] || return 0
	# upgrade yaourt first
	if [[ " ${aur_package[@]} " =~ " yaourt " ]]; then
		warning $(eval_gettext 'New version of $package detected')
		prompt "$(eval_gettext 'Do you want to update $package first ? ')$(yes_no 1)"
		if useragrees; then
			echo
			msg $(eval_gettext 'Upgrading $package first')
			install_from_aur "$package" || error $(eval_gettext 'unable to update $package')
			die 0
		fi
	fi

	echo; echo_fill "" - ""
	plain $(gettext 'Packages that can be updated from AUR:')
	echo "${aur_package[*]}"
	prompt "$(gettext 'Do you want to update these packages ? ')$(yes_no 1)"
	useragrees || return 0
	echo
	for PKG in ${aur_package[@]}; do
		install_from_aur "$PKG" || error $(eval_gettext 'unable to update $PKG')
	done
	cleanoutput
}


