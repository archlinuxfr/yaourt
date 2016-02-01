#!/bin/bash
#
# misc.sh : Some misc functions
# This file is part of Yaourt (http://archlinux.fr/yaourt-en)

Y_PKG_ORPHANS="$YAOURTTMPDIR/orphans.$$"
Y_PKG_INSTALLED="$YAOURTTMPDIR/installed.$$"

prepare_status_list() {
	# Prepare orphan & installed lists
	if ((SHOWORPHANS)); then
		pkgquery -Qdtf '%n' --sort n > "$Y_PKG_ORPHANS"
		cleanup_add rm "$Y_PKG_ORPHANS"
	fi
	if ((AUTOSAVEBACKUPFILE)); then
		pkgquery -Qf '%n %v' --sort n > "$Y_PKG_INSTALLED"
		cleanup_add rm "$Y_PKG_INSTALLED"
	fi
}

analyse_status_list() {
	if ((SHOWORPHANS)); then
		local neworphans
		neworphans=$(LC_ALL=C comm -13 "$Y_PKG_ORPHANS" <(pkgquery -Qdtf '%n' --sort n))
		# show new orphans
		if [[ "$neworphans" ]]; then
			neworphans=$(echo $neworphans)
			msg "$(gettext 'Packages no longer required by any installed package:')"
			echo_wrap 4 "$neworphans"
		fi
	fi
	# Test local database
	((NO_TESTDB)) || $PACMAN -Dk
	if ((AUTOSAVEBACKUPFILE)) && ! \
		diff "$Y_PKG_INSTALLED" <(pkgquery -Qf '%n %v' --sort n) &> /dev/null; then
		# save original of backup files (pacnew/pacsave)
		msg "$(gettext 'Searching for original config files to save')"
		launch_with_su pacdiffviewer --backup -q
	fi
}

# vim: set ts=4 sw=4 noet:
