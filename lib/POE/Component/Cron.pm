package POE::Component::Cron;

use 5.008;

our $VERSION = 0.015;

use strict;
use warnings;

use POE;
use DateTime;
use DateTime::Infinite;
use DateTime::Span;
use Time::HiRes qw( time );
our $poe_kernel;

my $Singleton;
my $ID_Sequence = 'a';    # sequence is 'a', 'b', ..., 'z', 'aa', 'ab', ...
my %Schedule_Ticket;      # Hash helps remember alarm id for cancel.

#
# crank up the schedule session
#
sub spawn {
    my $class = shift;
    my %arg   = @_;

    if ( !defined $Singleton ) {

        $Singleton = POE::Session->create(
            inline_states => {
                _start => sub {
                    my ($k) = $_[KERNEL];

                    $k->alias_set( $arg{'Alias'} || "Cron" );
                    $k->sig( 'SHUTDOWN', 'shutdown' );
                },

                schedule     => \&_schedule,
                client_event => \&_client_event,
                cancel       => \&_cancel,

                shutdown => sub {
                    my $k = $_[KERNEL];

                    $k->alarm_remove_all();
                    $k->sig_handled();
                },
            },
        )->ID;
    }
}

#
# schedule the next event
#  ARG0 is a client session,
#  ARG1 is the client event name,
#  ARG2 is a DateTime::Set iterator
#  ARG3 is an schedule ticket
#  ARG4 .. $#_ are arguments to the client event
#
sub _schedule {
    my ( $k, $s, $e, $ds, $tix, @arg ) = @_[ KERNEL, ARG0 .. $#_ ];
    my $n;

    #
    # deal with DateTime::Sets that are finite
    #
    return 1 unless ( $n = $ds->next );

    $Schedule_Ticket{$tix} =
      $k->alarm_set( 'client_event', $n->epoch, $s, $e, $ds, $tix, @arg );
}

#
# handle a client event and schedule the next one
#  ARG0 is a client session,
#  ARG1 is the client event name,
#  ARG2 is a DateTime::Set iterator
#  ARG3 is an schedule ticket
#  ARG4 .. $#_ are arguments to the client event
#
sub _client_event {
    my ( $k, $s, $e, $ds, $tix, @arg ) = @_[ KERNEL, ARG0 .. $#_ ];

    $k->post( $s, $e, @arg );
    _schedule(@_);
}

#
# cancel an alarm
#
sub _cancel {
    my ( $k, $id ) = @_[ KERNEL, ARG0 ];

    $k->alarm_remove($id);
}

#
# takes a POE::Session, an event name and a DateTime::Set
#
sub add {

    my $class  = shift;
    my $ticket = $ID_Sequence++;    # get the next ticket;

    my ( $session, $event, $iterator, @args ) = @_;
    $iterator->isa('DateTime::Set')
      or die __PACKAGE__ . "->add: third arg must be a DateTime::Set";

    spawn unless $Singleton;

    $poe_kernel->post( $poe_kernel->ID_id_to_session($Singleton),
        'schedule', $session, $event, $iterator, $ticket, @args, );
    $Schedule_Ticket{$ticket} = ();

    return bless \$ticket, $class;
}

sub delete {
    my $self   = shift;
    my $ticket = $$self;

    $poe_kernel->post(
        $poe_kernel->ID_id_to_session($Singleton),
        'cancel', $Schedule_Ticket{$ticket},
    );
    delete $Schedule_Ticket{$ticket};

}

sub from_cron {
    my $class = shift;
    my ( $spec, $session, $event, @args ) = @_;

    $class->add(
        $session => $event => DateTime::Event::Cron->from_cron($spec)->iterator(
            span => DateTime::Span->from_datetimes(
                start => DateTime->now( time_zone => 'local' ),
                end   => DateTime::Infinite::Future->new
              ) => @args,
        )
    );
}

*new = \&add;

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

	# crontab DateTime set
	$sched1 = POE::Component::Cron->add(
		$s1 => Tick => DateTime::Event::Cron->from_cron('* * * * *')->iterator(
			span => DateTime::Span->from_datetimes(
				start => DateTime->now,
				end	  => DateTime::Infinite::Future->new
			)
		),
	);

	# random stream of events
	$sched2 = POE::Component::Cron->add(
		$s2 => Tock => DateTime::Event::Random->(
			seconds => 5,
			start	=> DateTime->now,
		)->iterator
	);

	$sched3 = POE::Component::Cron-> from_cron(
	    '* * * * *' => $s2->ID => 'modify'
        );

	# delete some schedule of events
	$sched2->delete();
	

=head1 DESCRIPTION

This component encapsulates a session that sends events to client sessions
on a schedule as defined by a DateTime::Set iterator.	The implementation is 
straight forward if a little limited.

This is early Beta code.  The API is close to jelling.  I'd love to
hear your ideas if you want to share them.

=head1 METHODS

=head2 spawn

No need to call this in normal use, add, new and from_cron all crank
one of these up if it is needed.  Start up a poco::cron. returns a
handle that can then be added to.

=head2 add

Add a set of events to the schedule. the 'session and event name are passed
to POE without even checking to see if they are valid and so have the same 
warnnigs as ->post() itself.

	$cron->add( 
		session,
		'event_name',
		DateTime::Set->iterator,
		@other_args_to_event\@session
	);

=head2 from_cron

Add a schedule using a simple syntax for plain old cron spec.

    POE::Component::Cron-> from_cron('* * * * *' => session => event);

=head2 delete

remove a schedule. you did hang on to the handle returned by add didn't you?


=head1 SEE ALSO

POE, perl, DateTime::Set, DateTime::Event::Cron.

=head1 AUTHOR

Chris Fedde, E<lt>cfedde@cpan.orgE<gt>

=head1 COPYRIGHT AND LICENSE

Copyright (C) 2007 by Chris Fedde

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself, either Perl version 5.8.3 or,
at your option, any later version of Perl 5 you may have available.

=cut
