
use strict;
use warnings;

use 5.010_000;

use ExtUtils::MakeMaker 6.30;



my %WriteMakefileArgs = (
  "ABSTRACT" => "a tree-based versatile config handler",
  "AUTHOR" => "Dominik Schulz <dominik.schulz\@gauner.org>",
  "BUILD_REQUIRES" => {
    "FindBin" => 0,
    "Test::MockObject::Universal" => 0,
    "Test::More" => 0,
    "strict" => 0
  },
  "CONFIGURE_REQUIRES" => {
    "ExtUtils::MakeMaker" => "6.30"
  },
  "DISTNAME" => "Config-Tree",
  "EXE_FILES" => [],
  "LICENSE" => "perl",
  "NAME" => "Config::Tree",
  "PREREQ_PM" => {
    "Config::Any" => 0,
    "Config::Tiny" => 0,
    "Data::Dumper" => 0,
    "Data::Tree" => 0,
    "English" => 0,
    "Hash::Merge" => 0,
    "IO::Handle" => 0,
    "Log::Tree::RequiredLogger" => 0,
    "Module::Pluggable::Object" => 0,
    "Moose" => 0,
    "Moose::Role" => 0,
    "Scalar::Util" => 0,
    "Try::Tiny" => 0,
    "autodie" => 0,
    "feature" => 0,
    "mro" => 0,
    "namespace::autoclean" => 0,
    "warnings" => 0
  },
  "VERSION" => "0.22",
  "test" => {
    "TESTS" => "t/*.t"
  }
);


unless ( eval { ExtUtils::MakeMaker->VERSION(6.56) } ) {
  my $br = delete $WriteMakefileArgs{BUILD_REQUIRES};
  my $pp = $WriteMakefileArgs{PREREQ_PM};
  for my $mod ( keys %$br ) {
    if ( exists $pp->{$mod} ) {
      $pp->{$mod} = $br->{$mod} if $br->{$mod} > $pp->{$mod};
    }
    else {
      $pp->{$mod} = $br->{$mod};
    }
  }
}

delete $WriteMakefileArgs{CONFIGURE_REQUIRES}
  unless eval { ExtUtils::MakeMaker->VERSION(6.52) };

WriteMakefile(%WriteMakefileArgs);



