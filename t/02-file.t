#!perl -T

use strict;
use warnings;
use Test::More tests => 26;
use Test::Exception;
use FindBin '$Bin';
use File::Slurp;
use File::Temp qw/tempfile/;
use YAML;

BEGIN {
    use_ok('Config::Tree::File');
}

use lib './t';
require 'testlib.pm';

my $conf;

$conf = Config::Tree::File->new(
    path => "$Bin/configs/file1",
    schema => Load(scalar read_file("$Bin/configs/schema1")),
);

# get
is($conf->get("i"), 1, "get 1");
is($conf->get("/s"), "foo", "get 2");
is_deeply($conf->get("/a"), [1, 2, 3], "get 3a");
is($conf->get("/a/2"), 3, "get 3b");
is($conf->get("/h/i"), 2, "get 4");
is($conf->get("/h/s2"), "bar", "get 5");

is($conf->get("/a/../h/./s2"), "bar", "normalize_path");

# unknown
ok(!defined($conf->get("/x/y")), "get unknown");

# cd
$conf->cd("/h"); is($conf->get("i"), 2, "cd 1a");
is($conf->get("../i"), 1, "cd 1b");
$conf->cd(".."); is($conf->get("i"), 1, "cd 2");

# when_invalid
dies_ok(sub {
    Config::Tree::File->new(
        path => "$Bin/configs/file1",
        schema => Load(scalar read_file("$Bin/configs/schema1b")),
    )->get("/i")}, "when_invalid dies"
);
lives_ok(sub {
    Config::Tree::File->new(
        path => "$Bin/configs/file1",
        schema => Load(scalar read_file("$Bin/configs/schema1b")),
        when_invalid => 'warn',
    )->get("/i")}, "when_invalid warn"
);
lives_ok(sub {
    Config::Tree::File->new(
        path => "$Bin/configs/file1",
        schema => Load(scalar read_file("$Bin/configs/schema1b")),
        when_invalid => 'quiet',
    )->get("/i")}, "when_invalid quiet"
);

# set & save
my ($fh, $filename) = tempfile();
my $schema = Load(scalar read_file("$Bin/configs/schema1"));
write_file($filename, read_file("$Bin/configs/file1"));

$conf = Config::Tree::File->new(path => $filename);
dies_ok(sub { $conf->set("i", 1) }, "default ro");

$conf = Config::Tree::File->new(path => $filename, ro=>1);
dies_ok(sub { $conf->set("i", 1) }, "ro");

$conf = Config::Tree::File->new(path => $filename, schema => $schema, ro=>0);
$conf->set("i", 10);
$conf->set("a/3", 4);
$conf->set("h/s2", "baz");
$conf->set("h2/a/0", "foo");
$conf->set("h2/a/0/b/c", "bar");
$conf->set("h2/a/0", "baz");
$conf->save;
my $c = Load(scalar read_file $filename);
is($c->{i}, 10, "set 1");
is($c->{a}[3], 4, "set 2");
is($c->{h}{s2}, "baz", "set 3");
is($c->{h2}{a}{0}, "baz", "set 4");

$conf->unset("/i");
$conf->unset("/h2/a");
$conf->unset("/a/0"); # delete this element
$conf->save;
$c = Load(scalar read_file $filename);
ok(!exists($c->{i}), "unset 1");
ok(!exists($c->{h2}{a}), "unset 2");
is($c->{a}[0], 2, "unset 3");

dies_ok(sub { $conf->set("i", "a"); $conf->save }, "set invalid");
dies_ok(sub { $conf->set("/", "a"); $conf->save }, "set root");

# hash key prefix is tested by CT::Var

# exclude_path_re, include_path_re is tested by CT::Var
