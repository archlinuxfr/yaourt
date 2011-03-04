#!/bin/bash
#
# aur.sh : deals with AUR
# This file is part of Yaourt (http://archlinux.fr/yaourt-en)

AUR_URL="https://aur.archlinux.org/"
AUR_PKG_URL="$AUR_URL/packages.php?setlang=en&ID="

loadlibrary abs
loadlibrary pkgbuild
# Get sources in current dir
aur_get_pkgbuild ()
{
	[[ $1 ]] || return 1
	local pkg=${1#*/}
	#(( $# > 1 )) && local pkgurl=$2 || \
	#local pkgurl=$(pkgquery -Aif "%u" "$pkg")
	local pkgurl="$AUR_URL/packages/$pkg/$pkg.tar.gz"
	if [[ ! "$pkgurl" ]] || ! curl -fs "$pkgurl" -o "$pkg.tar.gz"; then
		error $(eval_gettext '$pkg not found in AUR.');
		return 1;
	fi
	bsdtar --strip-components 1 -xvf "$pkg.tar.gz"
	rm "$pkg.tar.gz"
}

aur_show_info()
{
	local t="$(gettext "$1"): "; shift
	local len=${#t} str=""
	[[ $* ]] && str=("$@") || str="None"
	echo_wrap_next_line "$CBOLD$t$C0" $len "${str[@]}"
}

# Grab info for package on AUR Unsupported
info_from_aur() {
	title "Searching info on AUR for $1"
	PKG=$1
	read id votes outofdate < <(pkgquery -Aif '%i %w %o' "$PKG")
	((outofdate)) && outofdate="$(gettext Yes)" || outofdate="$(gettext No)"
	local tmpfile=$(mktemp --tmpdir="$YAOURTTMPDIR")
	curl -fis "$AUR_URL/packages/$PKG/PKGBUILD" -o "$tmpfile" || \
		{ error "$PKG not found in repos nor in AUR"; return 1; }
	sanitize_pkgbuild "$tmpfile" 
	unset pkgname pkgver pkgrel url license groups provides depends optdepends \
		conflicts replaces arch last_mod pkgdesc
	source "$tmpfile"
	aur_show_info "Repository     " "${colors[aur]:-${colors[other]}}aur$C0"
	aur_show_info "Name           " "$CBOLD$pkgname$C0"
	aur_show_info "Version        " "$CGREEN$pkgver-$pkgrel$C0"
	aur_show_info "URL            " "$CCYAN$url$C0"
	aur_show_info "AUR URL        " "$CCYAN${AUR_URL}packages.php?ID=$id$C0"
	aur_show_info "Licenses       " "${license[*]}"
	aur_show_info "Votes          " "$votes"
	aur_show_info "Out Of Date    " "$outofdate"
	aur_show_info "Groups         " "${groups[*]}"
	aur_show_info "Provides       " "${provides[*]}"
	aur_show_info "Depends On     " "${depends[*]}"
	aur_show_info "Optional Deps  " "${optdepends[@]}"
	aur_show_info "Conflicts With " "${conflicts[*]}"
	aur_show_info "Replaces       " "${replaces[*]}"
	aur_show_info "Architecture   " "${arch[*]}"
	aur_show_info "Last update    " "$(date +"%c" --date "$last_mod")"
	aur_show_info "Description    " "$pkgdesc"
	echo
	rm "$tmpfile" 
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
	max='$AURCOMMENT'
	i=0
	comment=0
}
/<div class="comment-header">/ {
	line="\n'$CYELLOW'"striphtml($0)"'$C0'"
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
	(( ! AURVOTEINSTALLED )) && return
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
	local PKG="${1#*/}"
	title $(eval_gettext 'Installing $PKG from AUR')
	init_build_dir "$YAOURTTMPDIR/aur-$PKG" || return 1
	aurid=""

	read aurid version numvotes outofdate pkgurl description < \
		<(pkgquery -Ai "$PKG" -f "%i %v %w %o %u %d")
	[[ "${aurid#-}" ]] || return 1
	
	# grab comments and info from aur page
	echo
	msg $(eval_gettext 'Downloading $PKG PKGBUILD from AUR...')
	aur_get_pkgbuild "$PKG" "$pkgurl" || return 1
	aurcomments $aurid
	echo -e "$CBOLD$PKG $version $C0: $description"
	echo -e "$CBLINK$CRED"$(gettext '( Unsupported package: Potentially dangerous ! )')"$C0"

	# Build, install/export
	package_loop 0 || { manage_error 1; return 1; }
	rm -rf "$YAOURTTMPDIR/aur-$PKG"

	# Check if this package has been voted on AUR, and vote for it
	(( AURVOTE )) && vote_package "$pkgbase" "$aurid"
	return 0
}

# aur_update_exists ($pkgname,$version,$localversion,outofdate)
aur_update_exists()
{
	if [[ ! ${2#-} ]]; then
		((DETAILUPGRADE>1)) && echo -e "$1: $CYELLOW"$(gettext 'not found on AUR')"$C0"
		return 1
	elif is_x_gt_y "$3" "$2"; then
		((DETAILUPGRADE>1)) && echo -e "$1: (${CRED}local=$3 ${C0}aur=$2)"
		return 1
	elif [[ "$2" = "$3" ]]; then
		((DETAILUPGRADE>1)) && {
			echo -en "$1: $(gettext 'up to date ')"
			(( outofdate )) && echo -e "$CRED($2 "$(gettext 'flagged as out of date')")$C0" || echo
		}
		return 1
	fi
	is_package_ignored "$1" $DETAILUPGRADE && return 1
	return 0
}

# vim: set ts=4 sw=4 noet: 
