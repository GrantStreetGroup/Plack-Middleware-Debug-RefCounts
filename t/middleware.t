use warnings;
use strict;
use Capture::Tiny qw(capture);
use Plack::Test;
use Plack::Builder;
use HTTP::Request::Common;
use Test::More;

my $app = sub {
    return [
        200, [ 'Content-Type' => 'text/html' ], ['<body>Hello World</body>']
    ];
};
$app = builder {
    enable 'Debug', panels => [qw(RefCounts)];
    $app;
};
test_psgi $app, sub {
    my $cb  = shift;
    my ($out, $err, $res) = capture { $cb->(GET '/') };
    is   $out, '', "middleware adds nothing to STDOUT";
    isnt $err, '', "middleware debugs to STDERR";
    is $res->code, 200, 'response status 200';
    like $res->content,
        qr/=== Reference growth counts ===/,
        "HTML contains ref counts panel";
};
done_testing;
