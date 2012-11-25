#!perl -T

use Test::More tests => 5;

BEGIN {
    use_ok( 'Config::Tree::LazyConfig' ) || print "Bail out!
";
    use_ok( 'Config::Tree::NamedPlugins' ) || print "Bail out!
";
    use_ok( 'Config::Tree::OrderedPlugins' ) || print "Bail out!
";
    use_ok( 'Config::Tree::RequiredConfig' ) || print "Bail out!
";
    use_ok( 'Config::Tree' ) || print "Bail out!
";
}

diag( "Testing Config::Tree $Config::Tree::VERSION, Perl $], $^X" );
