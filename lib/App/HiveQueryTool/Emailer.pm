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
package App::HiveQueryTool::Emailer;
use Moo;
use MooX::Types::MooseLike::Email qw( :all );
use namespace::sweep;
use Email::Sender;
use Email::Sender::Simple;
use MIME::Entity;
use Params::Util qw( _HASHLIKE );
use Data::Dumper;
use Try::Tiny;


sub send_email {

  my ($params) = _HASHLIKE($_[0]) || @_;
  try {
      my $email = Email::Simple->create(
        header => [
          To      => '"Xavier Q. Ample" <x.ample@example.com>',
          From    => '"Bob Fishman" <orz@example.mil>',
          Subject => "don't forget to *enjoy the sauce*",
        ],
        body => "This message is short, but at least it's cheap.\n",
      );

      Email::Sender::Simple->send( $email );

    die 'Expected email recipient' unless $params->{recipient};

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
