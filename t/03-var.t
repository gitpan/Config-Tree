#!perl -T

use strict;
use warnings;
use Test::More tests => 23;
use Test::Exception;
use FindBin '$Bin';
use File::Slurp;
use YAML::XS;

BEGIN {
    use_ok('Config::Tree::Var');
}

use lib './t';
require 'testlib.pm';

my $conf;

my $tree = {i=>1, s=>"foo", a=>[1,2,3], h=>{i=>2, s2=>"bar"}};

$conf = Config::Tree::Var->new(
    tree => $tree,
    schema => Load(scalar read_file("$Bin/configs/schema1")),
);

# get
is($conf->get("i"), 1, "get 1");
is($conf->get("/s"), "foo", "get 2");
is_deeply($conf->get("/a"), [1, 2, 3], "get 3a");
is($conf->get("/a/2"), 3, "get 3b");
is($conf->get("/h/i"), 2, "get 4");
is($conf->get("/h/s2"), "bar", "get 5");

# unknown
ok(!defined($conf->get("/x/y")), "get unknown");

# cd
$conf->cd("/h"); is($conf->get("i"), 2, "cd 1a");
is($conf->get("../i"), 1, "cd 1b");
$conf->cd(".."); is($conf->get("i"), 1, "cd 2");

# when_invalid
dies_ok(sub {
    Config::Tree::Var->new(
        tree => $tree,
        schema => Load(scalar read_file("$Bin/configs/schema1b")),
    )->get("/i")}, "when_invalid dies"
);
lives_ok(sub {
    Config::Tree::Var->new(
        tree => $tree,
        schema => Load(scalar read_file("$Bin/configs/schema1b")),
        when_invalid => 'warn',
    )->get("/i")}, "when_invalid warn"
);
lives_ok(sub {
    Config::Tree::Var->new(
        tree => $tree,
        schema => Load(scalar read_file("$Bin/configs/schema1b")),
        when_invalid => 'quiet',
    )->get("/i")}, "when_invalid quiet"
);

# save, noop

# hash key prefix
$tree = {a=>{'*b'=>{'+c'=>{'.d'=>{'-e'=>{'!f'=>6}}}}}, a2=>{b=>{c=>3}}};
$conf = Config::Tree::Var->new(
    tree => $tree,
);
is($conf->get("/a/b/c/d/e/f"), 6, "hash key prefix");

# exclude_path_re
$conf = Config::Tree::Var->new(tree => $tree, exclude_path_re=>qr!/c!);
ok( defined($conf->get("/a/b")), "exclude_path_re 1");
ok(!defined($conf->get("/a/b/c")), "exclude_path_re 2");
ok(!defined($conf->get("/a/b/c/d")), "exclude_path_re 3");
ok( defined($conf->get("/a2")), "exclude_path_re 4");
ok(!defined($conf->get("/a2/b/c")), "exclude_path_re 5");

# include_path_re
$conf = Config::Tree::Var->new(tree => $tree, include_path_re=>qr!^/a(?:\z|/)!);
ok( defined($conf->get("/a/b/c/d/e/f")), "include_path_re 1");
ok(!defined($conf->get("/a2")), "include_path_re 2");
ok(!defined($conf->get("/a2/b")), "include_path_re 3");
