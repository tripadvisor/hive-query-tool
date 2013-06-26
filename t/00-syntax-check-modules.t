#!/usr/bin/env perl
use strict;
use warnings;
use Test::More;
use English qw( -no_match_vars );
use File::Find qw();
use FindBin qw( $Bin );
use File::Spec::Functions qw( updir catdir abs2rel );
use Cwd qw( realpath );

# find the lib dir of this dist. If this script is in /path/to/dist/dir/t,
# we want /path/to/dist/dir/lib
my $dist_dir = realpath( catdir( $Bin, updir() ) );
my $lib_dir = catdir( $dist_dir, 'lib' );

# find all module files, make sure we find at least *one*
my @pm_files;
File::Find::find( sub { push @pm_files, $File::Find::name if /\.pm$/ }, $lib_dir );
ok scalar @pm_files, "found .pm files under $lib_dir";

# setup the PERL5LIB env var so when we spawn perl to do the syntax check
# it will contain all the paths currently in @INC, plus $lib_dir. Might
# as well remove dupes while we're at it, too.
my %seen_path;
my @new_inc_paths = map { $seen_path{$_}++ ? () : $_ } $lib_dir, @INC;
$ENV{PERL5LIB} = join ":", @new_inc_paths;

# set up the perl command to de-duplicate lib paths before checking syntax
# so we get a somewhat easier-to-read error message when a check fails.
my $perl_cmd = $EXECUTABLE_NAME . q{ '-Mlib do{my %x;map{$x{$_}++?():$_}@INC}'};
# now syntax check eack one
for my $file ( @pm_files ) {
   my $file_relpath = abs2rel( $file, $dist_dir );
   ok -f $file, "normal file check $file_relpath";
   my @output = qx{ $perl_cmd -c $file 2>&1 };
   my $exit_code = $CHILD_ERROR >> 8;
   is $exit_code, 0, "syntax check of $file_relpath" or diag @output;
}

done_testing;
__END__

=pod

=head1 DESCRIPTION

=head1 NOTES

=cut
