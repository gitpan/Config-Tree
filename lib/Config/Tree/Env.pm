package Config::Tree::Env;

=head1 NAME

Config::Tree::Env - Read configuration tree from environment variables

=head1 SYNOPSIS

 # in Bash-like shell:

 % CONFIG_FOO__BAR=3 perl script.pl
 % CONFIG_FOO='{bar: 3}' perl script.pl; # same thing

 # in script.pl:

 use Config::Tree::Env;

 my $conf = Config::Tree::Env->new(
     # schema => ...,
     # include_path_re => qr/.../,
     # exclude_path_re => qr/.../,
     # env_path_separator => '__',
     # env_prefix => 'CONFIG_',
     # env_lowercase => 1,
     # env_as_yaml => 1,
     ro    => 0,
 );
 my $val = $conf->get('/foo/bar'); # 3
 $conf->cd('/foo');
 $conf->set('bar', 10); # same as set('/foo/bar', 10);


=head1 DESCRIPTION

This module, CT::Env, construct config tree from environment
variables. By default, only config variables beginning with C<CONFIG_>
will be parsed (can be changed with C<env_prefix> property). By
default, C<__> in environment variable's names will be regarded as
path separator (can be changed with C<env_path_separator>
property). Also, by default, environment variable's name will be
converted to lowercase (can be prevented by setting C<env_lowercase>
property to 0). So, environment variable C<CONFIG_FOO__BAR> will
become C</foo/bar> while C<CONFIG_FOO_BAR> will become C</foo_bar> and
C<FOO_BAR> will be ignored.

=cut

use Moose;
extends 'Config::Tree::Base';
use File::Slurp;
use Data::Schema;
use YAML::XS; # YAML.pm sucks: too strict for simple values, requiring ---, newline, etc

=head1 ATTRIBUTES

=cut

has _tree => (is => 'rw');
has _mtime => (is => 'rw');
has _loaded => (is => 'rw', default => 0);
has env_path_separator => (is => 'rw', default => '__');
has env_prefix => (is => 'rw', default => 'CONFIG_');
has env_lowercase => (is => 'rw', default => 1);
has env_as_yaml => (is => 'rw', default => 1);

=head1 METHODS

=head2 new(%args)

Construct a new Config::Tree::Env object. Arguments.

=over 4

=item *

C<exclude_path_re>. Optional. When set, config path matching the regex will not
be retrieved. See also: C<include_path_re>.

=item *

C<include_path_re>. Optional. When set, only config path matching the regex will
be retrieved. Takes precedence over C<exclude_path_re>.

=item *

C<schema>. Optional. When specified, after the tree is retrieved, it will be
validated against this schema using Data::Schema.

=item *

C<env_path_separator>. Optional. What string to assume as path
separator. Default is C<__> (two underscores). If you do not want path
splitting, set this to empty string.

=item *

C<env_prefix>. Optional. Default is C<CONFIG_>. What string to use as
prefix. Only variables matching the prefix will be parsed. Setting
this to empty string means all environment variables will be parsed
and imported into config tree!

=item *

C<env_lowercase>. Optional. Whether to convert environment variable's
name to lowercase. Default is 1.

=item *

C<env_as_yaml>. Optional. Whether to assume environment variable's
value as YAML. Default is 1.

=back

=cut

sub BUILD {
    my ($self) = @_;
    # immediately load
    $self->get_tree_for('/');
    $self->name("env") unless $self->name;
}

sub _get_tree {
    my ($self) = @_;

    unless ($self->_loaded) {
        my $tree = {};

        my $sep = $self->env_path_separator;
        if (length($sep)) { $sep = qr/\Q$sep/ }
        my $prefix = $self->env_prefix;
        if (length($prefix)) { $prefix = qr/^\Q$prefix/ }

        for my $envname (keys %ENV) {
            my $name = $envname;
            next unless !$prefix || $name =~ s/$prefix//;
            $name =~ s!$sep!/!g if $sep;
            $name = lc($name) if $self->env_lowercase;

            my $val = $ENV{$envname};
            if ($self->env_as_yaml) {
                eval { $val = Load($val) };
                die "YAML parse error in environment variable $envname: $@" if $@;
            }

            my $t = $tree;
            my @path = grep {length} split m!/+!, $name;
            my $n = pop @path;
            for (@path) {
                if (!exists $t->{$_}) {
                    $t->{$_} = {};
                    $t = $t->{$_};
                } else {
                    die "Environment variable conflict with previous one(s): $envname";
                }
            }
            if (!exists($t->{$n})) {
                $t->{$n} = $val;
            } else {
                die "Environment variable conflict: $envname";
            }
        }

        $self->_tree($tree);
        #print Dump($tree);
        $self->_mtime(time);
        $self->_loaded(1);

    }
    ($self->_tree, $self->_mtime);
}

sub _format_validation_error {
    my ($self, $res) = @_;
    sprintf("%sconfig has %d error(s): `%s`",
            ($self->modified ? "modified " : ""),
            scalar(@{ $res->{errors} }),
            join(", ", @{ $res->{errors} }));
}

=head2 set($path, $val)

Does nothing.

=head2 save()

Does nothing.

=cut

sub _save {
    my ($self) = @_;
    1;
}

=head1 SEE ALSO

L<Data::Schema>, L<Config::Tree::Base>

=head1 AUTHOR

Steven Haryanto, C<< <stevenharyanto at gmail.com> >>

=head1 COPYRIGHT & LICENSE

Copyright 2009 Steven Haryanto, all rights reserved.

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.


=cut

__PACKAGE__->meta->make_immutable;
1;
