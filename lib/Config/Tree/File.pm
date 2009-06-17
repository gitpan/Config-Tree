package Config::Tree::File;

=head1 NAME

Config::Tree::File - Read configuration tree from a YAML file

=head1 SYNOPSIS

 # in config.yaml:
 foo:
   bar: 2
   baz: 3

 # in script.pl:

 use Config::Tree::File;

 my $conf = Config::Tree::File->new(
     path  => '/path/to/config.yaml',
     # watch => 10, # currently not implemented
     # schema => ...,
     # when_invalid => ...,
     # include_path_re => qr/.../,
     # exclude_path_re => qr/.../,
     ro => 0,
 );
 my $val = $conf->get('/foo/bar'); # 2
 $conf->cd('/foo');
 $conf->set('bar', 10); # same as set('/foo/bar', 10);
 $conf->save(); # writes back to file

=head1 DESCRIPTION

=cut

use Moose;
extends 'Config::Tree::Base';
use File::Slurp;
use YAML;

=head1 ATTRIBUTES

=cut

has path => (is => 'rw');
has _mtime => (is => 'rw');
has _tree => (is => 'rw');
has _loaded => (is => 'rw', default => 0);

=head1 METHODS

=head2 new(%args)

Construct a new Config::Tree::File object. Arguments.

=over 4

=item *

C<path>. Required. Path to YAML file.

=item *

C<ro>. Optional, default is 0. Whether we should disallow set() and save().

=item *

C<exclude_path_re>. Optional. When set, config path matching the regex will not
be retrieved. See also: C<include_path_re>.

=item *

C<include_path_re>. Optional. When set, only config path matching the regex will
be retrieved. Takes precedence over C<exclude_path_re>.

=item *

C<schema>. Optional. When specified, after the tree is retrieved from file, it
will be validated against this schema using Data::Schema.

=back

=cut

sub BUILD {
    my ($self) = @_;
    die "path must be specified" unless defined($self->path);
}

sub _load_file {
    my ($self) = @_;
    my $content = read_file($self->path);
    my $res = Load($content);
    die "config must be hashref" unless ref($res) eq 'HASH';
    $res;
}

sub _get_tree {
    my ($self) = @_;
    unless ($self->_loaded) {
        if (-e $self->path) {
            my $res = $self->_load_file();
            $self->_tree($res);
            $self->_mtime((stat $self->path)[9]);
        } else {
            $self->_tree(undef);
            $self->_mtime(-1);
        }
        $self->_loaded(1);
    }
    ($self->_tree, $self->_mtime);
}

sub _format_validation_error {
    my ($self, $res) = @_;
    sprintf("%sconfig file `%s` has %d error(s): `%s`",
            ($self->modified ? "modified " : ""),
            $self->path,
            scalar(@{ $res->{errors} }),
            join(", ", @{ $res->{errors} }));
}

=head2 set($path, $val)

Set config variable.

Will not write to file until save() is called.

=head2 save()

Save config variable to file.

If schema is specified, config tree will be validated first and an error will be
thrown if the config does not validate.

=cut

sub _save {
    my ($self, $new_path) = @_;
    my $path = $new_path || $self->path;
    return unless $self->_validate_tree($self->_tree);
    write_file($path,
               "# Saved by Config::Tree::File on ".scalar(localtime)."\n" .
               Dump($self->_tree));
    $self->_mtime((stat $self->path)[9]);
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
