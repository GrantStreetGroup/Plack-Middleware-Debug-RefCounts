# NAME

Plack::Middleware::Debug::RefCounts - reference count debugging for plack apps

# VERSION

version 0.91

# SYNOPSIS

```perl
use Plack::Middleware::Debug::RefCounts;

enable 'Debug', panels => [ 'RefCounts', @any_other_panels ];
```

# DESCRIPTION

This module aims to provide debugging tools to help identify memory leaks.

It uses [Devel::Gladiator](https://metacpan.org/pod/Devel::Gladiator) to compare reference counts at the beginning and end
of requests.

To get the most out of this module, you should:

- 1. Run you application with a single worker process.

    The middleware attempts not to unduly accumulate references. As such, it tracks
    references counts in a simple package variable (["Arena\_Refs"](#arena_refs)), which does not
    scale to multiple processes.

- 2. Identify what's growing unexpectedly, _then_ dive in.

    See the explanation under ["PLACK\_MW\_DEBUG\_REFCOUNTS\_DUMP\_RE"](#plack_mw_debug_refcounts_dump_re).

    Generally, just be aware that you're potentially looking at **A LOT** of
    information, and trying to debug it takes up a lot of resources. System
    errors may occur if you're too aggressive.

- 3. Repeat tests to make sure they are consistently leaking memory.

    Objects can be loaded the first time you load a specific web page, and increase
    memory usage.  The key is that they don't continue to increase memory after
    repeated hits.

    Preloading data prior to forking can help with this problem, but it can be hard
    to capture every single object or singleton that needs to be loaded.

# ENVIRONMENT VARIABLES

## PLACK\_MW\_DEBUG\_REFCOUNTS\_DUMP\_RE

A regex to be matched against changing counts in ["calculate\_arena\_refs"](#calculate_arena_refs).
If a variable's ref type (or class) matches it, the variable will be dumped to
`STDERR`. Only newly-discovered variables are dumped.

**WARNING:** Dumping certain variables may crash your process, because there is
so much to dump. Look at the ref counts first to figure out what you want to
dump, and try to work around any bizarre behaviors.

## PLACK\_MW\_DEBUG\_REFCOUNTS\_ON\_CLEANUP

A boolean, defaulting to `0`.

If the PSGI application supports cleanup and this variable is true, then ref
counting will happen during cleanup. This prevents rendering this refcount
information in the debug panel.

# PACKAGE VARIABLES

## Arena\_Refs

This stores all of the types and memory locations of every variable,
except `SCALAR`s and `REF`s. Data is captured at the end of each dispatch.

**NOTE** this is just a package variable - debugging memory works best with a
single worker anyway.

# METHODS

## run

The standard debug middleware interface. Runs the reference count comparison
as late as possible (ie. during cleanup if supported).

## update\_arena\_counts

```perl
($is_first, \%diff_list) = $self->update_arena_counts;
```

Updates the arena counts and returns a boolean indicating whether this is the
first runthrough and a diff of hashes via ["compare\_arena\_counts"](#compare_arena_counts).

## calculate\_arena\_refs

```perl
\%diff_list = $self->calculate_arena_refs;
```

Walks the arena (of Perl variables) via ["walk\_arena" in Devel::Gladiator](https://metacpan.org/pod/Devel::Gladiator#walk_arena), and
catalogs all non-SCALAR/REFs into ref types and memory locations.  Returns a
diff list hashref.

_After_ the first (initializing) run, if ["PLACK\_MW\_DEBUG\_REFCOUNTS\_DUMP\_RE"](#plack_mw_debug_refcounts_dump_re)
is set, newly discovered matching variables will be dumped to `STDERR`.

## compare\_arena\_counts

```perl
@lines = $self->compare_arena_counts(\%diff_list);
```

Using a diff list from ["calculate\_arena\_refs"](#calculate_arena_refs), this displays the new ref
counts on STDERR, and returns those displayed lines.

Anything listed here has either shrunk or grown the variables within the arena.

Example output:

```perl
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
```

# SEE ALSO

- [Devel::Gladiator](https://metacpan.org/pod/Devel::Gladiator)

    The tool used for leak hunting.

- [Plack::Middleware::Debug](https://metacpan.org/pod/Plack::Middleware::Debug)

    General debugging framework.

- [Plack::Middleware::Debug::Memory](https://metacpan.org/pod/Plack::Middleware::Debug::Memory)

    Monitors RSS, which is not particularly helpful for tracking down memory leaks.

- [Plack::Middleware::MemoryUsage](https://metacpan.org/pod/Plack::Middleware::MemoryUsage)

    As of writing, is broken by a 2015 bug in [B::Size2](https://metacpan.org/pod/B::Size2)
    (and neither module has been updated since 2014).

# AUTHOR

Grant Street Group <developers@grantstreet.com>

# LICENSE AND COPYRIGHT

Copyright 2018 Grant Street Group.

This program is free software; you can redistribute it and/or modify it
under the terms of the the Artistic License (2.0). You may obtain a
copy of the full license at:

[http://www.perlfoundation.org/artistic\_license\_2\_0](http://www.perlfoundation.org/artistic_license_2_0)
