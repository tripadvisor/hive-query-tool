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
# This file is the main entry point for the HTTP-JSON back-end of the
# Hive Parameterized Query server. This is the server that actually runs
# the Hive Queries submitted by the front-end.
#
# To start this server, simply run this file like so:
#
#   ./hivecli-server.pl
#
# If desired, you can specify the config file to use like so:
#
#   ./hivecli-server.pl /path/to/config
#
# @Author: Stephen R. Scaffidi <sscaffidi@tripadvisor.com>
# @Date: June 2013
#

# pragmas & language extensions
use feature ':5.10.1';
use strict;
use warnings;
use lib 'lib';
use autodie qw(:all);

# general imports
use AnyEvent::HTTPD;
use AnyEvent::Util qw(run_cmd);
use Data::Dumper qw(Dumper);
use DBM::Deep qw();
use IPC::System::Simple qw(capturex);
use MIME::Entity;
use Email::Sender::Simple qw(sendmail);
use File::Spec::Functions qw(updir catfile);
use File::Which qw(which);
use FindBin qw($RealBin);
use JSON qw(to_json);
use List::MoreUtils qw(uniq);
use Storable qw(dclone);
use DateTime;
use YAML::Any;

# local imports
use Package::Alias HiveCLI => 'App::HiveQueryTool::HiveCLI';
use Package::Alias HQTEmailer => 'App::HiveQueryTool::Emailer';

my $CFG_FILE = shift || catfile $RealBin, updir, 'conf', 'hqt_config.yaml';
my $CFG = YAML::Any::LoadFile($CFG_FILE) or die "Couldn't load config from $CFG_FILE\n";

# from email for emails
my $email_from = qq{$CFG->{email_from_name} <$CFG->{email_from_addr}>};

# the HTTPD will listen on this port.
my $LISTEN_PORT    = shift || 9090;
my $CONVERSION_CMD = "$RealBin/convert-hive-output.pl";
my $JOB_INFO_FILE  = $CFG->{jobs_dbm}
    or die "Setting jobs_dbm is not defined in the config\n";

# info about each hive job is put in here where it will be persisted to disk.
my $HIVE_JOB_INFO = DBM::Deep->new(
  file      => $JOB_INFO_FILE,
  locking   => 1,
  autoflush => 1
);

# turn off output buffering
$|++;

# keep all running hivecli processes in here, keyed by PID
my %HIVE_PROCS;


# set up the HiveCLI runner. This runs jobs on the Hive CLI with
# the given configuration and HQL.
my $RUNNER = HiveCLI->new();


# this is a stupid-simple web server running on AnyEvent. I chose it because
# it needs to play nice with Hadoop::HiveCLI which also uses AnyEvent.
# Also, because it's stupid-simple.
my $HTTPD = AnyEvent::HTTPD->new(port => $LISTEN_PORT);

# below all the "routes" are registered for the web site.
# each key is a "route", which is just an HTTP path. When
# a client requests something under this path, the associated
# callback sub is called.
$HTTPD->reg_cb(

  # this route creates a new HiveCLI job.
  '/create-job' => sub {
    # the callback is passed the httpd object (type: AnyEvent::HTTPD) and a
    # request object (type: AnyEvent::HTTPD::Request)
    my ($httpd, $req) = @_;

    # the options we will pass to the HiveCLI runner.
    my %hive_opts;

    my $query_id = $req->parm('query_id') // do {
      return $req->respond( res_json_xx(400, 'query_id parameter required', {} ) );
    };

    my $user_name = $req->parm('user_name') // do {
      return $req->respond( res_json_xx(400, 'user_name parameter required', {} ) );
    };
    # set the user to run the hive command as
    $hive_opts{user} = $user_name;

    my $template_name = $req->parm('template_name') // do {
      return $req->respond( res_json_xx(400, 'template_name parameter required', {} ) );
    };

    $hive_opts{hql} = $req->parm('hql') // do {
      return $req->respond( res_json_xx(400, 'hql parameter required', {} ) );
    };

    # get the queue permissions of the user
    my @queue_perms = capturex(qw(sudo -E -u), $user_name, which('hadoop'), qw(queue -showacls));

    # set the queue if the user specified one
    if ( my $queue = $req->parm('queue') ) {
      if ( ! grep { /^\Q$queue\E\s+.*submit-job/ } @queue_perms ) {
        warn join " ",
          "User [$user_name] does not have permission to submit jobs in queue [$queue].",
          "Not setting mapred.job.queue.name hiveconf param.\n";
      }
      else {
        $hive_opts{conf}{'mapred.job.queue.name'} = $queue;
      }
    }

    # check the query for any statements that set the queue.
    # make sure the user has permission to use all specified queues
    my $set_queue_re = qr{ (?:^|;) \s* set \s+ mapred.job.queue.name \s* = \s* }imsx;
    my @hql_set_queues = $hive_opts{hql} =~ m{ $set_queue_re ([^;\s]+)}gimsx;
    for my $queue ( @hql_set_queues ) {
      if ( ! grep { /^\Q$queue\E\s+.*submit-job/ } @queue_perms ) {
        warn join " ",
          "User [$user_name] does not have permission to submit jobs in queue [$queue]",
          #"which is set in the query. Running job as user [$ENV{USER}] until this is resolved.\n";
          "which is set in the query. Attempting to remove this line from the query...\n";
        #$hive_opts{user} = $ENV{USER};
        #last;
        $hive_opts{hql} =~ s{ $set_queue_re \Q$queue\E \s* ;? }{}gimsx;
      }
    }


    # add an HQL command to change permissions on the output directory
    if ( my $res_dir = $req->parm('res_dir') ) {
        $hive_opts{hql} .= "\n;\n! chmod -R ugo+rwX $res_dir;\n";
    }

    # The HiveCLI process will call this when the process finishes.
    $hive_opts{on_finish} = sub { query_finished(@_, $query_id) };

    # finally, spawn the HiveCLI process
    my $proc = $RUNNER->run( %hive_opts );
    print "Attempting to run command as user [$hive_opts{user}]: ", Dumper $proc->cmd;

    # store the request vars for later reference. using dclone to ensure
    # a deep copy of all the info.
    $HIVE_JOB_INFO->{$query_id}{req_vars} = dclone { $req->vars };

    # store user name in the job info
    $HIVE_JOB_INFO->{$query_id}->{user_name} = $user_name;
    $HIVE_JOB_INFO->{$query_id}->{template_name} = $template_name;

    # NOTE: if we don't need the time zone, we could simply use 'scalar localtime'
    my $cur_date = DateTime->now(time_zone => 'local');
    my $datetime_str = join " ", $cur_date->mdy, $cur_date->hms,
        $cur_date->time_zone_short_name;
    $HIVE_JOB_INFO->{$query_id}->{submit_time} = $datetime_str;

    # save the proc object here so we can get to it later.
    $HIVE_PROCS{$query_id} = $proc;

    # send an email to the user indicating query has started
    my $to_email = $req->parm('notify_email');
    my $query = $req->parm('hql');
    my $job_url = $req->parm('notify_url');
    my $email_body =<<"END_EMAIL_TXT";
Hive Query Tool is executing the query given below:
$query

You will receive an email when the query has completed.
Meanwhile, You can check the status of this job at:
$job_url

END_EMAIL_TXT

    my $email_params = {
      recipient => $to_email,
      subject => 'Hive Query Tool - Your query has started',
      body => $email_body,
    };
    HQTEmailer::send_email($email_params);

    # the response can be one of two different data-structures. Look at the docs for
    # AnyEvent::HTTPD::Request. The res_json function takes care of the details for a
    # normal JSON response here.
    $req->respond(
      res_json( { pid => $proc->pid, status => $proc->state, qid => $query_id } )
    );
  },

  # return the raw data about all jobs (for debugging)
  '/all-jobs-raw' => sub {
    my ($httpd, $req) = @_;
    $req->respond( res_json( { jobs_info => $HIVE_JOB_INFO->export } ) );
  },

  # return a list of *all* jobs (for admins to use)
  '/all-jobs' => sub {
    my ($httpd, $req) = @_;

    my %all_jobs_info;
    while ( my ($id, $info) = each %$HIVE_JOB_INFO ) {
      next unless keys %$info;
      my $status = $info->{DONE} ? 'finished' : 'running';
      $all_jobs_info{$status}{$id} = $info->export;
    }

    $req->respond( res_json( { jobs_info => \%all_jobs_info } ) );
  },

  # return a list of jobs belonging to the given user
  '/jobs' => sub {
    my ($httpd, $req) = @_;
    my $user_name = $req->parm('user_name') // do {
      return $req->respond( res_json_xx(400, 'user_name parameter required', {} ) );
    };

    my %user_job_info;
    while ( my ($id, $info) = each %$HIVE_JOB_INFO ) {
      next unless $info->{user_name};
      if( $info->{user_name} eq $user_name) {
        my $status = $info->{DONE} ? 'finished' : 'running';
        $user_job_info{$status}{$id} = $info->export;
      }
    }
    $req->respond( res_json( { jobs_info => \%user_job_info } ) );
  },

  # return info about a specific job
  '/job' => sub {
    my ($httpd, $req) = @_;
    my $pid = ($req->url->path_segments)[-1];
    my $info = find_proc_info($pid) or do {
      return $req->respond( res_json_xx(404, 'job not found', {} ) );
    };
    $info->{req_vars} = $HIVE_JOB_INFO->{$pid}{req_vars}->export;
    # strip out the chmod hack so users don't see it...
    $info->{hql} =~ s/[;\n]\s*!\s*chmod\s+.*//mg;
    $req->respond( res_json( $info ) );
  },

  # kill a running job
  '/kill-job' => sub {
    my ($httpd, $req) = @_;
    my $query_id = ($req->url->path_segments)[-1];
    my $proc = $HIVE_PROCS{$query_id};
    unless ( $proc ) {
      return $req->respond( res_json_xx(404, 'running job not found', {} ) );
    }
    say "attempting to kill job [$query_id] running under [". $proc->pid . "]";
    $proc->terminate;
    $req->respond( res_json( {} ) );
  },

  # clean a (non-running) job's info from the DBM and from memory
  '/clean-job' => sub {
    my ($httpd, $req) = @_;
    my $query_id = ($req->url->path_segments)[-1];
    # only clean info for jobs whose processes are no longer running.
    if ( $HIVE_PROCS{$query_id} ) {
        return $req->respond( res_json_xx(403, 'can not delete data for active job', {} ) );
    }
    my $job_info = delete $HIVE_JOB_INFO->{$query_id};
    if ( ! $job_info ) {
        return $req->respond( res_json_xx(404, 'job not found', {} ) );
    }
    # just let $job_info go out of scope and it's gone for good.
    $req->respond( res_json( {} ) );
  },

  # default route handler
  '' => sub {
    my ($httpd, $req) = @_;
    $req->respond( res_json_xx(404, 'nothing to see here', {} ) );
  },

);

sub query_finished {
  my ($proc, $query_id) = @_;

  say "job [$query_id] running as pid [" . $proc->pid . "] ended with code [". ($proc->info->{exit_code} // "") . "]";

  # remove the entry for running job info
  delete $HIVE_PROCS{$query_id};

  my $job_info = $HIVE_JOB_INFO->{$query_id};

  # update the job info in the DBM
  $job_info->{info} = dclone $proc->info;

  # if error occurred while executing hive, then send error message
  if( $proc->info->{exit_code}) {

    # sending error email
    my $to_email = $job_info->{req_vars}{notify_email};
    my $job_url = $job_info->{req_vars}{notify_url};
    my $query = $job_info->{req_vars}{hql};
    my $err_msg = $job_info->{info}->{error_msg} // '';
    my $err_lines = join "\n", @{ $proc->error_lines };
    my $email_body =<<"END_EMAIL_TXT";
Your query given below exited with this message below:
$err_msg

The following output may contain more info about the error:
$err_lines

Your query:
$query
END_EMAIL_TXT

    my $email_params = {
      recipient => $to_email,
      subject => 'Hive Query Tool - Your query has errored out',
      body => $email_body,
    };
    HQTEmailer::send_email($email_params);

    # mark the job as completed
    $job_info->{DONE} = 1;
  }
  else {
    # convert the \001-delimited output files to CSV
    my $res_dir  = $job_info->{req_vars}{res_dir} or return;
    my $res_file = $job_info->{req_vars}{res_file} or return;
    say "converting the hive output to a compressed csv...";
    my ( $cv, $pid_ref ) = convert_hive_output($res_dir, $res_file);
    $cv->cb( sub {
      my $retval = $cv->recv;
      my $retcode = $retval >> 8;
      say "hive output conversion process $$pid_ref completed with code $retcode";
      # destroy the condvar we explicitly kept in scope.
      undef $cv;
      $job_info->{conversion_info}{return_code} = $retcode;
      $job_info->{conversion_info}{pid} = $$pid_ref;
      $job_info->{DONE} = 1;
      #send_completion_email($job_info);

      # sending completion email
      my $to_email = $job_info->{req_vars}{notify_email};
      my $job_url = $job_info->{req_vars}{notify_url};
      my $query = $job_info->{req_vars}{hql};
      my $email_body =<<"END_EMAIL_TXT";
Attached is the result of below query
$query

If you want further details on it, please check at:
$job_url
END_EMAIL_TXT

      my $email_params = {
        recipient => $to_email,
        subject => 'Hive Query Tool - Your query has finished',
        body => $email_body,
        zip_attachments => [ $res_file ]
      };
      HQTEmailer::send_email($email_params);

    });
  }

}

# Simply runs an external command that converts the \A-delimited output files
# from the hive job into a compressed CSV file
sub convert_hive_output {
  my ($hive_output_dir, $csv_file) = @_;
  say "converting hive output in $hive_output_dir to $csv_file";
  #return;
  my $cmd_pid;
  my $cmd_cv = run_cmd [ $CONVERSION_CMD, $hive_output_dir, $csv_file ],
    close_all => 1, '$$' => \$cmd_pid;
  return ($cmd_cv, \$cmd_pid)
}


# given a PID, find the freshest source of info on that process and return it as a
# plain hash. Note that it is necessary to "export" from a DBM::Deep hash because it
# is tied with magic that encode_json does *not* like.
sub find_proc_info {
  my ($pid) = @_;
  return unless $pid;
  my $info = exists $HIVE_PROCS{$pid} ? $HIVE_PROCS{$pid}->info
           : exists $HIVE_JOB_INFO->{$pid}{info} ? $HIVE_JOB_INFO->{$pid}{info}
           : return;
  return eval { $info->isa('DBM::Deep::Hash') } ? $info->export : $info;
}


# return a normal 200 OK response with the message body as JSON
sub res_json {
   my ($resp) = @_;
   return { content => [ 'application/json', to_json($resp)."\n" ] }
}


# return a non-normal HTTP response as JSON. Specify the HTTP code, error message, and
# data to return in the message body.
sub res_json_xx {
  my ($code, $msg, $resp) = @_;
  return [$code, $msg, { 'Content-Type' => 'application/json' }, to_json($resp)."\n" ];
}


print "Listening on port $LISTEN_PORT...\n";
$HTTPD->run;
__END__
