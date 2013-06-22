package App::HiveQueryTool::Controller;
use Mojo::Base 'Mojolicious::Controller';
use Scalar::Util qw( reftype );
use Data::Dumper;
our $VERSION = '0.001';

=head1 DESCRIPTION

All controller classes in this app should use this class as their base,
like so:

  use Mojo::Base 'App::HiveQueryTool::Controller';

This way, we can put common functionality in one place, along with any
customizations to the way a 'standard' Mojolicious::Controller does things.

For example, this class overrides the standard constructor, new(), to add
special handling for an init() method in subclasses.

=cut

=head1 METHODS

=head2 new

Construct a new Controller object. This gets called automatically by the
Mojolicious framework for each new request. The implementation here
overrides and extends the new() method inherited from Mojolicious::Controller,
doing everything it does, and then doing other things that are custom to this
application.

Subclasses of this class should not override this method without careful
consideration, nor should the new() method in this class be modified without
thorough testing of all its sub-classes.

=cut

sub new {
  my $class = shift;
  my $self = $class->SUPER::new(@_);

  # see documentation on init(), below.
  if (my $init = $self->can('init')) {
    # remember initialization state between calls
    state %initialized;
    $self->$init(@_) unless $initialized{$class};
    $initialized{$class} = 1;
  }

  return $self;
}


sub throw {
print Dumper \@_;
    # throw away the invocant
    shift @_;
    my $caller_pkg = scalar caller;
    # first argument is always the class of the exception
    my $ex_type    = shift @_;
    my $msg        = ! ref $_[0] ? shift @_ : undef;
    # payload can be a data-structure or an object
    my $payload    = ref $_[0] ? shift @_ : undef;
    # if the payload is a hashref and there was no message, see if
    # the hash contains something to use as a message...
    if ( ! defined $msg and reftype( $payload ) eq 'HASH' ) {
        for my $key ( qw( message msg error err ) ) {
            next unless exists $payload->{$key} and defined $payload->{$key};
            $msg = $payload->{$_};
        }
    }
    die "Error: [$ex_type] is not a valid exception type!\n"
        unless $ex_type =~ m{\A [\w]+ (?: :: [\w]+ )* \Z}msx;
    my $ex_pkg = $caller_pkg . "::Exception::" . $ex_type;
    eval qq[
        package $ex_pkg;
        use overload
            '""'     => sub { \$_[0]->{as_string} || __PACKAGE__ },
            'bool'   => sub {1},
            fallback => 1;
        1;
    ] or die "Could not create package [$ex_pkg] for exception type [$ex_type]\n";
    eval "package " . __PACKAGE__ . ";";
    $msg = "" unless defined $msg;
    $payload = {} unless defined $payload;
    $payload->{as_string} = "$ex_pkg: $msg";
    die bless $payload, $ex_pkg;
}

=head2 init()

This class does not have an init() method, but if you define an init() method
in a Controller class that is derived from this one, it will be called as an
object method the first time an object of the derived Controller's class is
instantiated.

Note that it will not be called on subsequent instantiations of that Controller
unless the whole application is reloaded or restarted.

The init() method is intended to perform any initialization that you wish to
happen only once. For example, connecting to a database or loading data from
a file into a variable, or any other things that might be expensive to do
on every request.

The parameters passed to init() are the same as are passed to new(), so this
should include a reference to the Controller object itself, and perhaps
some other things. I will document them here when I know for sure.

From the Controller object (let's call it $c), you can access the rest of the
Mojolicios app that instantiated it, like so: C<<<$c->app>>>

This comes in handy, because before a Controller has been instantiated, there
seems to be no way to get at the app object, nor the app config, routes, etc.
All that is only available after instantiation.

You could concievably override new(), do the initialization there, and store
your DB handles/config data/etc in class variables... but there's a problem
with that: Mojolicious creates a new instance of a Controller every time
it dispatches a request to one. That means it calls the constructor for
every request, and all that initialization work will get redone as well.
Ick.

Granted, this may just be an implementation detail - Perhaps future versions
of Mojolicious will do it differently, but for now this work-around seems to
me to be reasonable safe and sane, and should continue to work even if
future versions of Mojolicious change.

See the code in L<App::HiveQueryTool::Controller::BuildQuery> for
an example on how this can be used.

=cut

1;
