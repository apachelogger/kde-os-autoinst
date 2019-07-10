package distribution_neon;
use base 'distribution';

use testapi qw(send_key %cmd assert_screen check_screen check_var get_var match_has_tag set_var type_password type_string wait_serial mouse_hide send_key_until_needlematch record_soft_failure wait_still_screen wait_screen_change diag);

sub init() {
    my ($self) = @_;
    $self->SUPER::init();
    $self->init_consoles();
    $self->{console_sudo_cache} = %{()};
}

sub x11_start_program($$$) {
    my ($self, $program, $timeout, $options) = @_;
    # KRunner is dbus-invoked, this can take a while. Make sure we give it
    # enough time.
    $timeout //= 4;
    # enable valid option as default
    $options->{valid} //= 1;
    send_key "alt-f2";
    mouse_hide(1);
    check_screen('desktop-runner', $timeout);
    type_string $program;
    sleep 8;
    send_key "ret";
}

sub ensure_installed {
    my ($self, $pkgs, %args) = @_;
    my $pkglist = ref $pkgs eq 'ARRAY' ? join ' ', @$pkgs : $pkgs;
    $args{timeout} //= 90;

    testapi::x11_start_program('konsole');
    assert_screen('konsole');
    testapi::assert_script_sudo("chown $testapi::username /dev/$testapi::serialdev");
    testapi::assert_script_sudo("chmod 666 /dev/$testapi::serialdev");

    # make sure packagekit service is available
    testapi::assert_script_sudo('systemctl is-active -q packagekit || (systemctl unmask -q packagekit ; systemctl start -q packagekit)');
    $self->script_run(
"for i in {1..$retries} ; do pkcon -y install $pkglist && break ; done ; RET=\$?; echo \"\n  pkcon finished\n\"; echo \"pkcon-\${RET}-\" > /dev/$testapi::serialdev",
        0
    );

    if (check_screen('polkit-install', $args{timeout})) {
        type_password;
        send_key('ret', 1);
    }

    wait_serial('pkcon-0-', $args{timeout}) || die "pkcon failed";
    send_key('alt-f4');
}


# initialize the consoles needed during our tests
sub init_consoles {
    my ($self) = @_;

    $self->add_console('root-virtio-terminal', 'virtio-terminal', {});
    # NB: ubuntu only sets up tty1 to 7 by default.
    $self->add_console('log-console', 'tty-console', {tty => 6});

    # in bionic ubuntu switched to tty1 for default. we adjusted our sddm
    # accordingly.
    $self->add_console('x11', 'tty-console', {tty => 1});

    # oem-config runs on tty1, later it will drop into tty7 for the final
    # x11.
    $self->add_console('oem-config', 'tty-console', {tty => 1});

    use Data::Dumper;
    print Dumper($self->{consoles});

    return;
}

sub script_sudo($$) {
    # Clear the TTY first, otherwise we may needle match a previous sudo
    # password query and get confused. Clearing first make sure the TTY is empty
    # and we'll either get a new password query or none (still in cache).
    type_string "clear\n";

    # NB: this is an adjusted code copy from os-autoinst distribution, we're
    #   caching sudo results as by default sudo has a cache anyway.
    my ($self, $prog, $wait) = @_;

    # Iff the current console is a tty and it's been less than 4 minutes since
    # the last auth we don't expect an auth and skip the auth needle.
    # The time stamps are reset in activate_console which is only called after
    # consoles get reset and switched to again, so this should be fairly ok.
    # !tty never are cached. e.g. on x11 you could have multiple konsoles but
    # since the sudo cache is per-shell we don't know if there is a cache.
    use Scalar::Util 'blessed';
    my $class = blessed($self->{consoles}{$testapi::current_console});
    my $is_tty = ($class =~ m/ttyConsole/);
    my $last_auth = $self->{console_sudo_cache}{$testapi::current_console};
    my $need_auth = (!$is_tty || !$last_auth || (time() - $last_auth >= 4 * 60));
    # Debug for now. Can be removed when someone stumbles upon this again.
    print "sudo cache [tty: $is_tty, last_auth: $last_auth, need auth: $need_auth]:\n";

    $wait //= 10;

    my $str;
    if ($wait > 0) {
        $str  = testapi::hashed_string("SS$prog$wait");
        $prog = "$prog; echo $str > /dev/$testapi::serialdev";
    }
    testapi::type_string "sudo $prog\n";
    if ($need_auth) {
        if (testapi::check_screen "sudo-passwordprompt", 2, no_wait => 1) {
            testapi::type_password;
            testapi::send_key "ret";

            $self->{console_sudo_cache}{$testapi::current_console} = time();
        }
    }
    if ($str) {
        return testapi::wait_serial($str, $wait);
    }
    return;
}

sub activate_console {
    my ($self, $console) = @_;

    diag "activating $console";

    $self->{console_sudo_cache}{$console} = 0;

    if ($console eq 'log-console') {
        assert_screen 'tty6-selected';

        type_string $testapi::username;
        send_key 'ret';
        assert_screen 'tty-password';
        type_password $testapi::password;
        send_key 'ret';

        assert_screen [qw(tty-logged-in tty-login-incorrect)];
        if (match_has_tag('tty-login-incorrect')) {
            # Let's try again if the login failed. If it fails again give up.
            # It can happen that due to IO some of the password gets lost.
            # Not much to be done about that other than retry and hope for the
            # best.
            type_string $testapi::username;
            send_key 'ret';
            assert_screen 'tty-password';
            type_password $testapi::password;
            send_key 'ret';
            assert_screen 'tty-logged-in';
        }

        # Mostly just a workaround. os-autoinst wants to write to /dev/ttyS0 but
        # on ubuntu that doesn't fly unless chowned first.
        testapi::assert_script_sudo("chown $testapi::username /dev/$testapi::serialdev");
        testapi::assert_script_sudo("chmod 666 /dev/$testapi::serialdev");
    }

    return;
}

# Make sure consoles are ready and in a well known state. This prevents
# switching between consoles quickly from ending up on a console which isn't
# yet ready for use (e.g. typing on TTY before ready and losing chars).
sub console_selected {
    my ($self, $console, %args) = @_;
    # FIXME: should make sure the session is unlocked
    if ($console eq 'x11') {
        # Do not wait on X11 specifically. Desktop state is wildely divergent.
        # Instead wait a static amount. This is a bit shit. But meh.
        # We could maybe needle the panel specifically? But then sddm has no
        # panel. I am really not sure how to best handle this.
        sleep 2;
        return;
    }
    assert_screen($console, no_wait => 1);
}

1;
