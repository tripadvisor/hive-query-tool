package App::HiveQueryTool::Emailer;
use strict;
use warnings;
use Email::Sender::Simple qw( sendmail );
use MIME::Entity;
use Data::Dumper;
use Try::Tiny;
sub send_email {
  my ($params) = @_;
  try {
    die 'Expected email recipient'
      unless (defined $params->{recipient} && exists $params->{recipient});

    $params->{sender} //= q{"Hive Query Tool" <blackhole@tripadvisor.com>};

    my $email = MIME::Entity->build(
      Type => "multipart/mixed",
      From => $params->{sender},
      To => $params->{recipient},
      Subject => $params->{subject},
    );

    # email body as inline attachment
    $email->attach(
      Type => "text",
      Disposition => 'inline',
      Data => $params->{body}
    );

    if( defined $params->{zip_attachments}) {
      for my $attchmt (@{$params->{zip_attachments}}) {
        $email->attach(
          Path => $attchmt ,
          Type => "application/gzip",
          Disposition => 'attachment'
        );
      }
    }
    print "Attempting to email $params->{recipient}\n";
    sendmail($email);
  }
  catch {
    warn "Error attempting to send email: $_";
  }
}
1;
