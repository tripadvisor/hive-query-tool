#!/usr/bin/env perl
#
# This is a simple script that converts the output from a hive job that was written
# to a local directory into a gzipped CSV file.
#
# Usage:
#   ./convert-hive-output.pl /path/to/hive/output /path/to/csvfile.csv.gz
#
# @Author: Stephen R. Scaffidi <sscaffidi@tripadvisor.com>
# @Date: Sept. 2012
#
use strict;
use warnings;
use feature ':5.10.1';
use autodie;
use File::Slurp qw(read_dir);
# TODO: find something that doesn't need zlib headers and use that instead.
#use PerlIO::gzip;
use IO::Compress::Gzip qw($GzipError);
use Text::CSV;

my $in_dir   = shift;
my $out_file = shift;

#open my $out_fh, ">:gzip", $out_file;
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

