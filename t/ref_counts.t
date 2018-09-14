use strict;
use warnings;
use Test::More;

use Capture::Tiny qw(capture_stderr);
use Plack::Test;
use Plack::Middleware::Debug::RefCounts;

{
    Plack::Middleware::Debug::RefCounts->update_arena_counts;
    my $array_ref = [ qw(1 2 3) ];
    my @changes   = Plack::Middleware::Debug::RefCounts->update_arena_counts;
    like(
        shift(@changes),
        qr/Reference growth counts/,
        "growth counts self-identify"
    );

    like(
        shift(@changes),
        qr/^\+1 \s+ \(diff\) \s+ => \s+ \d+ \s+ \(now\) \s+ => \s+ ARRAY$/x,
        "Noted one additional array"
    );

    is scalar(@changes), 0, "No unexpected changes";
}

{
    Plack::Middleware::Debug::RefCounts->update_arena_counts;
    my $class   = 'Plaque::Mid_Delaware::Budge::Recount';
    my $value   = "4 5 6";
    my $new_ref = bless \$value, $class;

    local $ENV{PLACK_MW_DEBUG_REFCOUNTS_DUMP_RE} = $class;
    my ($stderr, @changes) = capture_stderr {
        Plack::Middleware::Debug::RefCounts->update_arena_counts
    };
    like $stderr, qr/$value/, "PLACK_MW_DEBUG_REFCOUNTS_DUMP_RE works";
}

done_testing;
