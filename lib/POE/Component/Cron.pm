package POE::Component::Cron;

our $VERSION = 0.011;

use 5.008;
use strict;
use warnings;

use POE;
use DateTime;
use DateTime::Infinite;
use DateTime::Span;
use Time::HiRes qw( time );
our $poe_kernel;

sub spawn {
    my $class = shift;
    my %arg   = @_;
    my $self  = {};

    $self->{'Cron'} = POE::Session->create(
        inline_states => {
            _start => sub {
                my ($k) = $_[KERNEL];

                $k->alias_set( $arg{'Alias'} || "Cron" );
                $k->sig( 'SHUTDOWN', 'shutdown' );
            },

            schedule     => \&_schedule,
            client_event => \&_client_event,

            shutdown => sub {
                my $k = $_[KERNEL];

                $k->alarm_remove_all();
                $k->sig_handled();
                exit(0);
            },
        },
    );

    return bless $self, $class;
}

#
# schedule an event
#  ARG0 is a client session,
#  ARG1 is the client event name,
#  ARG2 is a DateTime::Set iterator
#  ARG3 .. $#_ are arguments to the client event
#
sub _schedule {
    my ( $k, $s, $e, $ds, @arg ) = @_[ KERNEL, ARG0 .. $#_ ];
    my $n = $ds->next;

    $k->alarm_add( 'client_event', $n->epoch, $s, $e, $ds, @arg );
}

#
# handle a client event and schedule the next one
#  ARG0 is a client session,
#  ARG1 is the client event name,
#  ARG2 is a DateTime::Set iterator
#  ARG3 .. $#_ are arguments to the client event
#
sub _client_event {
    my ( $k, $s, $e, $ds, @arg ) = @_[ KERNEL, ARG0 .. $#_ ];

    $k->post( $s, $e, @arg);
    _schedule(@_);
}

#
# takes a POE::Session, an event name and a DateTime::Set
#
sub add {
    my $self = shift;
    my ( $session, $event, $iterator ) = @_;
    $session->isa('POE::Session')
      or die __PACKAGE__ . "->add: first arg must be a POE::Session";
    $iterator->isa('DateTime::Set')
      or die __PACKAGE__ . "->add: third arg must be a DateTime::Set";

    $poe_kernel->post( $self->{'Cron'}, 'schedule', $session, $event,
        $iterator );
}

1;
__END__

=head1 NAME

POE::Component::Cron - Schedule POE Events using a cron spec

=head1 SYNOPSIS

    use POE::Component::Cron;
    use DateTime::Event::Crontab;
    use DateTime::Event::Random;

    $s1 = POE::Session->create(
        inline_states => {
            _start => sub {
                $_[KERNEL]->delay( _die_, 120 );
              }

              Tick => sub {
                print 'tick ', scalar localtime, "\n";
              },

			  Tock => sub {
			    print 'tock ', scalar localtime, "\n";
			  }

            _die_ => sub {
                print "_die_";
              }
        }
    );

    $cron = POE::Component::Cron->spawn();

    # crontab DateTime set
    $cron->add(
        $s1 => Tick => DateTime::Event::Cron->from_cron('* * * * *')->iterator(
            span => DateTime::Span->from_datetimes(
                start => DateTime->now,
                end   => DateTime::Infinite::Future->new
            )
        ),
    );

    # random stream of events
    $cron->add(
        $s2 => Tock => DateTime::Event::Random->(
            seconds => 5,
            start   => DateTime->now,
        )->iterator
    );


=head1 DESCRIPTION

This compoment encapsulates a session that sends events to client sessions
on a schedule as defined by a DateTime::Set iterator.   The implementation is 
streight forward if a little limited.  As of this writing there is no mechinism for deleting schedules once they have been added.

=head1 METHODS

=head2 spawn

Start up a poco::cron.

=head2 add

Add another schedule of events to the.

=head1 SEE ALSO

POE, perl, DateTime::Event::Cron.

=head1 AUTHOR

Chris Fedde, E<lt>cfedde@littleton.co.usE<gt>

=head1 COPYRIGHT AND LICENSE

Copyright (C) 2004 by Chris Fedde

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself, either Perl version 5.8.3 or,
at your option, any later version of Perl 5 you may have available.

=cut
