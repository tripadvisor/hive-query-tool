package App::HiveQueryTool::Plugin::LDAPAuth;
use Mojo::Base 'Mojolicious::Plugin';
use Params::Util qw(_HASHLIKE);
use Hash::Merge::Simple qw(merge);
use Net::LDAP qw(LDAP_SUCCESS);
use Net::LDAP::Message;

our $VERSION = "0.1";

# register the plugin
sub register {
  my ($plugin, $app, $conf) = @_;

  # add a helper method for the app controllers
  $app->helper( ldap_auth_user => sub { ldap_auth_user(@_) });

  return 1;
}


# connect to LDAP and make sure it's *secure*
# on success, return the ldap object. on failure,
# return false.
sub ldap_connect {
    my $c = shift; # current controller

    # make sure the config is not empty
    my $cfg = $c->config('ldap_config') or do {
        warn "ldap config info is missing";
        return;
    };

    # if not defined, set to enabled.
    $cfg->{enable_tls} //= 1;

    my $ldap = Net::LDAP->new( $cfg->{server_url} ) or do {
        warn "couldn't connect to ldap server at URL: $cfg->{server_url}";
        return;
    };

    # bypass start_tls if not enabled.
    return $ldap unless $cfg->{enable_tls};

    ### make sure the LDAP object is connected to the server securely!
    $c->app->log->debug("Starting TLS for LDAP connection to $cfg->{server_url}");

    # the capath param for start_tls (below) needs a trailing
    # slash for whatever reason. This doesn't seem to be in
    # Net::LDAP's docs.
    my $capath = $cfg->{cacert_dir} || '';
    $capath =~ s{([^/])$}{$1/} if $capath;

    my $status = $ldap->start_tls(
        # by default, don't verify the server's cert
        # this is just for convenience - not every workstation
        # here has their root-certs configured properly.
        verify => $cfg->{verify_cert} || 'none',
        # only pass this option if it's not empty.
        ($capath ? (capath => $capath) : ()),
    );

    if ( $status->code != LDAP_SUCCESS ) {
        warn "ldap start_tls failed with code: " . $status->code;
        return;
    }

    return $ldap;
}


# given a username and password, attempt to authenticate against LDAP
# for now, returns a boolean status and an optional message (currently
# is always for an error condition)
sub ldap_auth_user {
  my ($c, $user, $pass) = @_;

  my $ldap = ldap_connect($c)
    or return (undef, "Error: Cannot connect to ldap server");

  my $ldap_dn = "uid=$user," . $c->config->{ldap_config}{user_base};
  my $status = $ldap->bind( $ldap_dn, password => $pass);

  if( $status->code != LDAP_SUCCESS) {
        return (undef, "User name or password incorrect");
  }

  return (1, "")
}


1;
