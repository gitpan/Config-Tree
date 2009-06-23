#!perl -T

use strict;
use warnings;
use Test::More tests => 11;
use FindBin '$Bin';
use File::Slurp;
use YAML::XS;

BEGIN {
    use_ok('Config::Tree::Base');
}

use lib './t';
require 'testlib.pm';

my $conf = Config::Tree::Base->new();

# cd
is($conf->getcwd, "/", "getcwd 1");
$conf->cd("a/b"); is($conf->getcwd, "/a/b", "cd 1");
$conf->cd("../c"); is($conf->getcwd, "/a/c", "cd 2");
# pushd & popd
$conf->pushd("/a/b2"); is($conf->getcwd, "/a/b2", "pushd 1");
$conf->pushd(".."); is($conf->getcwd, "/a", "pushd 2");
$conf->popd; is($conf->getcwd, "/a/b2", "popd 1");
$conf->popd; is($conf->getcwd, "/a/c", "popd 2");
# normalize_path
is($conf->normalize_path("a"), "/a/c/a", "normalize_path 1");
is($conf->normalize_path("/b/c"), "/b/c", "normalize_path 2");
is($conf->normalize_path(".."), "/a", "normalize_path 3");
