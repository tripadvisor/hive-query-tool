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
package App::HiveQueryTool::Controller::BuildQuery;
use Mojo::Base 'App::HiveQueryTool::Controller';


# general imports
use CGI::Expand qw(expand_hash);
use Data::Dumper qw(Dumper);
use DBM::Deep;
use Digest::MD5 qw(md5_hex);
use File::Basename qw(basename);
use File::Find qw();
use File::Slurp qw(read_dir read_file);
use File::Spec::Functions qw(updir catfile);
use FindBin qw($RealBin);
use JSON qw(to_json from_json);
use Storable qw(dclone);
use Hash::Merge::Simple qw(merge);
use Text::Template;
use Time::HiRes;
use Try::Tiny;
use YAML::Any qw(Load);

# We reference this a bit, and the name is unweildy, so
# alias it to something shorter.
use Package::Alias HQLTemplater => 'App::HiveQueryTool::HQLTemplater';

our $HIVECLI_URI;
our $HQL_TEMPLATES;

sub init {
    my $c = shift;
    $HIVECLI_URI   = $c->app->config('backend_listen');
    my $template_dir = catfile $c->app->home, $c->app->config('hql_template_dir');
    $HQL_TEMPLATES = _load_query_templates( $template_dir );
}

sub _load_query_templates {
    my ($hqt_dir) = @_;

    my %template_info;
    die "Could not find directory $hqt_dir" unless -d $hqt_dir;

    # get the paths to all non-hidden files ending in .hqt in the dir
    my @hqt_files;
    File::Find::find(
        {
            follow => 1,
            wanted => sub {
                push @hqt_files, $File::Find::fullname
                    if defined $_ and /[.]hqt$/ and not /^[.]/
            },
        },
        $hqt_dir,
    );

    # now load them up, one by one.
    for my $file ( @hqt_files ) {
        try {
            my ( $yaml, $hqt ) = read_file( $file ) =~ /(.*?) ^[.]{3}$ (.*)/msx;
            if ( !$yaml or !$hqt ) {
                die join ' ', "ERROR: The file [$file] does not appear to be valid.",
            }
            my $ti = merge Load( $yaml ), { template => $hqt, file => $file };
            if (exists $template_info{$ti->{id}}) {
                my $other_file = $template_info{$ti->{id}}->{file};
                die join ' ', "ERROR: The HQL Template id [$ti->{id}] in",
                    "file [$file] conflicts with the id in [$other_file]";
            }
            $template_info{$ti->{id}} = $ti;
        } catch {
            warn "Error loading HQL Template file [$file]: $_"
        };
    }

    return \%template_info;
}


sub select_template {
  my $c = shift;
  $c->app->log->debug("in select-template handler");
  warn "in select-template handler";
  my %template_info;
  for my $tmpl_key (keys %$HQL_TEMPLATES) {
    $template_info{$tmpl_key} = $HQL_TEMPLATES->{$tmpl_key};
  }
  $c->render('select-template', template_info => \%template_info );
}


sub edit_template  {
  my $self = shift;
  my $id = $self->param('template_id') || return $self->redirect('select-template');
  $self->render( 'set-query',
    template_id => $id,
    template_name => $HQL_TEMPLATES->{$id}{name},
    template_code => $HQL_TEMPLATES->{$id}{template},
    template_description => $HQL_TEMPLATES->{$id}{description},
  );
}

# enter the query parameters and submit to hive
sub prep_query {
  my $self = shift;
  my $id = $self->param('template_id') || return $self->redirect('select-template');
  my $tmpl = $HQL_TEMPLATES->{$id}{template};
  my $meta = HQLTemplater::get_metadata( $tmpl );

  my @where_column_names = ($meta->{where_columns} ? keys %{$meta->{where_columns}} : ());

  $self->stash(
    template_id => $id,
    template_name => $HQL_TEMPLATES->{$id}{name},
    template_description => $HQL_TEMPLATES->{$id}{description},
    hql_tmpl      => $tmpl,
    where_columns => \@where_column_names,
    group_columns => $meta->{group_columns} || [],
    limit         => $meta->{limit},
    vars          => $meta->{var} || {},
    errors        => \@HQLTemplater::ERRORS,
  );

  $self->render( 'prep-query' );
}

# this is not used as a route. This is a helper used by both preview and run
sub prepare_query {
  my ($tmpl_id, $params) = @_;
  my $tmpl      = $HQL_TEMPLATES->{$tmpl_id}{template};
  my $tmpl_data = extract_query_inputs($params);
  my $hql       = HQLTemplater::fill($tmpl, $tmpl_data);
  my @errs      = @HQLTemplater::ERRORS;
  return ($hql, @errs);
}

sub extract_query_inputs {
  my ($params) = @_;
  my $user_inputs = from_json($params->{user_inputs});
  if( $params->{limit}) {
    $user_inputs->{limit} = $params->{limit};
  }
  return $user_inputs;
}

# returns json. so please use this route with ajax query only
sub preview_query {
  my $self = shift;
  my $template_id = $self->param('template_id') || return $self->redirect('select-template');
  my ($query, @errors) = prepare_query($template_id, $self->req->params->to_hash);
  if(@errors) {
    $self->render( json => { error_msg => get_str_from_arr(@errors) });
  }
  else
  {
    $self->render ( json => { query => $query } );
  }

}

# returns a string from the array of strings. Each string separated by newline
sub get_str_from_arr {
  my @str_arr = @_;
  my $str = "";
  if(@str_arr) {
    for my $s (@str_arr) {
      $str .= $s. "\n";
    }
  }
  return $str;
}

# submit the query with any template parameters filled in
sub run_query {
  my $self = shift;

  my $template_id = $self->param('template_id') || return $self->redirect('select-template');
  my $template_name = $self->param('template_name') || $template_id;

  my ($query, @errors) = prepare_query($template_id, $self->req->params->to_hash);

  if(@errors) {
     $self->render( json => { error_msg => get_str_from_arr(@errors) });
     return;
  }

  # unique id to identify the query
  my $query_to_hash = join(" ", $query, $self->session('authenticated'), Time::HiRes::time());
  my $qid = md5_hex($query_to_hash); # query ID

  my $res_dir = "/tmp/hql-webapp/$qid";
  my $full_hql = HQLTemplater::fill_directory_in_template($query, $res_dir);
  $self->app->log->debug("Hive query which will be executed is:" . $full_hql);

  my $job = $self->ua->post(
    "$HIVECLI_URI/create-job" => form => {
      hql          => $full_hql,
      template_id  => $template_id,
      template_name => $template_name,
      queue        => $self->param('queue') // 'default',
      user_name    => $self->session('authenticated'),
      res_dir      => $res_dir,
      res_file     => "$res_dir/output.csv.gz",
      query_id     => $qid,
      notify_email => $self->param('notify_email'),
      notify_url   => $self->req->url->base . "/job/$qid",
    }
  )->res->json;

  $self->render( json => { redirect_url => "/job/$qid"})
}


1;
