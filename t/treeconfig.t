use Test::More qw( no_plan );
use Config::Tree;

BEGIN { use_ok( 'Config::Tree', '@VERSION@' ); }

my $ConfigObject = Config::Tree::->new(
    {
        'locations' => [qw(t/conf/test001.conf)],
        'debug'     => 0,
        'verbose'   => 0,
    }
);
isa_ok $ConfigObject, 'Config::Tree';

my $config_ref = $ConfigObject->config();

my $ref = {
    'config' => {
        'tree' => {
            'example'   => 'Str',
            'sites' => {
                'site1' => {
                    'days' => 'Num',
                    'type'         => 'Str',
                }
            }
        },
    },
};

# Compare reference structure to actual config
sub check_ref {
    my $ref    = shift;
    my $config = shift;
    my $stack  = shift;
    foreach my $key ( keys %{$ref} ) {
        push( @{$stack}, $key );
        if ( ref( $ref->{$key} ) eq 'HASH' ) {
            &check_ref( $ref->{$key}, $config->{$key}, $stack );
        }
        else {
            my $ref_val = $ref->{$key};
            if ( $ref_val eq 'ARRAY' ) {
                ok( ref( $config->{$key} ) eq 'ARRAY', 'Expected Array at ' . join( '-', @{$stack} ) . ' not ' . ref( $config->{$key} ) );
            }
            elsif ( $ref_val eq 'HASH' ) {
                ok( ref( $config->{$key} ) eq 'HASH', 'Hash at ' . join( '-', @{$stack}. ' - Got: '.$config->{$key} ) );
            }
            elsif ( $ref_val eq 'Str' ) {
                ok( $config->{$key} =~ m/\w+/, 'String at ' . join( '-', @{$stack}. ' - Got: '.$config->{$key} ) );
            }
            elsif ( $ref_val eq 'Num' ) {
                ok( $config->{$key} =~ m/[+-]?[\d.,]+/, 'Number at ' . join( '-', @{$stack}. ' - Got: '.$config->{$key} ) );
            }
            else {
                ok( $config->{$key} eq $ref_val, 'String eq at ' . join( '-', @{$stack} . ' Got: ' . $config->{$key} . '. Expected: ' . $ref_val ) );
            }
        }
        pop( @{$stack} );
    }
}

&check_ref( $ref, $config_ref, [] );

# set value in config
$ConfigObject->set( 'Config::Tree::DoMeSo', '123' );
# set value in reference
$ref->{'config'}->{'tree'}->{'domeso'} = '123';
# compare config an reference
&check_ref( $ref, $config_ref, [] );
# get value set before
is( $ConfigObject->get('Config::Tree::DoMeSo'), '123', 'Get value set before' );

# Test set on hash_ref w/o force
$ConfigObject->set( 'Config::Tree::Sites', 'Hello', 0 );
isnt( $ConfigObject->get('Config::Tree::Sites'), 'Hello', 'Should not be able to replace hashref w/ scalar w/o force.' );

# Test set on hash_ref w/ force
$ConfigObject->set( 'Config::Tree::Sites', 'Hallo', 1 );
is( $ConfigObject->get('Config::Tree::Sites'), 'Hallo', 'Should be able to replace hashref w/ scalar w/ force.' );

# Try to read an non-existing key
isnt( $ConfigObject->get('Config::Tree::Some::Made::Up::Key'), '123', 'Should not be able to read an non-existing key.' );

# Make sure test002.conf was not read
isnt( $ConfigObject->get('Should::Not::Exist'), '1', 'Should not be able to read an non-existing key.' );

# Try to read an non-exisiting key w/ default
# case #1: default != undef
is( $ConfigObject->get( 'Config::Tree::Another::Made::Up::Key', { Default => 'HelloWorld' } ), 'HelloWorld', 'Default is returned for non-existing key' );

# case #2: default == undef
is( $ConfigObject->get( 'Config::Tree::Another::Made::Up::Key', ), undef, 'undef is returned for non-existing key' );

# case #3: default == 0
is( $ConfigObject->get( 'Config::Tree::Another::Made::Up::Key', { Default => 0 } ), 0, 'Default is returned for non-existing key' );

$ConfigObject->reset_config();
ok( !keys %{ $ConfigObject->config() }, 'Test that config is empty after reset' );

$ConfigObject = undef;
