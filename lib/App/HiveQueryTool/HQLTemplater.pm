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
use feature ':5.10.1';
package App::HiveQueryTool::HQLTemplater;
# ABSTRACT: define and work with HQL Templates
use Data::Dumper;
use Text::Template qw(fill_in_string);
use DateTime;
use DateTime::Format::Strptime qw(strptime);
use Storable qw(dclone);
use Carp;
use Safe;
use Text::Trim qw(trim ltrim rtrim);
use Try::Tiny;
use Scalar::Util qw(looks_like_number);

# these vars need to be in scope for Text::Template's processing
our %DATA;     # the data to fill in
our %METADATA; # info about the data that will be filled in
our @ERRORS;   # errors get stored here to display to the user


# $MODE determines what the template functions should be doing.
# If 'meta': the functions should be building up a data-structure that describes what
#            form fields to show on the web page.
# If 'fill': the functions should be returning the HQL fragments to fill the template
#            with.
our $MODE;

### TODO: figure out how to make this work properly inside a SAFE compartment.
# this is a "safe compartment". The template code will be executed inside this sandbox
# which ensures that it can't do things like call system('rm -rf /') or manipulate
# variables outside the compartment's namespace.
our $SAFE = Safe->new;

# this is executed at the beginning of every call to fill_in() on each template.
our $TMPL_HEAD = <<'END_CODE';
use strict;
use warnings;
use feature ':5.10.1';
use Carp;
use autodie;
END_CODE

our $QUERY_PREFIX_STR =<<'END_QUERY_PREFIX';
SET hive.exec.compress.output = false;
INSERT OVERWRITE LOCAL DIRECTORY '{$output_directory_path}'
END_QUERY_PREFIX

# get the metadata for the functions embedded in the template
sub get_metadata {
  my ($tmpl) = @_;

  local $MODE='meta';

  %METADATA = ();
  @ERRORS = ();

  # calling this for the side-effects - when $MODE is meta, the functions in this
  # package will use their arguments to fill-in %METADATA, which we will then return.
  fill_in_string( $tmpl, prepend => $TMPL_HEAD , BROKEN => \&template_broken);

  return \%METADATA;
}

sub template_broken {
   my %args = @_;
   push @ERRORS,  $args{error};
   return undef;
}

sub fill {
  my ($tmpl, $user_input) = @_;

  $MODE='fill';
  %DATA = ();
  @ERRORS = ();

  my $meta = get_metadata($tmpl);

  # make sure the user gave values for all vars in meta, or use the default.
  for my $var_name (keys %{ $meta->{var} || {} } ) {
    my $default = $meta->{var}{$var_name}{default};
    $DATA{var}{$var_name} = $user_input->{var}{$var_name} // $default;
  }

  $DATA{select}     = $user_input->{select};
  $DATA{where}      = $user_input->{where};
  $DATA{group}      = $user_input->{group};
  $DATA{where_mode} = $user_input->{where_mode};
  $DATA{limit}      = $user_input->{limit};
  $DATA{res_dir}    = $user_input->{res_dir};

  my $new_hql = fill_in_string( $tmpl, prepend => $TMPL_HEAD , BROKEN => \&template_broken);

  # strip out blank lines
  $new_hql =~ s/^\s*\n//gms;

  if ($meta->{main_select_marked}) {
    return $new_hql;
  }
  else {
    return $QUERY_PREFIX_STR . $new_hql;
  }
}

sub fill_directory_in_template {
  my ($tmpl, $dir_path_value) = @_;
  my $new_tmpl = fill_in_string($tmpl, HASH => { output_directory_path => $dir_path_value});
  return $new_tmpl;
}

###########################################################
# TEMPLATE FUNCTIONS BELOW

sub validate_var {
  my ($name) = @_;
  return unless $MODE eq 'fill';
  my $var_type = $METADATA{var}{$name}->{type};
  return unless defined $var_type;
  if( $var_type eq 'date'){
    try {
      ymd_to_dt( $DATA{var}{$name});
    }
    catch {
      # output exception text and info for debuging
      warn "Error attempting to convert to user input to DateTime: $_";

      # throw a new exception with a more useful message for the user.
      # strip out any existing error location info, then make sure the
      # message ends with a newline to suppress adding more location info.
      s{\sat\s[/].*?\sline\s\d+[.]?}{}gxms;
      die join ' ', "value [$DATA{var}{$name}] for var [$name] is not",
      "a valid date in yyyy-mm-dd format: $_\n";
    };
  }
  return;
}

sub insert_var {
  my ($name, $opt) = @_;
  given ($MODE) {
    when ('meta') {
      $METADATA{var}{$name} ||= ($opt? dclone $opt: {});
      return;
    }
    when ('fill') {
      validate_var( $name );
      my $var_type = $METADATA{var}{$name}->{type};
      my $var_val = $DATA{var}{$name};
      given ( $var_type ) {
        when ('list') {
          return sql_escape_string_list($var_val); # make comma-separated list SQL-safe
        }
        when ('int') {
          return $var_val;
        }
        default {
          return "'$var_val'";
        }
      }
    }
  }
}

sub insert_select {
  my (%opt) = @_;
  given ($MODE) {
    when ('meta') {
      die "Not Yet Implemented";
    }
    when ('fill') {
      return unless $DATA{select};
    }
  }
}

sub insert_where {
  my ($opt) = @_;
  given ($MODE) {
    when ('meta') {
      $METADATA{where_columns} ||= $opt->{columns};
      return;
    }
    when ('fill') {
      my $where_clause = fill_where();
      return unless $where_clause;
      return "WHERE $where_clause ";
    }
  }
}

sub fill_where {
  return $DATA{where_str} if $DATA{where_str};
  return unless $DATA{where};
  my $mode = $DATA{where_mode} || 'AND';
  my $where_clause_string = get_where_clause_string($DATA{where});
  $DATA{where_str} = $where_clause_string;
  return unless $where_clause_string;
  return "\( $where_clause_string \)";
}

## constructs a where clause string using the json onject representing the where clause passed in
sub get_where_clause_string{
  my ($json_obj) = @_;
  my $clause_str = "";
  if($json_obj->{type} eq 'unary') {
    $clause_str = construct_single_clause( $json_obj->{col_name}, $json_obj->{col_relational_op}, $json_obj->{col_value});
    if($json_obj->{inner}) {
      return " ( " . $clause_str . " ) ";
    }
    else {
      return $clause_str;
    }
  }
  elsif ($json_obj->{type} eq 'binary') {
    $clause_str = get_where_clause_string( $json_obj->{clause1}) . " $json_obj->{logical_op} " . get_where_clause_string( $json_obj->{clause2});
    if($json_obj->{inner}) {
      return " ( " . $clause_str . ")" ;
    }
    else {
      return $clause_str;
    }
  }
}

sub construct_single_clause {
  my ($col_name, $col_operator, $col_value) = @_;

  # parse out semi-colons to prevent SQL injection
  $col_name =~ s/;//g;
  $col_operator =~ s/;//g;

  # escape single quotes to prevent possible SQL injection
  # don't remove semi-colons for the values here, since it may get quoted and be perfectly valid.
  $col_value =~ s/'/\\'/g;

  if ((uc $col_operator) eq 'LIKE') {
    # it doesn't matter what the metadata type is, put the value in single-quotes and add % wildcards.
    return " $col_name $col_operator \'%$col_value%\' ";
  }
  elsif ((uc $col_operator) eq 'IN') {
    return " $col_name $col_operator (" . sql_escape_string_list($col_value) . ") ";
  }
  # if the column is a string type, the value needs to be quoted,
  # regardless of what's in it.
  elsif( (uc $METADATA{where_columns}{$col_name}) eq 'STRING') {
    return " $col_name $col_operator \'$col_value\' ";
  }
  # If the column's not a string, the value should be a number or NULL and it *shouldn't*
  # be quoted. This works for the following numeric formats/notations/expressions:
  # 12345 12.345 1234E5 1234e5 -12345 +12345 ... and various combinations of those.
  # If any other non-digit characters are present, it will not look like a number.
  elsif ( looks_like_number $col_value or uc($col_value) eq 'NULL') {
    return " $col_name $col_operator $col_value ";
  }
  # if it didn't match the above cases, throw an error
  else {
    die "Column [$col_name] can only accept numbers or NULL. Value [$col_value] is not valid\n";
  }
}

sub insert_invert_where {
  return unless $MODE eq 'fill';
  my $where_clause = fill_where();
  return unless $where_clause;
  return "WHERE NOT $where_clause ";
}

sub append_where {
  my ($opt) = @_;
  given ($MODE) {
    when ('meta') {
      $METADATA{where_columns} ||= $opt->{columns};
      $METADATA{where_mode} ||= $opt->{mode} || 'AND';
      return;
    }
    when ('fill') {
      my $where_clause = fill_where();
      return unless $where_clause;
      my $mode = $DATA{where_mode} || 'AND';
      return "$mode $where_clause ";
    }
  }
}

sub append_invert_where {
  return unless $MODE eq 'fill';
  my $where_clause = fill_where();
  return unless $where_clause;
  my $mode = $DATA{where_mode} || 'AND';
  return "$mode NOT $where_clause ";
}

sub insert_limit {
  my (%opt) = @_;
  given ($MODE) {
    when ('meta') {
      $METADATA{limit} ||= \%opt;
      return;
    }
    when ('fill') {
      return unless $DATA{limit};
      return "LIMIT $DATA{limit}";
    }
  }
}

sub insert_group_by {
  my (%opt) = @_;
  given ($MODE) {
    when ('meta') {
      $METADATA{group_columns} ||= $opt{columns};
      return;
    }
    when ('fill') {
      return unless $DATA{group} and @{$DATA{group}};
      my $clause = "GROUP BY " . join ", ", @{$DATA{group}};
      return $clause;
    }
  }
}

sub append_group_by {
  my (%opt) = @_;
  given ($MODE) {
    when ('meta') {
      $METADATA{group_columns} ||= $opt{columns};
      return;
    }
    when ('fill') {
      return unless $DATA{group} and @{$DATA{group}};
      my $clause = ", " . join ", ", @{$DATA{group}};
      return $clause;
    }
  }
}

sub append_group_by_cols {
  my (%opt) = @_;
  given ($MODE) {
    when ('meta') {
      # do nothing
    }
    when ('fill') {
      return unless $DATA{group} and @{$DATA{group}};
      my $clause = ", " . join ", ", @{$DATA{group}};
      return $clause;
    }
  }
}

sub insert_group_by_cols {
  my (%opt) = @_;
  given ($MODE) {
    when ('meta') {
      # do nothing
    }
    when ('fill') {
      return unless $DATA{group} and @{$DATA{group}};
      my $clause = join ", ", @{$DATA{group}};
      return $clause;
    }
  }
}


############################################################
# not sure how to classify these:

sub var_val {
  my ($var_name) = @_;
  return unless $MODE eq 'fill';
  validate_var($var_name);
  my $val = $DATA{var}{$var_name};
  return $val;
}

sub set_var {
  my ($var_name, $opt) = @_;
  if( $MODE eq 'meta') {
    $METADATA{var}{$var_name} ||= ($opt ? dclone $opt : {});
  }
  else {
    validate_var($var_name);
  }
}


# takes a hash as input:
#   { functions => [ list of references to function],
#     args => [list of arguments to these functions]
#   }
# executes each of these functions with these arguments
sub check_args {
  my %params = @_;
  return unless $MODE eq 'fill';
  my @arguments = @{$params{args}};
  for my $func (@{$params{functions}}) {
    try {
      $func->(@arguments);
    }
    catch {
      warn "Error running check_args function: $_";
      push @ERRORS, "ERROR: $_\n";
    };
  }
}

sub check {
  my (%opt) = @_;
  return unless $MODE eq 'fill';
  try {
    $opt{fn}->();
  }
  catch {
    warn "Error running check function: $_";
    push @ERRORS, "ERROR: $opt{fail_msg}\n";
  };
  return;
}

sub begin_main_select {
  if ($MODE eq 'meta') {
    $METADATA{main_select_marked} = 1;
    return;
  }
  if ($MODE eq 'fill') {
    return unless $METADATA{main_select_marked};
    return $QUERY_PREFIX_STR;
  }
}

############################################################
# Helper functions below

sub today {
  return DateTime->now(time_zone => 'local');
}

sub today_ymd {
  return today->ymd;
}

sub yesterday_ymd {
  return days_ago_ymd(1);
}

sub days_ago_ymd {
  die "days_ago_ymd requires a number" unless looks_like_number($_[0]);
  return today->subtract(days => shift)->ymd;
}

sub weeks_ago_ymd {
  die "weeks_ago_ymd requires a number" unless looks_like_number($_[0]);
  return today->subtract(weeks => shift)->ymd;
}

sub months_ago_ymd {
  die "months_ago_ymd requires a number" unless looks_like_number($_[0]);
  return today->subtract(months => shift)->ymd;
}

sub ymd_to_dt {
  my $time = shift;
  return strptime('%F', $time);
}

# check if start date is less than end date
# argument 1 is start date and argument2 is end date
sub is_start_date_before_end {
  if(@_ != 2 ) {
    push @ERRORS, "Error: Incorrect number of arguments provides to is_start_date_before_end. Required 2.";
  }
  my ($start_date, $end_date) = @_;
  my $start_dt = ymd_to_dt( $start_date);
  my $end_dt = ymd_to_dt( $end_date );
  my $diff = DateTime->compare($start_dt, $end_dt);
  if( $diff > 0) {
    push @ERRORS, "Error: Start Date is greater than end date";
  }
}

# limit date range to no more than one month
# dates should be no more than a month apart
# argument 1 is start date and argument2 is end date
sub limit_month_range {
  if(@_ != 2 ) {
    push @ERRORS, "Error: Incorrect number of arguments provides to limit_month_range. Required 2.";
  }
  my ($start_date, $end_date) = @_;
  my $start_dt = ymd_to_dt( $start_date);
  my $end_dt = ymd_to_dt( $end_date );
  my $diff = DateTime->compare($start_dt, $end_dt->subtract( months =>1 ));
  if( $diff < 0 ) {
    push @ERRORS,  "Error: Dates are month than a month apart";
  }
}


# given a string that is supposed to be a comma-separated list of values,
# look at each value and add quoting and escaping as necessary.
# return a new string with the comma-separated values properly quoted.
# for example, "it, it's,it is , 1, 2," becomes "'it','it\'s','it is',1,2,''"
sub sql_escape_string_list {
  my ($strList) = @_;

  # split comma-separated values, trim leading/trailing whitespace
  my @values = trim( split(/,/, $strList) );

  # numbers pass unquoted, strings get quoted
  my @quoted = map {
    looks_like_number($_) ? $_ : sql_quote_string_value($_);
  } @values;

  # join back into a String
  return join(",", @quoted);
}

# add quotes around a sql/hql string value, escaping single-quotes
# already in the string. If no value or undef is passed, return a
# quoted empty string.
sub sql_quote_string_value {
  my ($str) = @_;
  $str //= '';
  $str =~ s/\'/\\\'/g;
  return "'$str'";
}

1 && q{ I clearly have no shame }; # truth
