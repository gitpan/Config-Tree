package MyTestNamed;
use Moose;
use Test::MockObject::Universal;
has 'config' => ( 'is' => 'ro', 'isa' => 'Config::Tree', 'lazy' => 1, 'builder' => '_init_mou', );
has 'logger' => ( 'is' => 'ro', 'isa' => 'Log::Tree', 'lazy' => 1, 'builder' => '_init_mou', );
with 'Config::Tree::NamedPlugins';
sub _plugin_base_class { return 'MyTest::Plugin'; }
sub _init_mou { return Test::MockObject::Universal->new(); }
no Moose;
1;
