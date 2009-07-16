#!perl -T

use Test::More tests => 8;

BEGIN {
	use_ok( 'Config::Tree' );

	use_ok( 'Config::Tree::Base' );
	use_ok( 'Config::Tree::CmdLine' );
	#use_ok( 'Config::Tree::DBI' );
	use_ok( 'Config::Tree::Dir' );
	use_ok( 'Config::Tree::Env' );
	use_ok( 'Config::Tree::File' );
	use_ok( 'Config::Tree::Var' );
	use_ok( 'Config::Tree::YAMLHashDir' );
	#use_ok( 'Config::Tree::YAMLHashFile' );

}

diag( "Testing Config::Tree $Config::Tree::VERSION, Perl $], $^X" );
