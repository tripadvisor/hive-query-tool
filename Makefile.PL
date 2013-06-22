use strict;
use warnings;

# the HQT requires perl 5.10.1 or newer.
use v5.10.1;

use ExtUtils::MakeMaker;

# creates a makefile to build, test, and install the HQT
WriteMakefile(

  # version of the HQT
  VERSION => '0.01',

  # specify the modules that the HQT uses.
  PREREQ_PM => {

    # If the version matters, put it here. By default, the specified version
    # is the lowest that will be accepted. If a higher one is available, *it*
    # will be installed instead. If you need to be more specific, see this:
    #   https://metacpan.org/module/CPAN::Meta::Spec#Version-Formats
    'Mojolicious'    => '3.87',
    'IO::Socket::IP' => '0.21', # contains fix for cpan RT81549

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
      Email::Sender::Simple
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

