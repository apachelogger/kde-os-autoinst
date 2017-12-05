# Copyright (C) 2017 Harald Sitter <sitter@kde.org>
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

use base "basetest";
use testapi;

# Core test to run for all install cases. Asserts common stuff.
sub run {
    assert_screen "grub", 30;
    send_key 'ret'; # start first entry

    # Eventually we should end up in sddm
    assert_screen "sddm", 120;

    select_console 'log-console';

    assert_script_run 'wget ' . data_url('enable_qdebug.rb'),  16;
    assert_script_run 'ruby enable_qdebug.rb', 16;

    # Should probably be put in a script that globs all snapd*timer
    script_sudo 'systemctl disable --now snapd.refresh.timer';
    script_sudo 'systemctl disable --now snapd.refresh.service';
    script_sudo 'systemctl disable --now snapd.snap-repair.timer';
    script_sudo 'systemctl disable --now snapd.service';

    assert_script_sudo 'sync';

    script_sudo 'shutdown now';
    assert_shutdown;
}

sub test_flags {
    # without anything - rollback to 'lastgood' snapshot if failed
    # 'fatal' - whole test suite is in danger if this fails
    # 'milestone' - after this test succeeds, update 'lastgood'
    # 'important' - if this fails, set the overall state to 'fail'
    return { milestone => 1 };
}

1;
