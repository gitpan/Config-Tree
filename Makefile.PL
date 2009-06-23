use inc::Module::Install;

name     'Config-Tree';
all_from 'lib/Config/Tree.pm';
author   'Steven Haryanto <stevenharyanto@gmail.com>';
license  'perl';

build_requires 'Test::More';

test_requires 'Test::Exception';
test_requires 'File::Temp';

requires 'Moose';
requires 'Data::PrefixMerge' => '0.05';
requires 'Data::Schema' => '0.06';
requires 'File::Slurp';
requires 'YAML::XS'; # YAML always sucks, it's too strict for CT::CmdLine
requires 'Tie::Cache'; # for CT::Dir

auto_install;

WriteAll;
