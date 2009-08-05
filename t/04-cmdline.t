#!perl -T

use strict;
use warnings;
use Test::More tests => 51;
use Test::Exception;
use FindBin '$Bin';
use File::Slurp;
use YAML::XS;

BEGIN {
    use_ok('Config::Tree::CmdLine');
}

use lib './t';
require 'testlib.pm';

my $conf;
my $schema = Load(scalar read_file("$Bin/configs/schema1"));

# schema when loading
@ARGV = ('--i', 'a');
dies_ok(sub {Config::Tree::CmdLine->new(schema=>$schema)}, "schema when loading");

# changes to @ARGV
@ARGV = ('--i', '1', '20');
$conf = Config::Tree::CmdLine->new(schema => $schema);
is_deeply(\@ARGV, [20], "changes to \@ARGV");

@ARGV = ('--i', '1', 'SKIPPED', '--s=foo', '--a=[1, 2, 3]', '--h={i: 2, s2: bar}');
$conf = Config::Tree::CmdLine->new(schema => $schema);

# get
is($conf->get("i"), 1, "get 1");
is($conf->get("/s"), "foo", "get 2");
is_deeply($conf->get("/a"), [1, 2, 3], "get 3a");
is($conf->get("/a/2"), 3, "get 3b");
is($conf->get("/h/i"), 2, "get 4");
is($conf->get("/h/s2"), "bar", "get 5");

# unknown
ok(!defined($conf->get("/x/y")), "get unknown");

# conflicting command line
@ARGV = ('--i', '1', '--i', '2'); dies_ok(sub { Config::Tree::CmdLine->new()->get("i") }, "conflict 1");
@ARGV = ('--i/j', '1', '--i/k', '2'); dies_ok(sub { Config::Tree::CmdLine->new()->get("i/j") }, "conflict 2");

# -- as ending list of cmdline options
@ARGV = ('--i=1', '--j=2');
$conf = Config::Tree::CmdLine->new();
is($conf->get('i'), 1, 'ending -- 1a');
is($conf->get('j'), 2, 'ending -- 1b');
@ARGV = ('--i=1', '--', '--j=2');
$conf = Config::Tree::CmdLine->new();
is($conf->get('i'), 1, 'ending -- 2a');
ok(!defined($conf->get('j')), 'ending -- 2b');

# --foo followed by another option becomes --foo=1
@ARGV = ('--i', '--j=2');
$conf = Config::Tree::CmdLine->new();
is($conf->get('i'), 1, 'opt followed by another opt 1');
is($conf->get('j'), 2, 'opt followed by another opt 2');

# --foo at the end becomes --foo=1
@ARGV = ('--i=3', '--j');
$conf = Config::Tree::CmdLine->new();
is($conf->get('i'), 3, 'opt at the end 1');
is($conf->get('j'), 1, 'opt at the end 2');

# boolean --foo does not take an argument
@ARGV = ('--i', '3', '--j', '2');
$conf = Config::Tree::CmdLine->new(schema=>[hash => {keys => {i=>"bool", j=>"int"}}]);
is($conf->get('i'), 1, 'boolean opt does not take argument 1a');
is($conf->get('j'), 2, 'boolean opt does not take argument 1b');
is_deeply(\@ARGV, [3], 'boolean opt does not take argument 1c');
@ARGV = ('--i', '3');
$conf = Config::Tree::CmdLine->new(schema=>[hash => {keys => {i=>"bool", j=>"int"}}]);
is_deeply(\@ARGV, [3], 'boolean opt does not take argument 2a');

# --nofoo
@ARGV = ('--noi', 1, '--noj', 1, '--nok/l', '--k/nol');
$conf = Config::Tree::CmdLine->new(schema=>[hash => {keys => {i=>"bool", noj=>"int",
                                                              nok=>[hash=>{keys=>{l=>"bool"}}],
                                                              k=>[hash=>{keys=>{l=>"bool"}}] }}]);
is($conf->get('i'), 0, 'boolean --noopt for opt 1a');
ok(!defined($conf->get('noi')), 'boolean --noopt for opt 1b');
is($conf->get('noj'), 1, 'boolean --noopt for opt 1c');
ok(!defined($conf->get('j')), 'boolean --noopt for opt 1d');
is($conf->get('nok/l'), 1, 'boolean --noopt for opt 1e');
is($conf->get('k/l'), 0, 'boolean --noopt for opt 1f');
ok(!defined($conf->get('k/nol')), 'boolean --noopt for opt 1g');
is_deeply(\@ARGV, [1], 'boolean --noopt for opt 1h');

# autovivify
@ARGV = ('--a/b/c/d/e/f=foo');
$conf = Config::Tree::CmdLine->new();
is($conf->get('a/b/c/d/e/f'), 'foo', 'autovivify hash');

# when_invalid
dies_ok (sub { @ARGV=('--noexist'); Config::Tree::CmdLine->new(schema=>$schema                       )->get("noexist") }, "when_invalid die");
lives_ok(sub { @ARGV=('--noexist'); Config::Tree::CmdLine->new(schema=>$schema, when_invalid=>"warn" )->get("noexist") }, "when_invalid warn");
lives_ok(sub { @ARGV=('--noexist'); Config::Tree::CmdLine->new(schema=>$schema, when_invalid=>"quiet")->get("noexist") }, "when_invalid quiet");

# special_options
@ARGV = ('--debug');
$conf = Config::Tree::CmdLine->new(special_options=>{ debug=>{sub=>sub{{log_level=>"debug", debugged=>1}}} });
ok(!defined($conf->get("debug")), "special_options 1a");
is($conf->get('log_level'), 'debug', 'special_options 1b');
is($conf->get('debugged'), 1, 'special_options 1c');

# short_options
@ARGV = ('-f', 2);
$conf = Config::Tree::CmdLine->new(short_options=>{f=>'foo'});
is($conf->get('foo'), 2, 'short_options 1');
dies_ok(sub { @ARGV = ('-g', 2); Config::Tree::CmdLine->new(short_options=>{f=>'foo'}) }, "short_options 2");

# stop_after_first_arg
@ARGV = ('--foo', 1, 3, '--bar', 2);
$conf = Config::Tree::CmdLine->new(); # default stop_after_first_arg=0
is_deeply(\@ARGV, [3], "stop_after_first_arg=0 1");
is($conf->get('bar'), 2, "stop_after_first_arg=0 2");
@ARGV = ('--foo', 1, 3, '--bar', 2);
$conf = Config::Tree::CmdLine->new(stop_after_first_arg=>1);
is_deeply(\@ARGV, [3, '--bar', 2], "stop_after_first_arg=1 1");
ok(!defined($conf->get('bar')), "stop_after_first_arg=1 2");

# argv
@ARGV = ('--foo', 1);
$conf = Config::Tree::CmdLine->new(argv=>['--foo', 2]);
is_deeply(\@ARGV, ['--foo', 1], "argv 1");
is_deeply($conf->argv, [], "argv 2");
is_deeply($conf->get('foo'), 2, "argv 3");

# ui.order in key schema
my $schema_ao = [hash=>{keys=>{ foo=>[str=>{"ui.order"=>0}], bar=>[str=>{"ui.order"=>1}], baz=>"str" }}];
@ARGV = (1, '--baz', 3, 2, 4);
$conf = Config::Tree::CmdLine->new(schema=>$schema_ao);
is_deeply($conf->_tree, {foo=>1, bar=>2, baz=>3}, "ui.order 1a");
is_deeply(\@ARGV, [4], "ui.order 1b");
@ARGV = (1, '--baz', 3, 2, 4, '--foo', 11); # foo has conflict
dies_ok(sub { Config::Tree::CmdLine->new(schema=>$schema_ao) }, "ui.order 2");

# cd, already tested in CT::Var

# save, noop

# hash key prefix, tested in CT::Var

# exclude_path_re, include_path_re is tested by CT::Var
