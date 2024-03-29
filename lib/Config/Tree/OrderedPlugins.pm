package Config::Tree::OrderedPlugins;
{
  $Config::Tree::OrderedPlugins::VERSION = '0.22';
}
BEGIN {
  $Config::Tree::OrderedPlugins::AUTHORITY = 'cpan:TEX';
}
# ABSTRACT: a role to provide handling of ordered plugins

use 5.010_000;
use mro 'c3';
use feature ':5.10';

use Moose::Role;
use namespace::autoclean;

# use IO::Handle;
# use autodie;
# use MooseX::Params::Validate;
# use Carp;
use English qw( -no_match_vars );
use Try::Tiny;
use Module::Pluggable::Object;

# extends ...
# has ...
has '_finder' => (
    'is'       => 'rw',
    'isa'      => 'Module::Pluggable::Object',
    'lazy'     => 1,
    'builder'  => '_init_finder',
    'accessor' => 'finder',
);

has '_plugins' => (
    'is'       => 'rw',
    'isa'      => 'ArrayRef',
    'lazy'     => 1,
    'builder'  => '_init_plugins',
    'accessor' => 'plugins',
);

has '_finder_search_path' => (
    'is'      => 'rw',
    'isa'     => 'ArrayRef[Str]',
    'lazy'    => 1,
    'builder' => '_init_finder_search_path',
);

# with ...
with qw(Config::Tree::RequiredConfig Log::Tree::RequiredLogger);
# initializers ...
sub _init_finder_search_path {
    my $self = shift;

    return [$self->_plugin_base_class()];
}

sub _init_finder {
    my $self = shift;

    # The finder is the class that finds our available plugins
    my $Finder = Module::Pluggable::Object::->new( 'search_path' => $self->_finder_search_path() );

    return $Finder;
} ## end sub _init_finder

sub _init_plugins {
    my $self = shift;

    # Allow the plugins to be sorted by prio in the config with the Priority
    # key in each plugin section. Why priorities? It may make sense or even
    # be a strict requirement to run some plugins before or after
    # another one.
    my $order_ref = {};

    PLUGIN: foreach my $plugin_name ( $self->finder()->plugins() ) {
        ## no critic (ProhibitStringyEval)
        my $eval_status = eval "require $plugin_name;";
        ## use critic
        if ( !$eval_status ) {
            $self->logger()->log( message => 'Failed to require ' . $plugin_name . ': ' . $EVAL_ERROR, level => 'warning', );
            next;
        }
        my $arg_ref = $self->config()->get($plugin_name);
        $arg_ref->{'logger'} = $self->logger();
        $arg_ref->{'config'} = $self->config();
        $arg_ref->{'parent'} = $self;
        $arg_ref->{'name'} ||= $plugin_name;
        if ( $arg_ref->{'disabled'} ) {
            $self->logger()->log( message => 'Skipping disabled plugin: ' . $plugin_name, level => 'debug', );
            next PLUGIN;
        }
        try {
            my $Plugin = $plugin_name->new($arg_ref);
            my $prio   = $Plugin->priority();

            # disabled/abstract plugins will set a prio of 0
            if ( $prio > 0 ) {
                push( @{ $order_ref->{$prio} }, $Plugin );
                $self->logger()->log( message => 'Loaded plugin '.ref($Plugin).' w/ priority '.$prio, level => 'debug', );
            } else {
                $self->logger()->log( message => 'Skipped loaded plugin '.ref($Plugin).' w/ priority '.$prio, level => 'debug', );
            }
        } ## end try
        catch {
            $self->logger()->log( message => 'Failed to initialize plugin ' . $plugin_name . ' w/ error: ' . $_, level => 'warning', );
        };
    } ## end foreach my $plugin_name ( $self...)

    my @plugins = ();

    # this basically merges the pre-sorted sub-arrays (which, if you follow
    # my advice, should each contain only one element ... but we must
    # plan for the unexptected, of course)
    foreach my $prio ( sort { $a <=> $b } keys %{$order_ref} ) {
        #$self->logger()->log( message => 'Adding Plugins '.join(',',map { ref($_) } @{$order_ref->{$prio}}).' w/ prio '.$prio, level => 'debug', );
        push( @plugins, @{ $order_ref->{$prio} } );
    }

    return \@plugins;
} ## end sub _init_plugins

# requires ...
requires qw(_plugin_base_class);

# your code here ...

no Moose::Role;

1;

__END__

=pod

=encoding utf-8

=head1 NAME

Config::Tree::OrderedPlugins - a role to provide handling of ordered plugins

=head1 SYNOPSIS

    use Moose;
    with 'Config::Tree::OrderedPlugins';

=head1 DESCRIPTION

This Moose role provides an plugin hanlder for plugins ordered by priority.

Upon access to the plugins() method this role will search
for all plugins within the search path defined by _plugin_base_class().

It will also require an Config::Tree instance and a Log::Tree instance.

=head1 NAME

Config::Tree::OrderedPlugins - This role provides an handler for ordered plugins.

=head1 AUTHOR

Dominik Schulz <dominik.schulz@gauner.org>

=head1 COPYRIGHT AND LICENSE

This software is copyright (c) 2012 by Dominik Schulz.

This is free software; you can redistribute it and/or modify it under
the same terms as the Perl 5 programming language system itself.

=cut
