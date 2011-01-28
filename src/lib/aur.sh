#!/bin/bash
#
# aur.sh : deals with AUR
# This file is part of Yaourt (http://archlinux.fr/yaourt-en)

AUR_PKG_URL="$AURURL/packages.php?setlang=en&ID="

loadlibrary abs
loadlibrary pkgbuild
# Get sources in current dir
aur_get_pkgbuild ()
{
	[[ $1 ]] || return 1
	local pkg=${1#*/}
	#(( $# > 1 )) && local pkgurl=$2 || \
	#local pkgurl=$(pkgquery -Aif "%u" "$pkg")
	local pkgurl="$AURURL/packages/$pkg/$pkg.tar.gz"
	if [[ ! "$pkgurl" ]] || ! curl_fetch -fs "$pkgurl" -o "$pkg.tar.gz"; then
		error $(_gettext '%s not found in AUR.' "$pkg");
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
	local pkgname=$1 id votes outofdate
	title "Searching info on AUR for $pkgname"
	read id votes outofdate < <(pkgquery -Aif '%i %w %o' "$pkgname")
	((outofdate)) && outofdate="$(gettext Yes)" || outofdate="$(gettext No)"
	local tmpfile=$(mktemp --tmpdir="$YAOURTTMPDIR")
	curl_fetch -fis "$AURURL/packages/$pkgname/$pkgname/PKGBUILD" -o "$tmpfile" || \
		{ error $(_gettext '%s not found in AUR.' "$pkgname"); return 1; }
	local vars=(pkgname pkgver pkgrel url license groups provides depends optdepends \
		conflicts replaces arch last_mod pkgdesc)
	unset ${vars[*]}
	. <( source_pkgbuild "$tmpfile" ${vars[*]} )
	aur_show_info "Repository     " "${C[aur]:-${C[other]}}aur$C0"
	aur_show_info "Name           " "$CBOLD$pkgname$C0"
	aur_show_info "Version        " "$CGREEN$pkgver-$pkgrel$C0"
	aur_show_info "URL            " "$CCYAN$url$C0"
	aur_show_info "AUR URL        " "$CCYAN${AURURL}/packages.php?ID=$id$C0"
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
	curl_fetch -s "${AUR_PKG_URL}$1" | awk '
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
	msg $(_gettext 'Checking vote status for %s' "$1")
	local pkgvote=`aurvote --id --check "$1/$2"`
	if [[ "${pkgvote}" = "already voted" ]]; then
		echo $(_gettext 'You have already voted for %s inclusion/keeping in [community]' "$1")
	elif [[ "$pkgvote" = "not voted" ]]; then
		echo
		prompt "$(_gettext 'Do you want to vote for %s inclusion/keeping in [community] ? ' "$1")$(yes_no 1)"
		useragrees || return
		aurvote --id --vote "$1/$2"
	else
		echo $pkgvote
	fi
}

# give to user all info to build and install Unsupported package from AUR
install_from_aur(){
	local pkgname="${1#*/}" aurid version numvotes outofdate pkgurl description
	title $(_gettext 'Installing %s from AUR' "$pkgname")
	init_build_dir "$YAOURTTMPDIR/aur-$pkgname" || return 1

	read aurid version numvotes outofdate pkgurl description < \
	  <(pkgquery -Ai "$pkgname" -f "%i %v %w %o %u %d")
	[[ "${aurid#-}" ]] || return 1
	
	# grab comments and info from aur page
	echo
	msg $(_gettext 'Downloading %s PKGBUILD from AUR...' "$pkgname")
	aur_get_pkgbuild "$pkgname" "$pkgurl" || return 1
	aurcomments $aurid
	local len="$pkgname $version : "
	echo_wrap_next_line "$CBOLD$pkgname $version $C0: " ${#len} "$description"
	echo -e "$CBLINK$CRED"$(gettext '( Unsupported package: Potentially dangerous ! )')"$C0"

	# Build, install/export
	package_loop 0 || manage_error $pkgname || return 1
	rm -rf "$YAOURTTMPDIR/aur-$pkgname"

	# Check if this package has been voted on AUR, and vote for it
	(( AURVOTE )) && vote_package "$pkgname" "$aurid"
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
