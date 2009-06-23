#!perl -T

use strict;
use warnings;
use Test::More tests => 11;
use Test::Exception;
use FindBin '$Bin';
#use File::Slurp;
use YAML::XS;

BEGIN {
    use_ok('Config::Tree::YAMLHashFile');
}

use lib './t';
require 'testlib.pm';

my $conf;

$conf = Config::Tree::YAMLHashFile->new(path => "$Bin/configs/yhfile");

# get
is($conf->get("1/i"), 1, "get 1.1");
#print Dump($conf->_tree);

is($conf->get("2/i"), 2, "get 2.1");
is($conf->get("2/h/i"), 5, "get 2.2");
is($conf->get("2/h/s"), "barbaz", "get 2.3");
is($conf->get("2/s"), "foo", "get 2.4");
ok(!defined($conf->get("2/a")), "get 2.5");

is($conf->get("3/h/i"), 55, "get 3.1 (multiple parents, relative path)");

ok(!defined($conf->get("5")), "get 5.1 (recursive)");
ok(!defined($conf->get("6")), "get 6.1 (recursive)");

ok(!defined($conf->get("7")), "get 7.1 (doesn't exist)");

# XXX set, save dies
