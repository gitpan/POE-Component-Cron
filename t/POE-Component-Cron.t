# vim: filetype=perl
#
use warnings;
use strict;

use Test::More qw(no_plan);

use_ok 'POE::Component::Cron';

use DateTime::Event::Cron;
use DateTime::Event::Random;
use POE;

diag('this is going to take about two minutes');

#
# a client session
#
my $s1 = POE::Session->create(
    inline_states => {
        _start => sub {
            $_[KERNEL]->delay( '_die_', 120 );
            $_[KERNEL]->delay( 'Tock',  1 );
        },

        Tick => sub {
            ok 1, 'tick ' . scalar localtime;
        },

        Tock => sub {
            ok 1, 'tock ' . scalar localtime;
            $_[KERNEL]->delay( 'Tock', 10 );
        },

        _die_ => sub {
            ok 1, "_die_";
			$_[KERNEL]->alarm_remove_all();
			$_[KERNEL]->signal($_[KERNEL], 'SHUTDOWN');
        },
    }
);

#
# another client session
#
my $s2 = POE::Session->create(
    inline_states => {
        _start => sub {
            $_[KERNEL]->delay( '_die_', 500 );
			ok 1, '_start';
        },

        update => sub {
            ok 1, 'update ' . scalar localtime;
        },

        report => sub {
            ok 1, 'report ' . scalar localtime;
        },

        _die_ => sub {
            ok 1, "s2 _die_";
			$_[KERNEL]->alarm_remove_all();
        },
    }
);

my $cron = POE::Component::Cron->spawn();

#
# a crontab-ish event stream
#
$cron->add (
	$s1 =>
	Tick =>
	DateTime::Event::Cron->from_cron('* * * * *')->iterator (
		span => DateTime::Span->from_datetimes(
			start => DateTime->now, 
			end   => DateTime::Infinite::Future->new
		)
	),
);

#
# one event stream
#
$cron->add(
    $s2 =>
   	update =>
   	DateTime::Event::Random->new(
        seconds => 5,
        start   => DateTime->now,
    )->iterator,
);

#
# another event stream
#
$cron->add(
    $s2 => report => DateTime::Event::Random->new(
        seconds => 5,
        start   => DateTime->now,
    )->iterator,
);

POE::Kernel->run();

ok( 1, "stopped" );
