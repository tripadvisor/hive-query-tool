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
#
# This is a simple script that converts the output from a hive job that was written
# to a local directory into a gzipped CSV file.
#
# Usage:
#   ./convert-hive-output.pl /path/to/hive/output /path/to/csvfile.csv.gz
#
# @Author: Stephen R. Scaffidi <sscaffidi@tripadvisor.com>
# @Date: June 2013
#
use strict;
use warnings;
use feature ':5.10.1';
use autodie;
use File::Slurp qw(read_dir);
use IO::Compress::Gzip qw($GzipError);
use Text::CSV;

my $in_dir   = shift;
my $out_file = shift;

my $out_fh = IO::Compress::Gzip->new( $out_file )
  or die "Couldn't initialize FH for gzip output: [$GzipError]";

# initialize the CSV writer
my $csv = Text::CSV->new({ binary => 1, auto_diag => 2, eol => $/ });

my @input_files =
  grep { $_ ne "$out_file" }
  map { "$in_dir/$_" }
  sort { $a cmp $b }
  grep { ! /^\./ }
  read_dir $in_dir;

for my $in_file ( @input_files ) {
  open my $in_fh, '<', $in_file;
  while ( defined( my $line = readline $in_fh ) ) {
    chomp($line);
    $csv->print( $out_fh, [ split '\001', $line ] );
  }
}

