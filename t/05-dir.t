#!perl -T

use strict;
use warnings;
use Test::More tests => 85;
use Test::Exception;
use FindBin '$Bin';
use File::Slurp;
use File::Temp qw/tempdir/;
use YAML;

BEGIN {
    use_ok('Config::Tree::Dir');
}

use lib './t';
require 'testlib.pm';

my $conf;

# --- content_as_yaml 1 ---

$conf = Config::Tree::Dir->new(
    path => "$Bin/configs/dir1",
    content_as_yaml => 1,
);

# get_tree_for
my @t;
@t = ($conf->get_tree_for("/"));
is_deeply([$t[0], $t[1]],
          ["/", {i=>1, s=>"foo", a=>[1,2,3], h=>{i=>2,s2=>"bar"}, h2=>{i=>-2,s=>"baz",h=>{i=>7}}, empty=>undef}],
          "get_tree_for 1");
@t = ($conf->get_tree_for("/a"));
is_deeply([$t[0], $t[1]],
          ["/", {i=>1, s=>"foo", a=>[1,2,3], h=>{i=>2,s2=>"bar"}, h2=>{i=>-2,s=>"baz",h=>{i=>7}}, empty=>undef}],
          "get_tree_for 2");
@t = ($conf->get_tree_for("/h"));
is_deeply([$t[0], $t[1]],
          ["/h", {i=>2,s2=>"bar"}],
          "get_tree_for 3");
@t = ($conf->get_tree_for("/h2"));
is_deeply([$t[0], $t[1]],
          ["/h2", {i=>-2,s=>"baz",h=>{i=>7}}],
          "get_tree_for 4");
@t = ($conf->get_tree_for("/h2/h"));
is_deeply([$t[0], $t[1]],
          ["/h2", {i=>-2,s=>"baz",h=>{i=>7}}],
          "get_tree_for 5");
@t = ($conf->get_tree_for("/h/x"));
is_deeply([$t[0], $t[1]],
          ["/h", {i=>2,s2=>"bar"}],
          "get_tree_for 6");

# get
is($conf->get("i"), 1, "get 1");
is($conf->get("/s"), "foo", "get 2");
is_deeply($conf->get("/a"), [1, 2, 3], "get 3a");
is($conf->get("/a/2"), 3, "get 3b");
is($conf->get("/h/i"), 2, "get 4");
is($conf->get("/h/s2"), "bar", "get 5");
is($conf->get("/h2/i"), -2, "get 6");
is($conf->get("/h2/h/i"), 7, "get 7");

ok(!defined($conf->get("/empty")), "get empty");

# unknown
ok(!defined($conf->get("/x/y")), "get unknown");

# cd
$conf->cd("/h"); is($conf->get("i"), 2, "cd 1a");
is($conf->get("../i"), 1, "cd 1b");
$conf->cd(".."); is($conf->get("i"), 1, "cd 2");

# hash prefix
$conf = Config::Tree::Dir->new(
    path => "$Bin/configs/dir2",
    content_as_yaml => 1,
);
is($conf->get("/a/b/c/d/e/f"), 6, 'hash_prefix');



# --- content_as_yaml 0 ---

$conf = Config::Tree::Dir->new(
    path => "$Bin/configs/dir1",
);

# get_tree_for
@t = ($conf->get_tree_for("/"));
is_deeply([$t[0], $t[1]],
          ["/", {i=>1, s=>"foo", a=>'[1, 2, 3]', h=>{i=>2,s2=>"bar"}, h2=>'{i: -2, s: baz, h: {i: 7}}', empty=>1}],
          "get_tree_for 1 (content_as_yaml=0)");
@t = ($conf->get_tree_for("/a"));
is_deeply([$t[0], $t[1]],
          ["/", {i=>1, s=>"foo", a=>'[1, 2, 3]', h=>{i=>2,s2=>"bar"}, h2=>'{i: -2, s: baz, h: {i: 7}}', empty=>1}],
          "get_tree_for 2 (content_as_yaml=0)");
@t = ($conf->get_tree_for("/h"));
is_deeply([$t[0], $t[1]],
          ["/h", {i=>2,s2=>"bar"}],
          "get_tree_for 3 (content_as_yaml=0)");
@t = ($conf->get_tree_for("/h2"));
is_deeply([$t[0], $t[1]],
          ["/", {i=>1, s=>"foo", a=>'[1, 2, 3]', h=>{i=>2,s2=>"bar"}, h2=>'{i: -2, s: baz, h: {i: 7}}', empty=>1}],
          "get_tree_for 4 (content_as_yaml=0)");
@t = ($conf->get_tree_for("/h/x"));
is_deeply([$t[0], $t[1]],
          ["/h", {i=>2,s2=>"bar"}],
          "get_tree_for 5 (content_as_yaml=0)");

# get
is($conf->get("i"), 1, "get 1 (content_as_yaml=0)");
is($conf->get("/s"), "foo", "get 2 (content_as_yaml=0)");
is_deeply($conf->get("/a"), '[1, 2, 3]', "get 3a (content_as_yaml=0)");
ok(!defined($conf->get("/a/2")), "get 3b (content_as_yaml=0)");
is($conf->get("/h/i"), 2, "get 4 (content_as_yaml=0)");
is($conf->get("/h/s2"), "bar", "get 5 (content_as_yaml=0)");

is($conf->get("/empty"), 1, "get empty (content_as_yaml=0)");
# unknown
ok(!defined($conf->get("/x/y")), "get unknown (content_as_yaml=0)");

$conf = Config::Tree::Dir->new(
    path => "$Bin/configs/dir2",
);
is($conf->get("/s"), "hello, world", "get strip newline (content_as_yaml=0)");
is($conf->get("/binary"), "\xff\xfe\n\n\n", "get strip newline binary (content_as_yaml=0)");

# hash prefix
ok(defined($conf->get("/a")), 'hash_prefix a (content_yaml=0)');
ok(defined($conf->get("/a/b")), 'hash_prefix b (content_yaml=0)');
ok(!defined($conf->get("/a/b/c/d/e/f")), 'hash_prefix c (content_yaml=0)');



# --- XXX schema_sub, when_invalid ---



# --- allow_symlink ---

my $dirname = tempdir(CLEANUP=>1);
chdir $dirname;
write_file("a", "foo");
SKIP: {
    eval { symlink ("a", "l") };
    skip "symlink() not supported", 6+3 if $@;

    my $conf0 = Config::Tree::Dir->new(path => $dirname, allow_symlink=>0, ro=>0);
    my $conf1 = Config::Tree::Dir->new(path => $dirname, allow_symlink=>1, ro=>0);
    my $conf2 = Config::Tree::Dir->new(path => $dirname, allow_symlink=>2, ro=>0);

    ok(!defined($conf0->get("l")), "allow_symlink=0, read1");
    is($conf1->get("l"), "foo", "allow_symlink=1, read1");
    is($conf2->get("l"), "foo", "allow_symlink=2, read1");

    # symlinks are ok here because we unlink+create
    $conf0->set("l", "bar");
    is($conf0->get("l"), "bar", "allow_symlink=0, write1");
    $conf1 = Config::Tree::Dir->new(path => $dirname, allow_symlink=>1, ro=>0); # defeat cache
    is($conf1->get("l"), "bar", "allow_symlink=1, write1");
    $conf2 = Config::Tree::Dir->new(path => $dirname, allow_symlink=>2, ro=>0); # defeat cache
    is($conf2->get("l"), "bar", "allow_symlink=2, write1");

    SKIP: {
        skip "must run as root to test allow_different_owner", 3 unless $> == 0;

        write_file("a2", "foo2");
        eval { symlink ("a2", "l2") };
        chown 1000, 1000, "a2";

        $conf0 = Config::Tree::Dir->new(path => $dirname, allow_symlink=>0, allow_different_owner=>1);
        $conf1 = Config::Tree::Dir->new(path => $dirname, allow_symlink=>1, allow_different_owner=>1);
        $conf2 = Config::Tree::Dir->new(path => $dirname, allow_symlink=>2, allow_different_owner=>1);

        ok(!defined($conf0->get("l2")), "allow_symlink=0, read different_owner symlink");
        dies_ok(sub { $conf1->get("l2") }, "allow_symlink=1, read different_owner symlink");
        is($conf2->get("l2"), "foo2", "allow_symlink=2, read different_owner symlink");
    };
};



# --- allow_different_owner ---

SKIP: {
    skip "must run as root to test allow_different_owner", 2 unless $> == 0;
    write_file("d", "baz");
    chown 1000, 1000, "d";
    my $confa = Config::Tree::Dir->new(path=>$dirname, allow_symlink=>2);
    my $confb = Config::Tree::Dir->new(path=>$dirname, allow_symlink=>2, allow_different_owner=>1);
    dies_ok (sub { $confa->get("d") }, "allow_different_owner=0, read1");
    lives_ok(sub { $confb->get("d") }, "allow_different_owner=1, read1");
};



# XXX file_mode, dir_mode



# --- include_file_re, exclude_file_re ---
$dirname = tempdir(CLEANUP=>1);
chdir $dirname;
mkdir("$dirname/a", 0755);
mkdir("$dirname/a/b", 0755);
mkdir("$dirname/a/b/c", 0755);
write_file("$dirname/a/b/c/d", 4);
write_file("$dirname/a/b/c/d~", 4);
write_file("$dirname/a/b/c/#d#", 4);
mkdir("$dirname/a2", 0755);
mkdir("$dirname/a2/b", 0755);
write_file("$dirname/a2/b/c", 3);
$conf = Config::Tree::Dir->new(path => $dirname);
ok(!defined($conf->get("/a/b/c/d~")), "default exclude_file_re 1");
ok(!defined($conf->get("/a/b/c/#d#")), "default exclude_file_re 2");

$conf = Config::Tree::Dir->new(path => $dirname, exclude_file_re=>qr!^c$!);
ok( defined($conf->get("/a/b")), "exclude_file_re 1");
ok(!defined($conf->get("/a/b/c")), "exclude_file_re 2");
ok(!defined($conf->get("/a/b/c/d")), "exclude_file_re 3");
ok( defined($conf->get("/a2")), "exclude_file_re 4");
ok(!defined($conf->get("/a2/b/c")), "exclude_file_re 5");
$conf = Config::Tree::Dir->new(path => $dirname, include_file_re=>qr!^[ab]$!);
ok( defined($conf->get("/a/b")), "include_file_re 1");
ok(!defined($conf->get("/a/b/c")), "include_file_re 2");
ok(!defined($conf->get("/a/b/c/d")), "include_file_re 3");
ok(!defined($conf->get("/a2")), "include_file_re 4");



# --- set & save (content_as_yaml=0) ---

$dirname = tempdir(CLEANUP=>1);
chdir $dirname;
mkdir("$dirname/a", 0755);
mkdir("$dirname/a/b", 0755);
mkdir("$dirname/a/b/c", 0755);
mkdir("$dirname/a/b/c2", 0755);
write_file("$dirname/a/b/c/d", 4);
write_file("$dirname/a/b/c2/d", 4);

$conf = Config::Tree::Dir->new(path => $dirname);
dies_ok(sub { $conf->set("a/b/c/d", 1) }, "default ro");

$conf = Config::Tree::Dir->new(path => $dirname, ro=>1);
dies_ok(sub { $conf->set("a/b/c/d", 1) }, "ro");

$conf = Config::Tree::Dir->new(path => $dirname, ro=>0);
$conf->set("/a/b/c/d", 10);
$conf->set("/a/b/c2", "hello, world\n");
$conf->set("/a2/b/c/d", 11);
$conf = Config::Tree::Dir->new(path => $dirname, ro=>0);
is($conf->get("/a/b/c/d"), 10, "set 1 (content_as_yaml=0)");
is($conf->get("/a/b/c2"), "hello, world", "set 2 (content_as_yaml=0)");
is($conf->get("/a2/b/c/d"), 11, "set 3 (content_as_yaml=0)");

# unset
$conf->set("/a/b/c/d", undef);
ok(defined($conf->get("/a/b/c/d")), "set undef 1a (content_as_yaml=0)");
is($conf->get("/a/b/c/d"), 0, "set undef 1b (content_as_yaml=0)");
ok((-f "$dirname/a/b/c/d"), "set undef 1c (content_as_yaml=0)");
$conf->unset("/a/b/c/d");
ok(!defined($conf->get("/a/b/c/d")), "unset 1a (content_as_yaml=0)");
ok(!(-e "$dirname/a/b/c/d"), "unset 1b (content_as_yaml=0)");
$conf->unset("/a");
ok(!defined($conf->get("/a")), "unset 2a (content_as_yaml=0)");
ok(!(-e "$dirname/a"), "unset 2b (content_as_yaml=0)");



# --- set & save (content_as_yaml=1) ---

$dirname = tempdir(CLEANUP=>1);
chdir $dirname;
mkdir("$dirname/a", 0755);
mkdir("$dirname/a/b", 0755);
mkdir("$dirname/a/b/c", 0755);
mkdir("$dirname/a/b/c2", 0755);
write_file("$dirname/a/b/c/d", '{e: 2}');
write_file("$dirname/a/b/c2/d", 4);
$conf = Config::Tree::Dir->new(path => $dirname, content_as_yaml=>1, ro=>0);

$conf->set("/a/b/c/d", 10);
$conf->set("/a/b/c2", "hello, world\n");
$conf->set("/a2/b/c/d", {f=>3});
$conf = Config::Tree::Dir->new(path => $dirname, content_as_yaml=>1, ro=>0);
is($conf->get("/a/b/c/d"), 10, "set 1");
is($conf->get("/a/b/c2"), "hello, world\n", "set 2");
is($conf->get("/a2/b/c/d/f"), 3, "set 3");

# set undef under content_as_yaml=1
$conf->set("/a/b/c/d", undef);
ok(!defined($conf->get("/a/b/c/d")), "set undef 1a");
ok((-f "$dirname/a/b/c/d"), "set undef 1b");

# cache
my (@t1, @t2, @t3);
@t1= $conf->get_tree_for("/a/b/c", undef);
@t2 = $conf->get_tree_for("/a/b/c", undef);
@t3 = $conf->get_tree_for("/a/b/c/d", undef);
is("@t1", "@t2", "cache 1");
is("@t1", "@t3", "cache 2");
$conf->set("/a/b/c/d", 1);
@t2 = $conf->get_tree_for("/a/b/c", undef);
isnt("@t1", "@t2", "cache 3"); # cache is flushed after set inside cache tree
@t1 = @t2; @t3 = $conf->get_tree_for("/a/b/c", undef);
is("@t2", "@t3", "cache 4"); # cached again
$conf->unset("/a/b/c/d");
@t2 = $conf->get_tree_for("/a/b/c", undef);
isnt("@t1", "@t2", "cache 5"); # cache is flushed after unset inside cache tree
$conf->set("/a2", 3);
@t3 = $conf->get_tree_for("/a/b/c", undef);
is("@t2", "@t3", "cache 6"); # cached is not flushed after set outside cache tree

# must_exist
my $nonexist = 0;
while (-e "/$nonexist") { $nonexist++ }
#lives_ok (sub { $conf = Config::Tree::Dir->new(path=>$nonexist               )->get("a") }, "must_exist 1");
dies_ok  (sub { $conf = Config::Tree::Dir->new(path=>$nonexist, must_exist=>1)->get("a") }, "must_exist 2");

# exclude_path_re, include_path_re is tested by CT::Var
