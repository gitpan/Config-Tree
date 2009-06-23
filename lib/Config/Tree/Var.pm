package Config::Tree::Var;

=head1 NAME

Config::Tree::Var - Read configuration tree from Perl data structure

=head1 SYNOPSIS

 use Config::Tree::Var;

 my $tree = {
    foo => {
        bar => 2,
        baz => 3,
    }
 };

 my $conf = Config::Tree::Var->new(
     tree => $var,
     # schema => ...,
     # when_invalid => ...
     # include_path_re => qr/.../,
     # exclude_path_re => qr/.../,
     ro => 0,
 );
 my $val = $conf->get('/foo/bar'); # 2
 $conf->cd('/foo');
 $conf->set('bar', 10); # same as set('/foo/bar', 10);

=head1 DESCRIPTION

=cut

use Moose;
extends 'Config::Tree::Base';

=head1 ATTRIBUTES

=cut

has _loaded => (is => 'rw', default => 0);
has _mtime => (is => 'rw', default => 0);
has tree => (is => 'rw', default => 0);

=head1 METHODS

=head2 new(%args)

Construct a new Config::Tree::Var object. Arguments.

=over 4

=item *

C<tree>. Required. Perl data structure that contains the tree. Must be a
hashref.

=item *

C<ro>. Optional, default is 0. Whether we should disallow set() and save().

=item *

C<when_invalid>. Optional, default is 'die'. What to do when file content does
not validate with supplied schema. Choices: 'die', 'warn', 'quiet'.

=item *

C<exclude_path_re>. Optional. When set, config path matching the regex will not
be retrieved. See also: C<include_path_re>.

=item *

C<include_path_re>. Optional. When set, only config path matching the regex will
be retrieved. Takes precedence over C<exclude_path_re>.

=item *

C<schema>. Optional. When specified, after the tree is retrieved, it will be
validated against this schema using Data::Schema.

=back

=cut

sub BUILD {
    my ($self) = @_;
    die "tree must be specified" unless defined($self->tree);
    $self->name("var") unless $self->name;
}

sub _get_tree {
    my ($self) = @_;
    unless ($self->_loaded) {
        die "tree must be hashref" unless ref($self->tree) eq 'HASH';
        $self->_loaded(1);
        $self->_mtime(time);
    }
    ($self->tree, $self->_mtime);
}

sub _format_validation_error {
    my ($self, $res) = @_;
    sprintf("%sconfig has %d error(s): `%s`",
            ($self->modified ? "modified " : ""),
            scalar(@{ $res->{errors} }),
            join(", ", @{ $res->{errors} }));
}

=head2 set($path, $val)

Set config variable in the tree.

=head2 save()

Does nothing. set() will already modify the Perl data structure.

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
