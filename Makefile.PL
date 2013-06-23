##############################################################################
#                                                                            #
#   Copyright 2013 TripAdvisor, LLC                                          #
#                                                                            #
#   Licensed under the Apache License, Version 2.0 (the "License");          #
#   you may not use this file except in compliance with the License.         #
#   You may obtain a copy of the License at                                  #
#                                                                            #
#       http://www.apache.org/licenses/LICENSE-2.0                           #
#                                                                            #
#   Unless required by applicable law or agreed to in writing, software      #
#   distributed under the License is distributed on an "AS IS" BASIS,        #
#   WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied. #
#   See the License for the specific language governing permissions and      #
#   limitations under the License.                                           #
#                                                                            #
##############################################################################
use strict;
use warnings;
use ExtUtils::MakeMaker;
##############################################################################
#
# If you are unfamiliar with this file, Makefile.PL, it is one of the primary
# means by which Perl software is configured, built, and installed. If you are
# attempting to build this software and the errors you are experiencing have
# led you here, and you are in unfamiliar territory, you should stop now and
# instead file a bug report at the site where you got this software, or email
# the authors. (bug report preferred, please)
#
##############################################################################

# creates a makefile to build, test, and install the HQT
WriteMakefile(

  # version of the HQT being installed
  VERSION => '0.01',

  # specify the modules that the HQT uses.
  PREREQ_PM => {

    'Perl' => '5.010001',

    # If the version matters, put it here. By default, the specified version
    # is the lowest that will be accepted. If a higher one is available, *it*
    # will be installed instead. If you need to be more specific, see this:
    #   https://metacpan.org/module/CPAN::Meta::Spec#Version-Formats
    'Mojolicious'            => '3.87',     # minimum supported version
    'IO::Socket::IP'         => '0.21',     # contains fix for cpan RT81549
    'Email::Sender::Simple'  => '1.300006', # v1.3 now uses Moo instead of Moose

    # if the version doesn't matter, put it in the list below.
    # the "required version" will be set to 0 which means "whatever"
    (map { $_ => 0 } qw(
      AnyEvent
      AnyEvent::HTTPD
      autodie
      CGI::Expand
      CLASS
      DateTime
      DateTime::Format::Strptime
      DBM::Deep
      File::Slurp
      File::Which
      Hash::Merge::Simple
      IO::Compress::Gzip
      IO::Socket::SSL
      IPC::System::Simple
      JSON
      List::MoreUtils
      MIME::Entity
      Mojolicious::Lite
      Mojolicious::Plugin::RenderFile
      Mojolicious::Plugin::YamlConfig
      Moo
      MooX::Types::MooseLike::Email
      namespace::sweep
      Net::LDAP
      Package::Alias
      Params::Util
      Scalar::Util
      Storable
      String::ShellQuote
      syntax
      Syntax::Feature::Qwa
      Sys::Hostname
      Text::CSV
      Text::Template
      Text::Trim
      Time::HiRes
      Try::Tiny
      YAML::Any
    ), ),
  },

  # where to look for HQT test scripts when running "make test"
  test => {TESTS => 't/*.t'},
);

