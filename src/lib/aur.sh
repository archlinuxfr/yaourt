#!/bin/bash
#
# aur.sh : deals with AUR
# This file is part of Yaourt (http://archlinux.fr/yaourt-en)

AUR_PKG_URL="$AURURL/packages/"
AUR_INSTALLED_PKGS=()

load_lib abs
load_lib pkgbuild

# Get sources in current dir
aur_get_pkgbuild() {
	[[ $1 ]] || return 1
	local pkg=${1#*/}
	local pkgurl=$2
	local local_aurusegit=$AURUSEGIT

	if ((AURUSEGIT)) && ! command -v git >/dev/null 2>&1; then
		warning $(_gettext 'AURUSEGIT is set but git command is not found. Falling back to tarballs.')
		local_aurusegit=0
	fi

	if ((local_aurusegit)); then
		local git_repo_url=$(pkgquery -Aif "%G" "$pkg")
		((UPGRADES && AURSHOWDIFF)) || local _depth="--depth=1"
		# We're already in "$pkg"/ here, so clone to the current directory
		git clone $_depth "$git_repo_url" . || return 1
	else
		[[ -z "$pkgurl" ]] && pkgurl=$(pkgquery -Aif "%u" "$pkg")
		if [[ ! "$pkgurl" ]] || ! curl_fetch -fs "$pkgurl" -o "$pkg.tar.gz"; then
			error $(_gettext '%s not found in AUR.' "$pkg");
			return 1;
		fi
		bsdtar --strip-components 1 -xvf "$pkg.tar.gz"
		rm "$pkg.tar.gz"
	fi
}

aur_show_info() {
	local t="$(gettext "$1"): "; shift
	local len=${#t} str=""
	[[ $* ]] && str=("$@") || str="None"
	echo_wrap_next_line "$CBOLD$t$C0" $len "${str[@]}"
}

# Grab info for package on AUR Unsupported
info_from_aur() {
	local pkgname=$1 id votes outofdate maintainer popularity last_mod pkgbuild_url \
		keywords licenses pkgver pkgdesc url
	title "Searching info on AUR for $pkgname"
	IFS='|' read id votes outofdate maintainer last_mod popularity pkgbuild_url \
		keywords licenses pkgver pkgdesc url \
		< <(pkgquery -Aif '%i|%w|%o|%m|%L|%p|%u|%K|%e|%v|%d|%U' "$pkgname")
	((outofdate)) && outofdate="$(gettext Yes)" || outofdate="$(gettext No)"
	local tmpfile=$(mktemp --tmpdir="$YAOURTTMPDIR")
	local pkgbase=${pkgbuild_url#*/snapshot/}; pkgbase=${pkgbase%.tar.gz}
	pkgbuild_url="${pkgbuild_url%/snapshot/*}/plain/PKGBUILD?h=$pkgbase"
	curl_fetch -fis "$pkgbuild_url" -o "$tmpfile" || \
		{ error $(_gettext '%s not found in AUR.' "$pkgname"); return 1; }
	local vars=(arch groups depends depends_$CARCH optdepends optdepends_$CARCH
		provides provides_$CARCH conflicts conflicts_$CARCH replaces replaces_$CARCH)

	unset ${vars[*]}
	local ${vars[*]}
	. <( source_pkgbuild "$tmpfile" ${vars[*]} )
	merge_arch_attrs

	aur_show_info "Repository     " "${C[aur]:-${C[other]}}aur$C0"
	aur_show_info "Name           " "$CBOLD$pkgname$C0"
	[[ $pkgname != $pkgbase ]] && {
	aur_show_info "Base Package   " "$pkgbase"; }
	aur_show_info "Version        " "$CGREEN$pkgver$C0"
	aur_show_info "Description    " "$pkgdesc"
	aur_show_info "Architecture   " "${arch[*]}"
	aur_show_info "URL            " "$CCYAN$url$C0"
	aur_show_info "AUR URL        " "$CCYAN${AURURL}/packages/$pkgname$C0"
	[[ "$keywords" != "-" ]] && {
	aur_show_info "Keywords       " "${keywords[*]}"; }
	aur_show_info "Licenses       " "${licenses[*]}"
	aur_show_info "Groups         " "${groups[*]}"
	aur_show_info "Provides       " "${provides[*]}"
	aur_show_info "Depends On     " "${depends[*]}"
	aur_show_info "Optional Deps  " "${optdepends[@]}"
	aur_show_info "Conflicts With " "${conflicts[*]}"
	aur_show_info "Replaces       " "${replaces[*]}"
	aur_show_info "Maintainer     " "$maintainer"
	aur_show_info "Last update    " "$(date +"%c" --date "@$last_mod")"
	aur_show_info "Out Of Date    " "$outofdate"
	aur_show_info "Votes          " "$votes"
	aur_show_info "Popularity     " "$popularity"
	echo
	rm "$tmpfile"
}

# scrap html page to show user's comments
aur_comments() {
	(( ! AURCOMMENT )) && return
	curl_fetch -s "${AUR_PKG_URL}$1" | awk '
function striphtml (str)
{
	# strip tags and entities
	gsub (/<\/*[^>]+>/, "", str)
	gsub (/&quot;/, "\"", str)
	gsub (/&[^;]+;/, "", str)
	gsub (/^[\t ]+/, "", str)
	gsub (/[\t ]+$/, "", str)
	return str
}
BEGIN {
	max='$AURCOMMENT'
	i=0
	comment=0
	comment_content=0
	div_news=0
}
{
	if (comment_content==1)
	{
		str=striphtml($0)
		if (str!="")
			line=line"\n"str
	}
}
/^[\t ]*<p>$/ {
	if (comment==1) {
		comment_content=1
	}
}
/^[\t ]*<\/div>$/ {
	if (comment==1) {
		comment=0
		comment_content=0
		com[i++]=line
	}
}
/^[\t ]*<h4 id="comment-/ {
	comment=1
	getline
	sub("^[\t ]*","")
	line="'$CYELLOW'"$0"'$C0' "
}
/^<div id="news">$/ {
	div_news=!div_news;
}
END {
	if (i>max) i=max
	for (j=i-1;j>=0;j--)
		print com[j]"\n"
}'
}

# Display PKGBUILD changes between installed version and AUR version.
# For devel packages compare the last two revisions as a fallback.
aur_git_diff() {
	local lrev rev

	# Search git revision matching the local version of the package
	while read rev; do
		git grep -F -q --all-match -e "pkgver = ${pkginfo[7]%-*}" -e "pkgrel = ${pkginfo[7]#*-}" $rev -- .SRCINFO
		[[ $? -eq 0 ]] && { lrev=$rev; break; }
	done < <(git rev-list HEAD -- .SRCINFO)

	echo
	git diff ${lrev:-HEAD^}..HEAD -- PKGBUILD
	echo
}

# Check if this package has been voted on AUR, and vote for it
vote_package() {
	(( ! AURVOTEINSTALLED )) && return
	echo
	msg $(_gettext 'Checking vote status for %s' "$1")
	local pkgvote=$(aurvote --check "$1")
	if [[ "${pkgvote}" = "already voted" ]]; then
		echo "$(_gettext 'You have already voted for %s' "$1")"
	elif [[ "$pkgvote" = "not voted" ]]; then
		echo
		prompt "$(_gettext 'Do you want to vote for %s ? ' "$1")$(yes_no 1)"
		useragrees || return
		aurvote --vote "$1"
	else
		echo $pkgvote
	fi
}

# give to user all info to build and install Unsupported package from AUR
install_from_aur() {
	local cwd
	declare -a pkginfo=($(pkgquery -1Aif "%n %i %v %w %o %u %m %l %L" "$1"))
	[[ "${pkginfo[1]#-}" ]] || return 1
	in_array ${pkginfo[0]} "${AUR_INSTALLED_PKGS[@]}" && return 0
	title $(_gettext 'Installing %s from AUR' "${pkginfo[0]}")
	cwd=$PWD
	init_build_dir "$YAOURTTMPDIR/aur-${pkginfo[0]}" || return 1
	echo
	msg $(_gettext 'Downloading %s PKGBUILD from AUR...' "${pkginfo[0]}")
	aur_get_pkgbuild "${pkginfo[0]}" "${pkginfo[5]}" ||
	  { cd "$cwd"; return 1; }
	aur_comments ${pkginfo[0]}
	echo -e "$CBOLD${pkginfo[0]} ${pkginfo[2]} $C0 ($(date -u -d "@${pkginfo[8]}" "+%F %H:%M"))"
	((UPGRADES && AURUSEGIT && AURSHOWDIFF)) && aur_git_diff
	[[ ! ${pkginfo[6]#-} ]] && echo -e "$CBLINK$CRED$(gettext 'This package is orphaned')$C0"
	echo -e "$CBLINK$CRED$(gettext '( Unsupported package: Potentially dangerous ! )')$C0"

	# Build, install/export
	package_loop ${pkginfo[0]} 0 || manage_error ${pkginfo[0]} ||
	  { cd "$cwd"; return 1; }
	cd "$cwd"
	rm -rf "$YAOURTTMPDIR/aur-${pkginfo[0]}"

	if ((AURVOTE)) && [[ ! "${pkginfo[7]#-}" ]]; then
		# Check if this package has been voted on AUR, and vote for it
		vote_package "${pkginfo[0]}"
	fi
	AUR_INSTALLED_PKGS+=("${pkginfo[0]}")
	return 0
}

# aur_update_exists ($pkgname,$version,$localversion,$outofdate,$maintainer)
aur_update_exists() {
	local ret=0
	local _msg=""
	if [[ ! ${2#-} ]]; then
		((DETAILUPGRADE & 6 )) && _msg+=" $CYELLOW$(gettext 'not found on AUR')$C0"
		ret=1
	elif is_x_gt_y "$3" "$2"; then
		((DETAILUPGRADE & 6 )) && _msg+=" (${CRED}local=$3 ${C0}aur=$2)"
		ret=1
	elif [[ "$2" = "$3" ]]; then
		((DETAILUPGRADE & 2)) || ((DETAILUPGRADE & 4 && ${4#-} )) && {
			_msg+=" $(gettext 'up to date ')"
			(( outofdate )) && _msg+=" $CRED($2 "$(gettext 'flagged as out of date')")$C0"
		}
		ret=1
	fi
	if [[ ! ${5#-} ]]; then
		if ((DETAILUPGRADE<2)); then
			tput el1
			echo -en "$prefix"
		fi
		_msg=" $CRED$(gettext 'Orphan')$C0 $_msg"
	fi
	[[ $_msg ]] && echo -e "${REFRESH:+ }$1 :$_msg"
	((ret)) && return $ret
	is_package_ignored "$1" $DETAILUPGRADE && return 1
	return 0
}

# vim: set ts=4 sw=4 noet:
