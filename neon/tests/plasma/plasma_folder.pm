# Copyright (C) 2016-2018 Harald Sitter <sitter@kde.org>
#
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License as
# published by the Free Software Foundation; either version 2 of
# the License or (at your option) version 3 or any later version
# accepted by the membership of KDE e.V. (or its successor approved
# by the membership of KDE e.V.), which shall act as a proxy
# defined in Section 14 of version 3 of the license.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <http://www.gnu.org/licenses/>.

use base "basetest_neon";
use strict;
use testapi;

sub run {
    my ($self) = @_;
    $self->boot;
    # We are now logged in...

    # wait for the desktop to appear
    # Technically we'd want to make sure the desktop appears in under 30s but
    # since we can't make sure that is in fact the baseline we can't really do
    # that :/
    # >30s would be indicative of a dbus timeout.
    assert_screen 'folder-desktop', 30;

    # 5.12 is the last version to have standard icons on desktop. So, only check
    # for them there.
    if (match_has_tag('folder-desktop-512')) {
        assert_and_click "home-icon";

        assert_screen 'dolphin', 10;
        send_key 'alt-f4';
        assert_screen 'folder-desktop', 8;
    }

    # While unstable installs are still on older plasmas this can be a soft
    # failure, should become hard in April 2018 if I remember.
    if (get_var('TYPE') eq 'unstable' && match_has_tag('folder-desktop-512')) {
        record_soft_failure "Screen had Plasma 5.12 icons but unstable should't have them!"
    }

    assert_screen 'folder-desktop';
    if (!check_screen('folder-desktop-color', 4)) {
        # TODO: drop once all images have been rotated (~mid Sept 2018)
        record_soft_failure 'Testing an old disk image without static wallpaper';
        mouse_set 400, 300;
        mouse_click 'right';
        assert_and_click 'plasma-context-config-folder';
        assert_and_click 'plasma-folder-config-background';
        assert_and_click 'plasma-folder-config-background-color';
        # Should the deafault ever become undesirable: #1d99f3 is the lovely color.
        assert_and_click 'kcm-ok';
    }
    # Should now be lovely blue.
    assert_screen 'folder-desktop-color';
}

sub test_flags {
    # without anything - rollback to 'lastgood' snapshot if failed
    # 'fatal' - whole test suite is in danger if this fails
    # 'milestone' - after this test succeeds, update 'lastgood'
    # 'important' - if this fails, set the overall state to 'fail'
    return { important => 1 };
}

1;
