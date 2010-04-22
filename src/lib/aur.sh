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

loadlibrary abs
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
	local t="$(gettext "$1"): "; shift
	local len=${#t} str=""
	[[ $* ]] && str=("$@") || str="None"
	echo_wrap_next_line "${COL_BOLD}$t${NO_COLOR}" $len "${str[@]}"
}

# Grab info for package on AUR Unsupported
info_from_aur() {
	title "Searching info on AUR for $1"
	PKG=$1
	local tmpfile=$(mktemp --tmpdir="$YAOURTTMPDIR")
	(
	set -e
	curl -is "$AUR_URL/packages/$PKG/$PKG/PKGBUILD" -o "$tmpfile"
	sed -in -e '/\$(/d' -e '/`/d' -e '/[><](/d' -e '/[&|]/d' \
		-e '/^ *[a-zA-Z0-9_]\+=(.*) *\(#.*\|$\)/{p;d}' \
		-e '/^ *[a-zA-Z0-9_]\+=(.*$/,/.*) *\(#.*\|$\)/{p;d}' \
		-e '/^ *[a-zA-Z0-9_]\+=.*\\$/,/.*[^\\]$/p' \
		-e '/^ *[a-zA-Z0-9_]\+=.*[^\\]$/p' \
		-e '1,/^\r$/ { s/Last-Modified: \(.*\)\r/last_mod="\1"/p }' \
		-e 'd' "$tmpfile" 
	) || { echo "$PKG not found in repos nor in AUR"; return 1; }
	unset pkgname pkgver pkgrel url license groups provides depends optdepends \
		conflicts replaces arch last_mod pkgdesc
	source "$tmpfile"
	shopt -s extglob
	aur_show_info "Repository     " "${COL_REPOS[aur]}aur${NO_COLOR}"
	aur_show_info "Name           " "${COL_BOLD}$pkgname${NO_COLOR}"
	aur_show_info "Version        " "${COL_GREEN}$pkgver-$pkgrel${NO_COLOR}"
	aur_show_info "URL            " "${COL_CYAN}$url${NO_COLOR}"
	aur_show_info "Licenses       " "${license[*]}"
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

	read aurid version numvotes outofdate pkgurl description < <(package-query -Ai "$PKG" -f "%i %v %w %o %u %d")
	[[ "${aurid#-}" ]] || return 1
	
	# grab comments and info from aur page
	echo
	msg $(eval_gettext 'Downloading $PKG PKGBUILD from AUR...')
	[[ -d "$PKG" ]] || mkdir "$PKG" || return 1
	cd "$PKG" && aur_get_pkgbuild "$PKG" "$pkgurl" || return 1
	aurcomments $aurid
	echo -e "${COL_BOLD}${PKG} ${version} ${NO_COLOR}: ${description}"
	echo -e "${COL_BOLD}${COL_BLINK}${COL_RED}"$(gettext '( Unsupported package: Potentally dangerous ! )')"${NO_COLOR}"

	# Customise PKGBUILD
	custom_pkg "$PKG" && customizepkg --modify

	# Build, install/export
	package_loop 0 || { manage_error 1; return 1; }

	# Check if this package has been voted on AUR, and vote for it
	(( AURVOTE )) && vote_package "$pkgbase" "$aurid"

	#msg "Delete $wdir"
	rm -rf "$wdir" || warning $(eval_gettext 'Unable to delete directory $wdir.')
	echo
	return 0
}

upgrade_from_aur(){
	title $(gettext 'upgrading AUR unsupported packages')
	msg $(gettext 'Searching for new version on AUR')
	loadlibrary pacman_conf
	parse_pacman_conf
	# Search for new version on AUR
	classify_pkg < <(package-query -AQmf '%n %r %v %l %o %d')
	sync_first "${syncfirstpkgs[@]}"
	pkgs+=("${srcpkgs[@]}")
	[[ $pkgs ]] || return 0
	display_update && for PKG in ${pkgs[@]}; do
		install_from_aur "$PKG" || error $(eval_gettext 'unable to update $PKG')
	done
}


