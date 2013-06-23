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
package App::HiveQueryTool::HiveCLI::Process;

# ABSTRACT: Track and control a running hive CLI process

use feature ':5.10.1';
use autodie qw(:all);
use Carp;
use Moo;

use AnyEvent;
use AnyEvent::Handle;
use AnyEvent::Util qw(run_cmd portable_pipe);
use Data::Dumper;
use File::Which qw(which);
use Hash::Merge::Simple qw(merge);
use IPC::System::Simple qw(systemx);
use Params::Util qw(_CODELIKE);
use POSIX qw(:signal_h); # signal constants
use Storable qw(dclone);
use String::ShellQuote qw(shell_quote_best_effort);


### public attributes


# constructor parameters
has hive_path     => ( is => 'ro', default => sub { __which_or_die('hive') } );
has user          => ( is => 'ro', default => sub { $ENV{USER} } );
has conf          => ( is => 'ro', default => sub { +{} } );
has env           => ( is => 'ro', default => sub { +{} } );
has hql           => ( is => 'ro', required => 1 );


# user can set a callback for when the command finishes.
has on_finish => ( is => 'rw', isa => sub { _CODELIKE $_[0] }, default => sub {} );


# stuff set while hive runs
has start_time    => ( is => 'ro', default => \&__now );
has end_time      => ( is => 'rwp' );
has cmd           => ( is => 'rwp' );
has history_file  => ( is => 'rwp' );
has pid           => ( is => 'rwp' );
has job_count     => ( is => 'rwp' );
has running_jobs  => ( is => 'rwp', default => sub { 0 } );
has state         => ( is => 'rwp', default => sub { 'ready' } );
has progress_info => ( is => 'rwp', default => sub { +{} } );
has exit_code     => ( is => 'rwp' );
has error_msg     => ( is => 'rwp' );
has error_lines   => ( is => 'rwp', default => sub { +[] } );


### private attributes


has _cmd_cv  => ( is => 'rwp', writer => '_set_cmd_cv' );
has _out_hdl => ( is => 'rwp', writer => '_set_out_hdl' );
has _err_hdl => ( is => 'rwp', writer => '_set_err_hdl' );
has _jobs    => ( is => 'rw', default => sub { +{} } );


### construction


# this is called by Moo after the object is constructed.
# basically, I'm using it to do some sanity checks on the object
sub BUILD {
  my ($self) = @_;

  # make sure the hive command can be found and executed.
  my @err;
  for my $bin ($self->hive_path) {
    -f $bin or do { push @err, "$bin could not be found"; next };
    -x $bin or push @err, "$bin is not executable";
  }
  croak @err if @err;

  my $user     = $self->user;
  my %hiveconf = %{ $self->conf };

  # if a user is specified (and it's different from the current user), use sudo to run hive.
  # this only works if sudoers is set up properly. For example, it includes a line like this:
  # hivequerytool   ALL=(ALL)       NOPASSWD: SETENV: /path/to/hive/home/bin/hive
  my @sudo_cmd =
     ( ! defined $user )     ? () :
     ( $user eq $ENV{USER} ) ? () :
     ( qw(sudo -E -u), $user );

  my @cmd = (
    @sudo_cmd,
    $self->hive_path,
    ( map { ("-hiveconf", "$_=$hiveconf{$_}") } keys %hiveconf ),
    '-e', $self->hql
  );

  $self->_set_cmd(\@cmd);
}


### public methods


# give users a *copy* of the current jobs hash.
# If jobs later become objects we can unpack them as hashes here.
sub jobs_info { dclone shift->_jobs }


# how long the task has been running or took to run
sub run_time {
  my ($self) = @_;
  return ($self->end_time || __now()) - $self->start_time;
}


# info about the currently running process
sub info {
  my ($self) = @_;

  return {
    cmd           => shell_quote_best_effort(@{ $self->cmd }),
    start_time    => $self->start_time,
    end_time      => $self->end_time,
    history_file  => $self->history_file,
    pid           => $self->pid,
    job_count     => $self->job_count,
    running_jobs  => $self->running_jobs,
    state         => $self->state,
    progress_info => $self->progress_info,
    jobs_info     => $self->jobs_info,
    run_time      => $self->run_time,
    user          => $self->user,
    conf          => $self->conf,
    env           => $self->env,
    hql           => $self->hql,
    exit_code     => $self->exit_code,
    error_msg     => $self->error_msg,
  }
}


# wait for the hive process to finish and exit.
sub wait { shift->_cmd_cv->recv }


# execute the job in another process, reading lines in
# from it as it goes and using the contents of those lines to set the various
# attributes/accessors.
sub run {
  my ($self) = @_;

  my @cmd = @{ $self->cmd };

  # prepare an asynch handle for the command's STDOUT
  my ($out_r, $out_w) = portable_pipe;
  my $out_hdl = AnyEvent::Handle->new(
    fh => $out_r,
    on_read => sub {
      shift->push_read( line => sub {
        my ($hdl, $line) = @_;
        $self->_handle_stdout_line($line);
      });
    },
    on_eof => sub {
      shift->destroy;
      close $out_r;
      close $out_w;
    },
    on_error => sub {
      my ($hdl, $fatal, $msg) = @_;
      AE::log error => $msg;
      $hdl->destroy;
      close $out_r;
      close $out_w;
  });
  $self->_set_out_hdl($out_hdl);

  # prepare an asynch handle for the command's STDERR
  my ($err_r, $err_w) = portable_pipe;
  my $err_hdl = AnyEvent::Handle->new(
    fh => $err_r,
    on_read => sub {
      shift->push_read( line => sub {
        my ($hdl, $line) = @_;
        $self->_handle_stderr_line($line);
      });
    },
    on_eof => sub {
      shift->destroy;
      close $err_r;
      close $err_w;
    },
    on_error => sub {
      my ($hdl, $fatal, $msg) = @_;
      AE::log error => $msg;
      $hdl->destroy;
      close $err_r;
      close $err_w;
  });
  $self->_set_err_hdl($err_hdl);

  # run the command in a child process, cv is a condvar.
  my $cmd_pid;
  my $cmd_cv = run_cmd \@cmd,
    close_all => 1,
    '<'  => '/dev/null',
    '>'  => $out_w,
    '2>' => $err_w,
    '$$' => \$cmd_pid;

  $self->_set_state('started');

  # set the callback for when the command exits.
  $cmd_cv->cb( sub { $self->_handle_cmd_done(@_) } );

  $self->_set_pid($cmd_pid);
  $self->_set_cmd_cv($cmd_cv);
}

sub terminate {
  my ($self) = @_;
  $self->send_signal( SIGTERM );
  $self->_set_out_hdl(undef);
  $self->_set_err_hdl(undef);
}

# user can pass in a signal number, but defaults to sigterm.
# as a temporary hack, if the job is running under sudo, try
# to kill it by closing its filehandles
sub send_signal {
  my ($self, $signal) = @_;
  $signal //= 0;
  CORE::kill $signal, $self->pid;
  # TODO: add a timer watcher to check that the process really died
  # and use SIGKILL if it didn't.
}

# returns true if the process is alive
sub is_alive {
  return CORE::kill 0, shift->pid;
}

### private methods


# when the command ends, this method is called.
sub _handle_cmd_done {
  my ($self, $cv) = @_;
  my $retval = $cv->recv;
  say "** Command finished with code $retval";
  $self->_set_exit_code($retval >> 8);
  $self->_set_end_time(__now());
  $self->_set_state('finished');
  # close the file handles we stored earlier
  $self->_set_out_hdl(undef);
  $self->_set_err_hdl(undef);
  $self->on_finish->($self);
}

# The Hive CLI prints out results on STDOUT. This method
# will handle that output.
sub _handle_stdout_line {
  my ($self, $line) = @_;
  say "+ $line";
}


# The Hive CLI prints out status information on STDERR. This
# method parses that output and updates the job attributes.
sub _handle_stderr_line {
  my ($self, $line) = @_;

  state $last_seen_job_id;
  my $nomatch = 0;

  given ($line) {
    when (/Hive history file/) {
      $self->_set_history_file( $line =~ /=\s*(.*)$/ )
    }
    when (/Total MapReduce jobs/) {
      $self->_set_job_count( $line =~ /.*?=\s*(.*)$/ );
    }
    when (/Launching Job/) {
      $self->_set_running_jobs( $self->running_jobs + 1 );
    }
    when (/Starting Job/) {
      # create and update the attributes of the job.
      # later, I might make the hash in jobs an object.
      my ($job_id)  = ($line =~ /.*?=\s*(\w+),/);
      my ($job_url) = ($line =~ /URL\s*=\s*(.*)$/);

      $self->_jobs->{ $job_id }{id}          = $job_id;
      $self->_jobs->{ $job_id }{tracker_url} = $job_url;
      $self->_jobs->{ $job_id }{state}       = 'started';
      $self->_jobs->{ $job_id }{start_time}  = __now();

      $last_seen_job_id = $job_id;
    }
    when (/Kill Command/) {
      my ($kill_cmd) = ($line =~ /=\s*(.*)$/);
      $self->_jobs->{ $last_seen_job_id }{kill_cmd} = $kill_cmd;
    }
    when (/Stage-(\d+)\s+map\s*=\s*(\d+)%,\s*reduce\s*=\s*(\d+)%/) {
      $self->_set_progress_info(
        merge $self->progress_info, { $1 => { stage => $1, map => $2, reduce => $3 } }
      );
    }
    when (/FAILED:/) {
      my ($err_msg) =  ($line =~ /[:]\s*(.*)$/);
      $self->_set_error_msg($err_msg );
    }
    when (/Ended Job = (\w+) (.*)/) {
      my ($job_id) = $1;
      $self->_jobs->{ $job_id }{state}    = 'finished';
      $self->_jobs->{ $job_id }{end_time} = __now();
      $self->_set_running_jobs( $self->running_jobs - 1 );
    }
    when (/^OK/) {
      # no-op, just swallow it
    }
    # nothing else matched? It might be an error. Save it.
    default { say "* $line"; $nomatch = 1; push @{ $self->error_lines }, $line;  }
  };
  say $line unless $nomatch;
}


### private functions


# just a helper function
sub __now { scalar time }


# another helper, finds a command in our $PATH
sub __which_or_die { which $_[0] or croak "Can't find the '$_[0]' command" }



1 && q{ this statement is true }; # truth
__END__

=head1 DESCRIPTION

=head1 SYNOPSIS

=cut


=method new

Constructs a new Hadoop::HiveCLI::Process object.
Currently accepts the following parameters:

=over 4

=item I<cmd>

This should be an I<array> of strings, which make up the command and command-line
arguments for running the hive CLI process.

=back


=method cmd

The command used to start the hive CLI process


=method start_time

The unix timestamp of when the hive process was started


=method state

The current state of the Hive process.
Can be one of I<ready>, I<started>, or I<finished>.


=method history_file

The file where Hive stores the command history of this invocation


=method jobs_info

Returns a hash with info about the jobs run by hive


=method progress_info

Returns a hash with information about Hive's progress running your query.


=method end_time

The unix timestamp of when the hive command finished


=method job_count

The number of hadoop jobs hive plans to run (or will run)


=method running_jobs

How many jobs hive is currently running


=method pid

The pid of the hive process


=method wait

Wait for the process to finish


=method run_time

The time in seconds for which the hive process has been (or had been) running

