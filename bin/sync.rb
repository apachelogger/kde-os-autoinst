#!/usr/bin/env ruby
# frozen_string_literal: true
#
# Copyright (C) 2017 Harald Sitter <sitter@kde.org>
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

# NB: stolen from pangea-tooling (same license and copyright)
# Retry given block.
# @param tries [Integer] amount of tries
# @param errors [Array<Object>] errors to rescue
# @param sleep [Integer, nil] seconds to sleep between tries
# @param name [String, 'unknown'] name of the action (debug when not silent)
# @yield yields to block which needs retrying
def retry_it(times: 1, errors: [StandardError], sleep: nil, silent: false,
             name: 'unknown')
  yield
rescue *errors => e
  raise e if (times -= 1) <= 0
  print "Error on retry_it(#{name}) :: #{e}\n" unless silent
  Kernel.sleep(sleep) if sleep && !@sleep_disabled
  retry
end


TYPE = ENV.fetch('TYPE')
ISO_URL = "http://files.kde.org/neon/images/neon-#{TYPE}/current/neon-#{TYPE}-current.iso".freeze
ZSYNC_URL = "#{ISO_URL}.zsync".freeze
SIG_URL = "#{ISO_URL}.sig".freeze
GPG_KEY = '348C 8651 2066 33FD 983A 8FC4 DEAC EA00 075E 1D76'.freeze

if File.exist?('incoming.iso')
  warn "Using incoming.iso for #{TYPE}"
  FileUtils.mv('incoming.iso', 'neon.iso', verbose: true)
  exit 0
end

warn ISO_URL
if ENV['NODE_NAME'] # probably jenkins use, download from mirror
  # zsync_curl has severe performance problems from curl. It uses the same code
  # the original zsync but replaces the custom http with curl, the problem is
  # that the has 0 threading, so if only one block needs downloading it has
  # curl overhead + DNS overhead + SSL overhead + checksum single core calc.
  # All in all zsync_curl often performs vastly worse than downloading the
  # entire ISO would.
  # TODO: with this in place we can also drop stashing and unstashing of
  #   ISOs from master.
  system('wget', '-q', '-O', 'neon.iso',
         ISO_URL.gsub('files.kde.org', 'files.kde.mirror.pangea.pub')) || raise
  system('wget', '-q', '-O', 'neon.iso.sig',
         SIG_URL.gsub('files.kde.org', 'files.kde.mirror.pangea.pub')) || raise
else # probably not
  system('zsync_curl', '-o', 'neon.iso', ZSYNC_URL) || raise
  system('wget', '-q', '-O', 'neon.iso.sig', SIG_URL) || raise
end
# Retry this a bit, gpg servers may not always answer in time.
retry_it(times: 4, sleep: 1) do
  system('gpg2',
         '--keyserver', 'keyserver.ubuntu.com',
         '--recv-key', GPG_KEY,) || raise
end
system('gpg2', '--verify', 'neon.iso.sig') || raise
