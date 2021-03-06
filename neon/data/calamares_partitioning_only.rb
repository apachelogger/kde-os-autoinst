#!/usr/bin/env ruby
#
# Copyright (C) 2018 Harald Sitter <sitter@kde.org>
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

# Disable all modules except for partitioning.

require 'yaml'

puts "#{$0}: Disabling all clamares modules except for partitioning"

file = '/calamares/desktop/settings.conf'
settings = YAML.load_file(file)
exec_rule = settings['sequence'].find { |x| x.key?('exec') }
exec_rule['exec'] = %w[partition]
File.write(file, YAML.dump(settings))

# HACK!
# FIXME: https://github.com/calamares/calamares/issues/1170
require 'fileutils'
FileUtils.cp('/sbin/sfdisk', '/sbin/sfdisk.orig', verbose: true)
File.write('/sbin/sfdisk', <<-EOF)
#!/bin/sh

udevadm settle --timeout=8

exec /sbin/sfdisk.orig "$@"
EOF
File.chmod(0o755, '/sbin/sfdisk')
