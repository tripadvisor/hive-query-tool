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
package App::HiveQueryTool::Controller::Login;
use Mojo::Base 'App::HiveQueryTool::Controller';

sub init {
  my $c = shift;
  # load our LDAP plugin for Mojolicious
  $c->app->plugin('LDAPAuth');
}

# allow the user to login
sub login {
    my $c = shift;

    # Try to figure out where the user was trying to go when they ended up here.
    # If we can't or their dest was the login page, then make the destination
    # the app root page.
    my $dest = $c->param('dest') || $c->session('dest') || $c->req->url || $c->url_for('/');
    $dest = $c->url_for('/')
      if $dest eq $c->url_for('login') or $dest eq $c->url_for('logout');

    # make a hash out of the parameters
    my %p = ((map { $_ => $c->param(["$_"]) } qw(msg user pass)), dest => $dest);

    # just render the login page if it was a get request.
    # You can only auth with post.
    return $c->render('login', %p) if $c->req->method eq 'GET';

    if ($p{user}) {

      # If auth passes, $msg will be empty. If auth fails,
      # there should be something describing why in $msg.
      (my($ok), $p{msg}) = $c->ldap_auth_user($p{user}, $p{pass});

      # if ok, set a cookie and redirect to their destination
      if ($ok) {
        $c->session(authenticated => $p{user});
        $c->redirect_to($p{dest});
      }
    }
    else {
      $p{msg} = "Please enter a username."
    }

    return $c->render('login', %p);
};

sub logout {
    my $c = shift;
    $c->session(authenticated => undef);
    return $c->redirect_to('/');
}

# this should only be called as a bridge-route. It will let the request continue
# only if the user is authenticated. If the user is not, it will redirect them
# to the login page.
sub check_auth {
    my $c = shift;

    # send them to the login page if they were already headed there
    return 1 if $c->req->url eq $c->url_for('login');

     # if they've got the auth cookie, send them to their destination
    if ($c->session('authenticated')) {
        $c->session(dest => undef);
        $c->app->log->debug("auth ok");
        return 1;
    }

    # if not, remember where they were originally headed, and *then* send them there
    $c->session(dest => $c->req->url);
    return $c->redirect_to('login');
}

1;
