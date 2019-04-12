# Copyright (C) 2016-2017 Harald Sitter <sitter@kde.org>
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

use base "livetest_neon";
use strict;
use testapi;

my $user = $testapi::username;
my $password = $testapi::password;

sub assert_keyboard_page {
    assert_screen 'installer-keyboard', 16;

    # On bionic the keyboard is by default !english when installing !english,
    # this is a problem because we need english keyboard maps to do input
    # via openqa. So, once we've asserted the default keyboard page, change it
    # to use english instead.
    if (match_has_tag('installer-keyboard-espanol')) {
        # Open the combobox
        assert_and_click 'installer-keyboard';
        # Jump close to english (ingles).
        type_string 'in';
        # At the time of writing there is a
        # crasher when selecting certain english variants, so we can't just
        # type this out. We'll move arrow down from 'in' until we have found
        # en_US.
        my $counter = 20;
        while (!check_screen('installer-keyboard-select-en-us', 1)) {
            if (!$counter--) {
                last;
            }
            send_key 'down';
            sleep 1;
        }
        assert_and_click 'installer-keyboard-select-en-us';
    }

    # Make sure we've now ended up with the standard en-us keyboard setup.
    assert_screen 'installer-keyboard-en-us', 2;
    assert_and_click 'installer-next';
}

# Prepares live session for install. This expects a newly booted system.
sub prepare {
    my ($self) = shift;

    select_console 'log-console';
    {
        assert_script_run 'wget ' . data_url('geoip_service.rb'),  16;
        script_sudo 'systemd-run ruby `pwd`/geoip_service.rb', 16;
    }
    select_console 'x11';

    $self->maybe_switch_offline;
}

# Runs an install.
# @param disk_empty whether the disk is empty (when not empty it will be wiped)
sub install {
    my ($self, %args) = @_;
    $args{disk_empty} //= 1;

    # Installer
    assert_and_click "installer-icon";
    assert_screen "installer-welcome", 60;
    if (get_var('OPENQA_INSTALLATION_NONENGLISH')) {
        assert_and_click 'installer-welcome-click';
        send_key 'down';
        send_key 'ret';
        assert_screen 'installer-welcome-espanol';
    }
    assert_and_click "installer-next";

    assert_keyboard_page;

    assert_screen "installer-prepare", 16;
    assert_and_click "installer-next";
    if ($args{disk_empty}) {
        assert_screen "installer-disk", 16;
        assert_and_click "installer-install-now";
    } else {
        assert_and_click "installer-disk-wipe";
        assert_screen "installer-disk-wipe-selected", 16;
        assert_and_click "installer-install-now";
    }
    assert_and_click "installer-disk-confirm", 'left', 16;

    # Timezone has 75% fuzzyness as timezone is geoip'd so its fairly divergent.
    # Also, starting here only the top section of the window gets matched as
    # the bottom part with the buttons now has a progressbar and status
    # text which is non-deterministic.
    # NB: we give way more leeway on the new needle appearing as disk IO can
    #   cause quite a bit of slowdown and ubiquity's transition policy is
    #   fairly weird when moving away from the disk page.
    assert_screen "installer-timezone", 60;
    assert_and_click "installer-next";

    assert_screen "installer-user", 16;
    type_string $user;
    # user in user field, name field (needle doesn't include hostname in match)
    assert_screen "installer-user-user", 16;
    send_key "tab", 1; # username field
    send_key "tab", 1; # 1st password field
    type_string $password;
    send_key "tab", 1; # 2nd password field
    type_string $password;
    # all fields filled (not matching hostname field)
    assert_screen "installer-user-complete", 16;
    assert_and_click "installer-next";

    assert_screen "installer-show", 15;

    # Let install finish
    assert_screen "installer-restart", 640;
}

sub run {
    my ($self) = shift;

    # Divert installation data to live data.
    $testapi::username = 'neon';
    $testapi::password = '';

    $self->boot;
    $self->prepare;
    $self->install;

    if (get_var('OPENQA_PARTITIONING')) {
        # Reset the system and redo the entire installation to ensure partitioning
        # works on pre-existing partition tables. This is broken in bionic as of
        # the user edition ISO from 2018-09-15.

        power 'reset';
        reset_consoles;

        $self->boot;
        $self->prepare;
        $self->install(disk_empty => 0);
    }

    select_console 'log-console';
    {
        # Make sure networking is on (we disable it during installation).
        $self->online;
        $self->upload_ubiquity_logs;
    }
    select_console 'x11';

    assert_and_click "installer-restart-now";

    $self->live_reboot;

    # Set installation data.
    $testapi::username = $user;
    $testapi::password = $password;
}

sub upload_ubiquity_logs {
    # Uploads end up in wok/ulogs/
    assert_script_sudo 'tar cfJ /tmp/installer.tar.xz /var/log/installer';
    upload_logs '/tmp/installer.tar.xz', failok => 1;
}

sub post_fail_hook {
    my ($self) = shift;
    $self->SUPER::post_fail_hook;
    $self->upload_ubiquity_logs;
}

sub test_flags {
    # without anything - rollback to 'lastgood' snapshot if failed
    # 'fatal' - whole test suite is in danger if this fails
    # 'milestone' - after this test succeeds, update 'lastgood'
    # 'important' - if this fails, set the overall state to 'fail'
    return { important => 1, fatal => 1 };
}

1;
