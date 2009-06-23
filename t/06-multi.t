#!perl


use strict;
use warnings;
use Test::More tests => 44;
use Test::Exception;
use Data::Dumper; $Data::Dumper::Indent=1; $Data::Dumper::Terse=1;
use FindBin '$Bin';
use YAML::XS;

BEGIN {
    use_ok('Config::Tree::Multi');
}

use lib './t';
require 'testlib.pm';

# --- __common_prefix ---
ok(!defined(Config::Tree::Multi::__common_prefix()), "__common_prefix 1");
is(Config::Tree::Multi::__common_prefix(''), '', "__common_prefix 2");
is(Config::Tree::Multi::__common_prefix('', 'a'), '', "__common_prefix 3");
is(Config::Tree::Multi::__common_prefix('a', ''), '', "__common_prefix 4");
is(Config::Tree::Multi::__common_prefix('a', 'a'), 'a', "__common_prefix 5");
is(Config::Tree::Multi::__common_prefix('a', 'ab'), 'a', "__common_prefix 6");
is(Config::Tree::Multi::__common_prefix('a', 'ba'), '', "__common_prefix 7");
is(Config::Tree::Multi::__common_prefix('a', 'ab', 'abc'), 'a', "__common_prefix 8");
is(Config::Tree::Multi::__common_prefix('a', 'ab', ''), '', "__common_prefix 9");

my $t1 = {i=>1, s=>"foo", a=>[1,2,3], h=>{i=>2, s2=>"bar"},               s2 =>"a",   s3 =>"b" };
my $t2 = {i=>2, s=>"bar", a=>[2,3,4], h=>{i=>3, s2=>"baz", s3=>"quux"}, '.s2'=>'b', '!s3'=>''  };
my $t3 = {'+i'=>50};

# --- __get_branch ---
is_deeply(Config::Tree::Multi::__get_branch($t1, "/"), $t1, "__get_branch 1");
is_deeply(Config::Tree::Multi::__get_branch($t1, "/i"), $t1->{i}, "__get_branch 2");
is_deeply(Config::Tree::Multi::__get_branch($t1, "/h"), $t1->{h}, "__get_branch 3");
is_deeply(Config::Tree::Multi::__get_branch($t1, "/h/s2"), $t1->{h}{s2}, "__get_branch 4");
ok(!defined(Config::Tree::Multi::__get_branch($t1, "/x")), "__get_branch 5");
ok(!defined(Config::Tree::Multi::__get_branch($t1, "/x/y/z")), "__get_branch 6");

my $conf;

# --- 1, without trees_sub ---

$conf = Config::Tree::Multi->new();
$conf->add_var($t1);
is($conf->get("i"), 1, "get 1 {1}");

# --- 2, without trees_sub ---

$conf = Config::Tree::Multi->new();
$conf->add_var($t1); $conf->add_var($t2);

# get
is($conf->get("i"), 2, "get 1");
is($conf->get("/s"), "bar", "get 2");
is_deeply($conf->get("/a"), [2, 3, 4], "get 3a");
is($conf->get("/a/2"), 4, "get 3b");
is($conf->get("/h/i"), 3, "get 4");
is($conf->get("/h/s2"), "baz", "get 5");
is($conf->get("/h/s3"), "quux", "get 6");
is($conf->get("/s2"), "ab", "get 7");
ok(!defined($conf->get("/s3")), "get 8");

# unknown
ok(!defined($conf->get("/x/y")), "get unknown");

# cd
$conf->cd("/h"); is($conf->get("i"), 3, "cd 1a");
is($conf->get("../i"), 2, "cd 1b");
$conf->cd(".."); is($conf->get("i"), 2, "cd 2");

# --- 3, without trees_sub ---

$conf = Config::Tree::Multi->new();
$conf->add_var($t1); $conf->add_var($t2); $conf->add_var($t3);
is($conf->get("i"), 52, "get 1 {3}");

# --- 3, with dirs ---

$conf = Config::Tree::Multi->new();
$conf->add_var($t1); $conf->add_var($t2);
#print Dumper($t2);
$conf->add_dir("t/configs/dir1");
is($conf->get("i"), 1, "get 1 {3,dir}");
is($conf->get("s2"), "ab", "get 2 {3,dir}");

# schema
my $schema = [hash=>{keys=>{ i=>[int=>{min=>50}] }}];
$conf = Config::Tree::Multi->new();
$conf->add_var($t1); $conf->add_var($t2);
$conf->schema($schema);
dies_ok(sub { $conf->get("i") }, "schema 1");
$conf = Config::Tree::Multi->new();
$conf->add_var($t1); $conf->add_var($t2); $conf->add_var($t3);
$conf->schema($schema);
lives_ok(sub { $conf->get("i") }, "schema 2");

# save & set dies
dies_ok(sub { $conf->set("i", 4) }, "set");
dies_ok(sub { $conf->save }, "save");

# exclude_path_re (include_path_re should run too because implemented in Base, also tested in Var)
$conf = Config::Tree::Multi->new(exclude_path_re=>qr!/i!); $conf->add_var($t1); $conf->add_var($t2);
ok(!defined($conf->get("/i")), "exclude_path_re 1");
ok( defined($conf->get("/h/s2")), "exclude_path_re 2");
ok(!defined($conf->get("/h/i")), "exclude_path_re 3");

# --- with trees_sub, some path not at / ---

my $ct1 = Config::Tree::Var->new(tree=>$t1);
my $ct2 = Config::Tree::Var->new(tree=>$t2);
$conf = Config::Tree::Multi->new(); $conf->trees_sub(sub { return ['/', $ct1], ['/h', $ct2]; });
is($conf->get("i"), 3, "get 1 {2,trees_sub1}");
$conf = Config::Tree::Multi->new(); $conf->trees_sub(sub { return ['/h', $ct1], ['/h', $ct2]; });
$conf->trees_sub(sub { return ['/', $ct1], ['/h', $ct2]; });
is($conf->get("s2"), "baz", "get 1 {2,trees_sub2}");
is($conf->get("s3"), "quux", "get 2 {2,trees_sub2}");

$conf = Config::Tree::Multi->new(); $conf->trees_sub(sub { return ['/h', $ct1, "KEEP"], ['/h', $ct2]; });
is($conf->get("s2"), "bar", "get 1 {2,trees_sub3}");
exit;
is($conf->get("s3"), "quux", "get 2 {2,trees_sub3}");

# XXX --- cache ---
