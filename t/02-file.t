#!perl -T

use strict;
use warnings;
use Test::More tests => 37;
use Test::Exception;
use FindBin '$Bin';
use File::Slurp;
use File::Temp qw/tempfile/;
use YAML::XS;

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

SKIP: {
    ($fh, $filename) = tempfile();
    write_file($filename, "a: 1\n");
    my ($fh2, $filename2) = tempfile();
    unlink $filename2; eval { symlink $filename, $filename2 };
    skip "doesn't support symlink()", 6+3 if $@;

    my $conf0;
    my $conf1 = Config::Tree::File->new(path=>$filename2, allow_symlink=>1);
    my $conf2 = Config::Tree::File->new(path=>$filename2, allow_symlink=>2);

    dies_ok (sub { $conf0 = Config::Tree::File->new(path=>$filename2, allow_symlink=>0); }, "allow_symlink=0, read1");
    lives_ok(sub { $conf1->get("a") }, "allow_symlink=1, read1");
    lives_ok(sub { $conf2->get("a") }, "allow_symlink=2, read1");

    # symlinks are ok here because we unlink+create
    my ($fh3, $filename3) = tempfile();
    write_file($filename3, "a: 1\n");
    my $conf0r = Config::Tree::File->new(path=>$filename3, allow_symlink=>0, ro=>0);
    is($conf0r->get("a"), 1, "allow_symlink=0, write1a");
    unlink $filename2; eval { symlink $filename, $filename3 };
    lives_ok(sub { $conf0r->set("a", 2); $conf0r->save }, "allow_symlink=0, write1b");
    $c = Load(scalar read_file $filename3);
    is($c->{a}, 2, "allow_symlink=0, write1c");

    SKIP: {
        skip "must run as root to test allow_different_owner", 3 unless $> == 0;

        my ($fhb, $filenameb) = tempfile();
        write_file($filenameb, "a: 2\n");
        chown 1000, 1000, $filenameb;
        my ($fh2b, $filename2b) = tempfile();
        unlink $filename2b; eval { symlink $filenameb, $filename2b };

        my $conf0b = Config::Tree::File->new(path=>$filename2b, allow_symlink=>0);
        my $conf1b = Config::Tree::File->new(path=>$filename2b, allow_symlink=>1);
        my $conf2b = Config::Tree::File->new(path=>$filename2b, allow_symlink=>2, allow_different_owner=>1);

        dies_ok (sub { $conf0b->get("a") }, "allow_symlink=0, read2");
        dies_ok (sub { $conf1b->get("a") }, "allow_symlink=1, read2");
        lives_ok(sub { $conf2b->get("a") }, "allow_symlink=2, read2");
    };
};

# XXX file_mode

SKIP: {
    skip "must run as root to test allow_different_owner", 2 unless $> == 0;
    chown 1000, 1000, $filename;
    my $confa = Config::Tree::File->new(path=>$filename);
    my $confb = Config::Tree::File->new(path=>$filename, allow_different_owner=>1);
    dies_ok (sub { $confa->get("a") }, "allow_different_owner=0, read1");
    lives_ok(sub { $confb->get("a") }, "allow_different_owner=1, read1");
};

# hash key prefix is tested by CT::Var

# exclude_path_re, include_path_re is tested by CT::Var
