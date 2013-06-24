#!/usr/bin/env perl
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

