use strict;
use warnings;
use Test::More;

use Capture::Tiny qw(capture);
use Plack::Test;
use Plack::Middleware::Debug::RefCounts;

sub reset_counts () {
    my ($out, $err) = capture {
        Plack::Middleware::Debug::RefCounts->update_arena_counts;
    };

    fail "Unexpected clearing output $out" if $out;
    # ignore stderr
}

{
    reset_counts;
    my $array_ref = [ qw(1 2 3) ];
    my ($out, $err, $diff_list) = capture {
        Plack::Middleware::Debug::RefCounts->update_arena_counts;
    };
    fail "Unexpected output $out" if $out;

    for my $message_rx (
        qr/Reference growth counts/,
        qr/\+1 \s+ \(diff\) \s+ => \s+ \d+ \s+ \(now\) \s+ => \s+ ARRAY/x,
    ) {
        like $err, $message_rx, "STDERR checks out";
    }

    is scalar(grep { $_->[0] == 1 } values %$diff_list), 1, "No unexpected changes";
}

{
    my $class   = 'Plaque::Mid_Delaware::Budge::Recount';
    my $value   = "4 5 6";

    local $ENV{PLACK_MW_DEBUG_REFCOUNTS_DUMP_RE} = $class;

    reset_counts;
    my $new_ref = bless \$value, $class;

    my ($out, $err, $diff_list) = capture {
        Plack::Middleware::Debug::RefCounts->update_arena_counts
    };
    fail "Unexpected output $out" if $out;

    like $err, qr/$value/, "PLACK_MW_DEBUG_REFCOUNTS_DUMP_RE works";
    # Not checking changes, because Data::Dumper itself creates some
    # references iterating through these
}

done_testing;
