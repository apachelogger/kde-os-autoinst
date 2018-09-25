# Copyright (C) 2017-2018 Harald Sitter <sitter@kde.org>
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

package livetest_neon;
use base 'basetest_neon';

use testapi;
use strict;

sub new {
    my ($class, $args) = @_;
    my $self = $class->SUPER::new($args);
    # OPENQA_IS_OFFLINE is an env var used by online/offline.
    return $self;
}

sub post_fail_hook {
    my ($self, $args) = @_;

    # Make sure networking is on (we disable it during installation).
    $self->online;

    # Base test handles everything we need handling
    return $self->SUPER::post_fail_hook;
}

sub login {
    die 'not implemented'
}

sub maybe_login {
    die 'not implemented'
}

sub boot_to_dm {
    die 'not possible for live sessions'
}

sub _archive_iso_artifacts {
    upload_logs '/cdrom/.disk/info', log_name => 'metadata';
    upload_logs '/cdrom/casper/filesystem.manifest', log_name => 'metadata';
}

sub _secureboot {
    if (!get_var('SECUREBOOT')) {
        return
    }
    assert_script_sudo 'apt install -y mokutil', 60;
    assert_script_sudo 'mokutil --sb-state', 16;
    assert_screen 'mokutil-sb-on';
}

sub offline {
    my ($self, $args) = @_;

    if (!get_var('OPENQA_INSTALLATION_OFFLINE')) {
        return;
    }

    if (defined $ENV{'OPENQA_IS_OFFLINE'}) {
        return;
    }

    my $previous_console = $testapi::selected_console;
    select_console 'log-console';
    {
        assert_script_sudo 'nmcli networking off';
    }
    select_console $previous_console;

    $ENV{'OPENQA_IS_OFFLINE'} = '1';
}

sub online {
    my ($self, $args) = @_;

    if (!get_var('OPENQA_INSTALLATION_OFFLINE')) {
        return;
    }

    if (!defined $ENV{'OPENQA_IS_OFFLINE'}) {
        return;
    }

    my $previous_console = $testapi::selected_console;
    select_console 'log-console';
    assert_script_sudo 'nmcli networking on';
    select_console $previous_console;

    delete $ENV{'OPENQA_IS_OFFLINE'};
}

sub maybe_switch_offline {
    my ($self, $args) = @_;

    if (!get_var('OPENQA_INSTALLATION_OFFLINE')) {
        print "staying online!\n";

        # Run the early first start script to install coredumpd.
        # Only when NOT offline!
        # This runs apt update which would otherwise break the offline testing
        # with an update apt cache.
        # FIXME: we should possibly preseed the coredumpd into the ISO repo
        #   so we can install it even without internet in the tests.
        #   The package is fairly small and has no extra deps.
        select_console 'log-console';
        {
          assert_script_run 'wget ' . data_url('early_first_start.rb'),  16;
          assert_script_sudo 'ruby early_first_start.rb', 60 * 5;
        }
        select_console 'x11';

        return 0;
    }

    select_console 'log-console';
    {
        print "going offline!\n";
        $self->offline;

        # TODO: This isn't the most reliable assertion.
        #   Ideally we'd have a list of all packages simulate them to make
        #   sure all deps are installed. Or maybe even install them one
        #   by one to make sure they actually work?
        # Make sure the preinstalled repo is actually being used.
        assert_script_sudo 'DEBIAN_FRONTEND=noninteractive apt-get install -y bcmwl-kernel-source', 10 * 60;
    }
    select_console 'x11';

    assert_screen 'plasma-nm-offline';

    return 1;
}

sub bootloader_secureboot {
    if (!get_var('SECUREBOOT')) {
        return;
    }

    # Enable scureboot first. When in secureboot mode we expect a second
    # ISO to be attached for uefi fs1 where we can run a efi program to
    # enroll the default keys to enable secureboot.
    # In the core.pm we'll then assert that secureboot is on.
    # In first_start.pm we'll further assert that secureboot is still on.

    # Use a fairly low timeout for the f2 trigger. The default 1 second
    # timeout might well cause us to shoot past tianocore and into the ISO.
    # Checking more often is more expensive, but should prevent this from
    # failing. Try this for only 10 seconds. If we aren't in OVMF by then
    # something definitely went wrong.
    send_key_until_needlematch 'ovmf', 'f2', 10 * 4, 0.25;
    send_key_until_needlematch 'ovmf-select-bootmgr', 'down';
    send_key 'ret';
    send_key_until_needlematch 'ovmf-bootmgr-shell', 'up'; # up is faster
    send_key 'ret';
    assert_screen 'uefi-shell', 30;
    type_string 'fs1:';
    send_key 'ret';
    assert_screen 'uefi-shell-fs1';
    type_string 'EnrollDefaultKeys.efi';
    send_key 'ret';
    type_string 'reset';
    send_key 'ret';
    reset_consoles;
}

sub bootloader {
    my ($self, $args) = @_;
    $self->bootloader_secureboot;

    # Wait for installation bootloader. This is either isolinux for BIOS or
    # GRUB for UEFI.
    # When it is grub we need to hit enter to proceed.
    assert_screen 'bootloader', 60;
    if (match_has_tag('live-bootloader-uefi')) {
        # Hack to force kmsg onto ttyS1 to debug shutdown problems. This hack
        # can be dropped once neon properly shuts down all the time again!
        # Edits grub entry to add more kernel cmdlines.
        send_key 'e';

        my $counter = 8;
        while (!check_screen('live-grub-linux', 1)) {
            if (!$counter--) {
                last;
            }
            send_key 'down';
            sleep 1;
        }

        send_key 'end';
        send_key 'left';
        send_key 'left';
        send_key 'left';
        # Set the kmsg target to ttyS1. We then also need to force plymouth as
        # it'd not do anything if console= is set.
        type_string 'console=ttyS1 plymouth.force-splash plymouth.ignore-show-splash plymouth.ignore-serial-consoles ';
        send_key 'ctrl-x';

        if (testapi::get_var("INSTALLATION_OEM")) {
          send_key 'down';
          assert_screen('live-bootloader-uefi-oem');
        }
        send_key 'ret';
    }
}

# Waits for system to boot to desktop.
sub boot {
    my ($self, $args) = @_;

    my $user = $testapi::username;
    my $password = $testapi::password;
    $testapi::username = 'neon';
    $testapi::password = '';

    $self->bootloader;

    # We better be at the desktop now.
    assert_screen 'live-desktop', 360;

    select_console 'log-console';
    {
                  validate_script_output 'grep -e "Using input driver" /var/log/Xorg.0.log',
                                         sub { m/.+evdev.+/ };

        $self->_archive_iso_artifacts;
        $self->_secureboot;
        $self->_upgrade;

        assert_script_run 'wget ' . data_url('permissions_check.rb'),  16;
        assert_script_run 'ruby permissions_check.rb', 16;

        # This primarily to set up journald console output for /dev/ttyS1.
        # This script will also be run for the final system on first start and
        # retained in the image.
        assert_script_run 'wget ' . data_url('setup_journald_ttyS1.rb'),  16;
        assert_script_sudo 'ruby setup_journald_ttyS1.rb', 60 * 5;

        # Make sure the evdev driver is installed. We prefer evdev at this time
        # instead of libinput since our KCMs aren't particularly awesome for
        # libinput.
        # if (get_var('OPENQA_SERIES') ne 'xenial') {
        #     assert_script_run 'dpkg -s xserver-xorg-input-evdev';
        #     validate_script_output 'grep -e "Using input driver" /var/log/Xorg.0.log',
        #                            sub { m/.+evdev.+/ };
        # }

        # TODO: maybe control via env var?
        # assert_script_run 'wget ' . data_url('enable_qdebug.rb'),  16;
        # assert_script_run 'ruby enable_qdebug.rb', 16;
    }
    select_console 'x11';

    # Leave system as we have found it.
    assert_screen 'live-desktop', 5 * 60;

    $testapi::username = $user;
    $testapi::password = $password;
}

# TODO: could maybe be renamed to reboot and also grow an impl in basetest, then
#   use them interchangably. However, this doesn't actually trigger a reboot,
#   but conducts it, so it's somewhat different from a regular reboot in
#   basetest. Muse on this a bit.
sub live_reboot {
    assert_screen "live-remove-medium", 60;
    # The message actually comes up before input is read, make sure to send rets
    # until the system reboots or we've waited a bit of time. We'll then
    # continue and would fail on the first start test if the system in fact
    # never rebooted.
    my $counter = 20;
    while (check_screen('live-remove-medium', 1)) {
      if (!$counter--) {
          last;
      }
      eject_cd;
      send_key 'ret';
      sleep 1;
    }

    # There's a bug in the unit ordering which prevents reboot from working
    # every once in a while. I utterly failed to debug what exactly is wrong,
    # but it sucks enormously in code that isn't even maintained by us.
    # So, to mitigate this problem w'll force a reset if the remove medium
    # screen is still up after having tried to reboot nicely.
    #           - sitter, Sept. 2018
    if (check_screen('live-remove-medium', 1)) {
        eject_cd;
        sleep 1;
        power 'reset';
    }

    reset_consoles;
}

1;
