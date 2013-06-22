package App::HiveQueryTool::Controller::HiveJob;
use Mojo::Base 'App::HiveQueryTool::Controller';
use Data::Dumper;

# the backend HiveCLI server is running at this URI
our $HIVECLI_URI;

sub init {
    my $c = shift;
    $HIVECLI_URI = $c->app->config('backend_listen');
    $c->app->plugin('RenderFile');
}

sub list_all {
  my $self = shift;
  my $jobs = $self->ua->get( "$HIVECLI_URI/all-jobs")->res->json || {};
  $self->render( 'jobs', jobs_info => $jobs->{jobs_info} || {} );
}

sub list {
  my $self = shift;
  #TODO: make sure back-end will return all jobs if a user is an admin
  my $jobs = $self->ua->post(
    "$HIVECLI_URI/jobs" => form => {
      user_name => $self->session('authenticated')
    }
  )->res->json;

  $self->render( 'jobs', jobs_info => (defined $jobs->{jobs_info}) ? $jobs->{jobs_info}: {});
}

# TODO: make sure this will show any job to any user (so they can pass links around)
sub info {
  my $self = shift;
  my $qid = $self->param('qid');
  my $info = $self->ua->get("$HIVECLI_URI/job/$qid")->res->json;
  # TODO: redirect user to their previous location
  #return $self->redirect_to('/') unless keys %$info;
  my $show_results = -e $info->{req_vars}{res_file};
  $self->render('jobinfo', info => $info, qid => $qid, show_results => $show_results);
}

# TODO: make sure only admins and the job submitter can do this
sub kill {
  my $self = shift;
  my $qid = $self->param('qid');
  # TODO: return user to where they came, output info on success of kill
  $self->ua->get("$HIVECLI_URI/kill-job/$qid")->res->json;
  $self->redirect_to("/job/$qid");
};

# TODO: make sure only admins and the job submitter can do this
sub delete {
  my $self = shift;
  my $qid = $self->param('qid');
  # TODO: return user to where they came (unless they were on the job info
  # page, then return them to the job list) and output info on success of clean
  $self->ua->get("$HIVECLI_URI/clean-job/$qid")->res->json;
  $self->redirect_to('/jobs');
};

sub get_results {
  my $self = shift;
  my $qid = $self->param('qid');
  my $info = $self->ua->get("$HIVECLI_URI/job/$qid")->res->json;
  $self->render_file( filepath => $info->{req_vars}{res_file} );
};

1;
