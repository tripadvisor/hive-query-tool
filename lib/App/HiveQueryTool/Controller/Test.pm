package App::HiveQueryTool::Controller::Test;
use Mojo::Base 'Mojolicious::Controller';

sub index {
    my $c = shift;
    $c->render(text => 'Test: ' . `date`);
}

sub test2 {
    my $c = shift;
    $c->render(text => "Template DBM:" .  $c->app->config('template_dbm'))
};

1;
