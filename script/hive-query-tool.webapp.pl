#!/usr/bin/env perl
use strict;
use warnings;
use English qw(-no_match_vars);

BEGIN {
  # mojolicious requires a version of perl that isn't from the stone age
  my $minver = 'v5.10.1';
  if ($PERL_VERSION lt $minver ) {
    warn <<END;
Your system perl is too old: $EXECUTABLE_NAME version $PERL_VERSION
This program requires at least $minver - Did you run the setup-hqt script
first? If that didn't find a new-enough perl, take a look at perlbrew
to get something newer.
END
    exit 1;
  }
}

# make sure the app lib dir is on the path. Don't bother with the extlib dir
# because if that's not set-up there's probably other, bigger problems.
# since this script lives in the ./scripts subdir, just go up a
# level, then make the resulting path absolute.
use Cwd qw(abs_path);
use FindBin qw($RealBin);
use File::Spec::Functions qw(catdir updir);
use lib abs_path catdir $RealBin, updir, 'lib';

# Start the webapp!
use Mojolicious::Commands;
Mojolicious::Commands->start_app('App::HiveQueryTool');

