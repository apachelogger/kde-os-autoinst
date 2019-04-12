#!/usr/bin/env ruby
# frozen_string_literal: true
#
# Copyright (C) 2016-2018 Harald Sitter <sitter@kde.org>
#
# This library is free software; you can redistribute it and/or
# modify it under the terms of the GNU Lesser General Public
# License as published by the Free Software Foundation; either
# version 2.1 of the License, or (at your option) version 3, or any
# later version accepted by the membership of KDE e.V. (or its
# successor approved by the membership of KDE e.V.), which shall
# act as a proxy defined in Section 6 of version 3 of the license.
#
# This library is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
# Lesser General Public License for more details.
#
# You should have received a copy of the GNU Lesser General Public
# License along with this library.  If not, see <http://www.gnu.org/licenses/>.

require 'fileutils'

Dir.chdir(File.dirname(__dir__)) # go into working dir

if ENV['OPENQA_OS_AUTOINST_IN_TREE'] || !File.exist?('/opt/os-autoinst')
  # Install into working tree. I am not sure why though. FIXME: install to opt
  require_relative 'install.rb'
  # Only needed when bootstrapped from ubuntu.
  system('gem install jenkins_junit_builder') || raise
elsif ENV.fetch('NODE_NAME', '') == 'master' ||
      ENV.fetch('NODE_NAME', '').include?('autoinst')
  # Make sure master has the latest version in there.
  Dir.chdir('/opt') { system("#{__dir__}/install.rb") || raise }
end

system('bin/sync.rb') || raise if ENV['INSTALLATION']
exec('bin/run.rb')
