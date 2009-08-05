#!perl -T

use strict;
use warnings;
use Test::More tests => 11;
use Test::Exception;
use FindBin '$Bin';
use File::Slurp;
use YAML::XS;

BEGIN {
    use_ok('Config::Tree::Env');
}

use lib './t';
require 'testlib.pm';

my $conf;
my $schema = Load(scalar read_file("$Bin/configs/schema1"));

# basic stuffs
%ENV = ('CONFIG_I', 1, 'NOPREFIX'=>2, 'CONFIG_J_K'=>4, 'CONFIG_J__K'=>'{l: 3}');
$conf = Config::Tree::Env->new();
is($conf->get("i"), 1, "get 1");
is($conf->get("j_k"), 4, "get 2");
is_deeply($conf->get("/j/k"), {l=>3}, "env_path_separator, yaml");
ok(!defined($conf->get("noprefix")), "env_prefix");

# env_lowercase=0
$conf = Config::Tree::Env->new(env_lowercase=>0);
is($conf->get("I"), 1, "env_lowercase 1");
ok(!defined($conf->get("i")), "env_lowercase 2");

# env_as_yaml=0
$conf = Config::Tree::Env->new(env_as_yaml=>0);
is($conf->get("j/k"), '{l: 3}', "env_lowercase 1");

# schema when loading
%ENV = ('CONFIG_I', 'a');
dies_ok(sub {Config::Tree::CmdLine->new(schema=>$schema)}, "schema when loading");

# conflicting env var
%ENV = ('CONFIG_I', '1', 'CONFIG_i', '2'); dies_ok(sub { Config::Tree::Env->new()->get("i") }, "conflict 1");
# XXX, why in CmdLine it's assumed as conflict?
#%ENV = ('CONFIG_I__J', '1', 'CONFIG_I__K', '2'); dies_ok(sub { Config::Tree::Env->new()->get("i/j") }, "conflict 2");

# autovivify
%ENV = ('CONFIG_A__B__C__D__E__F', 'foo');
$conf = Config::Tree::Env->new();
is($conf->get('a/b/c/d/e/f'), 'foo', 'autovivify hash');

# cd, already tested in CT::Var

# when_invalid, already tested in CT::Var

# save, noop

# hash key prefix, tested in CT::Var

# exclude_path_re, include_path_re is tested by CT::Var
