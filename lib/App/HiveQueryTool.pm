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
package App::HiveQueryTool;
use Mojo::Base 'Mojolicious';
use CLASS qw( CLASS $CLASS);
use syntax qw( qwa );
use Sys::Hostname qw();

sub startup {
    my $app = shift;

    # add this namespace to search for plugins
    push @{$app->plugins->namespaces}, "${CLASS}::Plugin";

    # load the config
    $app->plugin('YamlConfig', {file => 'conf/hqt_config.yaml'});

    # see the set_secret method defined below
    # sets the secret used to hash cookies and sessions and such.
    $app->set_secret;

    # search for controller classes under this namespace
    $app->routes->namespaces([ "${CLASS}::Controller" ]);

    # set default stash values for each request
    $app->defaults->{layout} ='hqt_layout';
    $app->defaults->{title} = 'The Hive Query Tool';


    ### "routes" connect HTTP request paths to controller actions
    my $r = $app->routes;

    # if using authorization, reset the route object so all requests under
    # the app root go through the auth check (implicit bridge route)
    my $auth_using = lc( $app->config('frontend_auth') || 'none' );
    if ( $auth_using ne 'none' ) {
        $app->log->debug("auth enabled. setting up bridge route for login");
        $r = $app->routes->root->under->to('Login#check_auth');
        $r->route('/login')->via(qwa[GET POST])->to('Login#login'); #a
        $r->any('/logout')->to('Login#logout');
    }

    $r->any('/' => sub { shift->redirect_to('/select-template')});

    $r->any('/select-template')->to('BuildQuery#select_template');
    $r->any('/prep-query'     )->to('BuildQuery#prep_query');
    $r->any('/preview-query'  )->to('BuildQuery#preview_query');
    $r->any('/run-query'      )->to('BuildQuery#run_query');

    $r->any('/jobs'            )->to('HiveJob#list');
    $r->any('/job/:qid'        )->to('HiveJob#info');
    $r->any('/job/:qid/kill'   )->to('HiveJob#kill');
    $r->any('/job/:qid/delete' )->to('HiveJob#delete');
    $r->any('/job/:qid/results')->to('HiveJob#get_results');

    $r->any('/alljobs'         )->to('HiveJob#list_all');
    $r->any('/test'         )->to('Test#index');
}

# This is just to make the secret marginally more secure, if at all.
# Gets secret set in the config file. If it is not set, generates a
# random string. Then appends the hostname to that, and sets it for
# for this instance of the app.
sub set_secret {
   my ($app) = @_;
   my $secret = $app->config('secret') // __gen_random_secret();
   my $hostname = Sys::Hostname::hostname();
   $app->secret( "$hostname: $secret" );
}

# genrate a "reasonably random" string to use as a secret.
sub __gen_random_secret {
    # random length from 17 to 37 chars
    my $len = int rand( 20 ) + 17;
    # choose from an arbitrarily-chosen set of printable ASCII chars
    my @charset = map { chr } ( 0x21 .. 0x7e );
    my $last_idx = $#charset;
    my $secret = join '', map { $charset[ int rand $last_idx ]  } ( 1 .. $len );
    return $secret;
}


1;
