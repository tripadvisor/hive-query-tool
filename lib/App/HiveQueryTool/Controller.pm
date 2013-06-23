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
package App::HiveQueryTool::Controller;
our $VERSION = '0.001';
use Mojo::Base 'Mojolicious::Controller';
use CLASS qw( CLASS $CLASS );
use Scalar::Util qw( reftype );
use Data::Dumper qw( Dumper );

=head1 DESCRIPTION

All controller classes in this app should use this class as their base,
like so:

  use Mojo::Base 'App::HiveQueryTool::Controller';

This way, we can put common functionality in one place, along with any
customizations to the way a 'standard' L<Mojolicious::Controller> does things.

For example, this class overrides the standard constructor, new(), to add
special handling for an init() method in subclasses.

=cut

=head1 METHODS

In addition to methods inherited from L<Mojolicious::Controller>, the
following methods are defined in this class:

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
