package Config::Tree::Base;

=head1 NAME

Config::Tree::Base - Base class for Config::Tree classes

=head1 SYNOPSIS

 # Moose-speak
 extends 'Config::Tree::Base';

=head1 DESCRIPTION

This is the base class for Config::Tree classes.
=cut

use Moose;

use Data::Schema;

=head1 ATTRIBUTES

=cut

has name => (is => 'rw');

has ro => (is => 'ro', default => 1);
has modified => (is => 'rw', default => 0);
has when_invalid => (is => 'rw', default => 'die');
has validator => (is => 'rw', default => sub { Data::Schema->new() } );
has cwd => (is => 'rw', default => '/');
has dirstack => (is => 'rw', default => sub { [] });

has schema => (is => 'rw');

has include_path_re => (is => 'rw');
has exclude_path_re => (is => 'rw');


=head1 METHODS

=head2 get_tree_for($wanted_path)

Will be called whenever the tree is wanted (e.g. by get()). Should return an
list ($tree_path, $tree, $mtime). For small trees that are loaded entirely into
memory, $tree_path will be '/' (meaning the whole tree is retrieved). For large
trees, when $wanted_path = '/foo/bar', get_tree_for() might return $tree_path =
'/foo' which means only the '/foo' branch is loaded.

In other words, $tree_path can be a parent of $wanted_path. get_tree_for() is
called with $wanted_path argument to allow each source to only return a subtree.

The default implementation will call _get_tree() which should return the whole
tree and then _validate_tree(). Large tree classes (e.g. tree from database or
directory) can override this method to be able to load only parts of the tree as
needed.

=cut

sub get_tree_for {
    my ($self, $wanted_path) = @_;

    # default implementation
    my ($tree, $mtime) = $self->_get_tree;
    $self->_validate_tree($tree, '/');
    ('/', $tree, $mtime);
}

sub _validate_tree {
    my ($self, $tree, $path) = @_;
    return 1 unless $self->schema && $tree;
    #use Data::Dumper; $Data::Dumper::Terse=1; print "_validate_tree: tree=".Dumper($tree).", schema=".Dumper($self->schema)."\n";
    my $res = $self->validator->validate($tree, $self->schema);
    return 1 if $res->{success};
    if ($self->when_invalid eq 'quiet') {
        return 0;
    } else {
        my $msg = $self->_format_validation_error($res, $path);
        if ($self->when_invalid eq 'warn') {
            warn $msg;
        } else {
            #print $msg;
            die $msg;
        }
    }
}

=head2 save()

Save configuration. Does nothing if configuration is never modified (by set()
method). Dies if config is read only (ro property is true).

=cut

sub save {
    my ($self) = @_;
    die "save: config is read only!" if $self->ro;
    return unless $self->modified;
    $self->_save;
    $self->modified(0);
}

=head2 getcwd()

Returns the current absolute position.

=cut

sub getcwd {
    my ($self) = @_;
    $self->cwd;
}

=head2 pushd([$new_dir])

Save the current position into stack, optionally change to $new_dir. Concept is
like Unix shell's "pushd" command.

=cut

sub pushd {
    my ($self, $new_dir) = @_;
    push @{ $self->dirstack }, $self->cwd;
    $self->cd($new_dir) if defined($new_dir);
}

=head2 popd()

Go back to the last saved position. Concept is like Unix shell's "popd" command.

=cut

sub popd {
    my ($self) = @_;
    my $p = pop @{ $self->dirstack };
    die "popd: too many pops" unless defined($p);
    $self->cwd($p);
}

=head2 cd($path)

Change position to $path. $path is absolute or relative path.

=cut

sub cd {
    my ($self, $path) = @_;
    die "cd: path must be speficied" unless $path;
    $self->cwd($self->normalize_path($path));
}

=head2 normalize_path($path)

$path is a string, which can contain absolute (e.g. "/foo/bar") or relative path
(e.g., "../bar"). Returns array of path elements, which is its normalized form.

=cut

sub normalize_path {
    my ($self, $path) = @_;
    die "normalize_path: path must be string" if ref($path);

    my @p1;
    push @p1, (grep {length} split m!/+!, $self->cwd) unless $path =~ m!^/!;
    push @p1, (grep {length} split m!/+!, $path);
    my @p2;
    # eliminate .. and .
    for (@p1) {
        if ($_ eq '..') { pop @p2 } elsif ($_ eq '.') {} else { push @p2, $_ }
    }
    "/" . join("/", @p2);
}

=head2 get($path)

Get config variable for $path.

The default implementation can handle hash prefix a la Data::PrefixMerge.

=cut

sub get {
    my ($self, $path) = @_;
    my @res = $self->_get_with_key($path);
    return unless @res;
    die "BUG: _get_with_key doesn't return a 2-element list" unless @res == 2;
    $res[1];
}

# instead of just returning $val, returns a list ($key, $val) where $key is the
# key of the last branch (which might contain prefix).

sub _get_with_key {
    my ($self, $path) = @_;
    $path = $self->normalize_path($path);
    return if $self->path_is_excluded($path);
    my ($tree_path, $tree, $mtime) = $self->get_tree_for($path);
    return unless defined($tree);
    die "get: cannot get config tree for `$path`, got `$tree_path`" unless index($path, $tree_path) == 0;
    my $curpath = $tree_path eq '/' ? '' : $tree_path;
    my $key = "";
    for (grep {length} split m!/+!, substr($path, length($tree_path))) {
        $curpath .= "/$_";
        #use Data::Dumper; print "get($path): $curpath: tree=",Dumper($tree),"\n";
        return if $self->path_is_excluded($curpath);
        if (ref($tree) eq 'HASH') {
            for my $prefix ("", "*", "-", "+", ".", "^", "!") {
                $key = "$prefix$_";
                last if defined($tree->{$key});
            }
            $tree = $tree->{$key};
        } elsif (ref($tree) eq 'ARRAY' && /^\d+$/) {
            $key = $_;
            $tree = $tree->[$_];
        } else {
            return;
        }
    }
    ($key, $tree);
    # XXX clone?
}

=head2 path_is_excluded($normalized_path)

=cut

sub path_is_excluded {
    my ($self, $p) = @_;
    if ($self->include_path_re && $p !~ $self->include_path_re) {
        #print "$p is not included (".$self->include_path_re.")\n";
        return 1;
    }
    if ($self->exclude_path_re && $p =~ $self->exclude_path_re) {
        #print "$p is excluded (".$self->exclude_path_re.")\n";
        return 1;
    }
    0;
}

=head2 set($path, $val)

=cut

sub _set_or_unset_in_tree {
    my ($self, $tree, $path, $is_set, $val) = @_;

    my @path = grep {length} split m!/+!, $self->normalize_path($path);
    die "_set_in_tree: cannot set value for /" unless @path;
    my $n = pop @path;
    my $supertree;
    #print "set($path): ";
    for (my $i=0; $i<@path; $i++) {
        #print " >> $path[$i] ";
        if (ref($tree) eq 'HASH') {
            $supertree = $tree;
            $tree = $tree->{$path[$i]};
        } elsif (ref($tree) eq 'ARRAY' && /^\d+$/) {
            $supertree = $tree;
            $tree = $tree->[$path[$i]];
        } else {
            $tree = {};
            if (ref($supertree) eq 'ARRAY') {
                $supertree->[$path[$i-1]] = { $path[$i] => $tree };
            } else {
                $supertree->{$path[$i-1]} = { $path[$i] => $tree };
            }
        }
    }
    #print "\n";
    my $oldval;
    if (ref($tree) eq 'HASH') {
        $oldval = $tree->{$n};
        if ($is_set) { $tree->{$n} = $val } else { delete $tree->{$n} }
    } elsif (ref($tree) eq 'ARRAY' && $n =~ /^\d+$/) {
        $oldval = $tree->[$n];
        if ($is_set) { $tree->[$n] = $val } else { splice @{ $tree }, $n, 1 }
    } else {
        die "BUG: _set_in_tree: can't set /".join("/", @path, $n).": nonexisting hash/array";
    }
    $oldval;
}

sub _set_or_unset {
    my ($self, $path, $is_set, $val) = @_;
    die "_set_or_unset: config is read-only!" if $self->ro;

    # default implementation: modify retrieved tree (from _get_tree) directly
    my ($tree, $mtime) = $self->_get_tree;
    return unless defined($tree);
    my $oldval = $self->_set_or_unset_in_tree($tree, $path, $is_set, $val);
    $self->modified(1);
    $oldval;
}

sub set {
    my ($self, $path, $val) = @_;
    $self->_set_or_unset($path, 1, $val);
}

=head2 unset($path)

=cut

sub unset {
    my ($self, $path) = @_;
    $self->_set_or_unset($path, 0);
}


=head1 SEE ALSO

L<Data::Schema>, L<Data::PrefixMerge>.

=head1 AUTHOR

Steven Haryanto, C<< <stevenharyanto at gmail.com> >>

=head1 COPYRIGHT & LICENSE

Copyright 2009 Steven Haryanto, all rights reserved.

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.


=cut

__PACKAGE__->meta->make_immutable;
1;
