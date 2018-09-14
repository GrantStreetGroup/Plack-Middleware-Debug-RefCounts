package Plack::Middleware::Debug::RefCounts;

our $AUTHORITY = 'cpan:GSG';
our $VERSION   = '0.90';

use v5.10.1;
use strict;
use warnings;

use parent 'Plack::Middleware::Debug::Base';
use Data::Dumper;
use Devel::Gladiator;
use Env          qw($PLACK_MW_DEBUG_REFCOUNTS_DUMP_RE);
use Scalar::Util qw( refaddr );

use namespace::clean;  # don't export the above

=encoding utf8

=head1 NAME

Plack::Middleware::Debug::RefCounts - reference count debugging for plack apps

=head1 VERSION

version 0.90

=head1 SYNOPSIS

    use Plack::Middleware::Debug::RefCounts;

    enable 'Debug', panels => [ 'RefCounts', @any_other_panels ];

=head1 DESCRIPTION

This module aims to provide debugging tools to help identify memory leaks.

It uses L<Devel::Gladiator> to compare reference counts at the beginning and end
of requests.

To get the most out of this module, you should:

=over

=item 1. Run you application with a single worker process.

The middleware attempts not to unduly accumulate references. As such, it tracks
references counts in a simple package variable (L</Arena_Refs>), which does not
scale to multiple processes.

=item 2. Identify what's growing unexpectedly, I<then> dive in.

See the explanation under L<PLACK_MW_DEBUG_REFCOUNTS_DUMP_RE>.

Generally, just be aware that you're potentially looking at B<A LOT> of
information, and trying to debug it takes up a lot of resources. System
errors may occur if you're too aggressive.

=back

=head1 ENVIRONMENT VARIABLES

=head2 PLACK_MW_DEBUG_REFCOUNTS_DUMP_RE

A regex to be matched against changing counts in L</calculate_arena_refs>.
If a variable's ref type (or class) matches it, the variable will be dumped to
C<STDERR>. Only newly-discovered variables are dumped.

B<WARNING:> Dumping certain variables may crash your process, because there is
so much to dump. Look at the ref counts first to figure out what you want to
dump, and try to work around any bizarre behaviors.

=head1 PACKAGE VARIABLES

=head2 Arena_Refs

This stores all of the types and memory locations of every variable,
except C<SCALAR>s and C<REF>s. Data is captured at the end of each dispatch.

B<NOTE> this is just a package variable - debugging memory works best with a
single worker anyway.

=cut

our $Arena_Refs = [];

=head1 METHODS

=head2 run

The standard debug middleware interface. Runs the reference count comparison
as late as possible (ie. during cleanup if supported).

=cut

sub run {
    my ($self, $env, $panel) = @_;

    return Plack::Util::response_cb( $self->app->($env), sub {
        if ($env->{'psgix.cleanup'} ) {
            push @{ $env->{'psgix.cleanup.handlers'} }, sub {
                $panel->content(
                    $self->render_lines( [ $self->update_arena_counts() ] )
                );
            };
        }
        else {
            $panel->content(
                $self->render_lines( [ $self->update_arena_counts() ] )
            );
        }

    } );
}

=head2 update_arena_counts

    my @diff_lines = $self->update_arena_counts;

Updates the arena counts and returns the lines via L</compare_arena_counts>.

=cut

sub update_arena_counts {
    my $self = shift;
    my $ref_a = $Arena_Refs;
    ($Arena_Refs, my $diff_list) = $self->calculate_arena_refs($ref_a);

    if ($ref_a) { return $self->compare_arena_counts($diff_list) }

    return;
}

=head2 calculate_arena_refs

    (\@ref_b, \%diff_list) = $self->calculate_arena_refs(\@ref_a);

Walks the arena (of Perl variables) via L<Devel::Gladiator/walk_arena>, and
catalogs all non-SCALAR/REFs into ref types and memory locations.
Accepts an old ref list (from a previous call) as input,
and returns both a new ref list and diff list.

I<After> the first (initializing) run, if L</PLACK_MW_DEBUG_REFCOUNTS_DUMP_RE>
is set, newly discovered matching variables will be dumped to C<STDERR>.

=cut

sub calculate_arena_refs {
    my $self    = shift;
    my @ref_a   = @{ shift // [] };
    my $dump_re = $PLACK_MW_DEBUG_REFCOUNTS_DUMP_RE;

    $dump_re = undef unless @ref_a;  # don't dump the first run

    # refs start out "deleted", until they are found again
    my %ref_list = map { $_ => -1 } @ref_a;

    # This creates string address lists of all of the existing arena variables.
    # This is much cleaner and memory-friendly than storing real refs.
    my $all = Devel::Gladiator::walk_arena();
    my @ref_b;
    foreach my $it (@$all) {
        my $type = ref $it;

        # There are so many of these that even cataloging the memory addresses
        # of these is enough to overload memory footprint.
        next if $type eq 'SCALAR' || $type eq 'REF';

        # Get the pointer address
        my $addr = sprintf '%x', refaddr $it;
        my $id   = "$type/$addr";

        unless ($ref_list{$id}) {
            # New ref
            if ($dump_re && $type =~ /$dump_re/) {
                # Sometimes this dies. If so, just move on to the next one.
                eval {
                    local $Data::Dumper::Maxdepth = 2;
                    print STDERR "+$id = ".Dumper($it);
                };
                if ($@) {
                    print STDERR "+$id > ERROR: $@";
                }
            }
        }
        # either equalize to 0 for an existing ref, or go to 1 for a new one
        $ref_list{$id}++;

        push @ref_b, $id;

        $it = undef;
    }
    $all = undef;

    my %diff_list;
    foreach my $id (keys %ref_list) {
        my ($type, $addr) = split m!/!, $id, 2;
        my $cmp = $ref_list{$id};

        $diff_list{$type}   //= [0,0,0];
        $diff_list{$type}[0] += $cmp;              # diff
        $diff_list{$type}[1]++ unless $cmp ==  1;  # count_a
        $diff_list{$type}[2]++ unless $cmp == -1;  # count_b

        # Also dump the removed refs, if requested
        if ($dump_re && $type =~ /$dump_re/ && $cmp == -1) {
            say STDERR "-$id";
        }
    }

    say STDERR '' if $dump_re;

    return \@ref_b, \%diff_list;
}

=head2 compare_arena_counts

    $self->compare_arena_counts(\%diff_list);

Using a diff list from L</calculate_arena_refs>, this displays the new ref
counts, and returns those displayed lines.

Anything listed here has either shrunk or grown the variables within the arena.

Example output:

    === Reference growth counts ===
    +4    (diff) =>       4 (now) => Class::MOP::Class::Immutable::Moose::Meta::Class
    +1    (diff) =>       1 (now) => Class::MOP::Method::Wrapped
    +12   (diff) =>      19 (now) => DBD::mysql::st_mem
    +24   (diff) =>      38 (now) => DBI::st
    +1    (diff) =>       1 (now) => Data::Visitor::Callback
    +4    (diff) =>       4 (now) => DateTime
    +1    (diff) =>       1 (now) => DateTime::TimeZone::America::New_York
    +1    (diff) =>       1 (now) => Devel::StackTrace
    +1    (diff) =>       1 (now) => FCGI
    +3    (diff) =>       3 (now) => FCGI::Stream

=cut

sub compare_arena_counts {
    my ($self, $diff_list) = @_;

    my @lines = ( "=== Reference growth counts ===\n" );

    foreach my $key (sort keys %$diff_list) {
        my ($diff, $count_a, $count_b) = @{ $diff_list->{$key} };

        next unless $diff;
        push @lines, sprintf "%+-5d (diff) => %7d (now) => %-s\n", $diff, $count_b, $key;
    }

    print STDERR $_ for @lines, "\n";
    return @lines;
}

=head1 SEE ALSO

=over

=item L<Devel::Gladiator>

The tool used for leak hunting.

=item L<Plack::Middleware::Debug>

General debugging framework.

=item L<Plack::Middleware::Debug::Memory>

Monitors RSS, which is not particularly helpful for tracking down memory leaks.

=item L<Plack::Middleware::MemoryUsage>

As of writing, is broken by a 2015 bug in L<B::Size2>
(and neither module has been updated since 2014).

=back

=head1 AUTHOR

Grant Street Group <developers@grantstreet.com>

=head1 LICENSE AND COPYRIGHT

Copyright 2018 Grant Street Group.

This program is free software; you can redistribute it and/or modify it
under the terms of the the Artistic License (2.0). You may obtain a
copy of the full license at:

L<http://www.perlfoundation.org/artistic_license_2_0>

=cut

1;
