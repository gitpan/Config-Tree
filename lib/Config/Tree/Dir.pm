package Config::Tree::Dir;

=head1 NAME

Config::Tree::Dir - Read configuration tree from a directory

=head1 SYNOPSIS

 # in confdir/
 #   foo/
 #     bar      # content: '3'
 #     baz      # content: "hello, world!\n\n"
 #     binary   # content: "\xff\xfe\n"
 #     quux     # content: '{i: 1, j: 2}'
 #   flag       # 0 bytes

 # in script.pl:

 use Config::Tree::Dir;
 my $conf = Config::Tree::Dir->new(
     path => '/path/to/confdir',
     #watch => 10, # currently not implemented
     #allow_symlink => 0,
     #check_owner => 1,
     #content_as_yaml => 0,
     #include_path_re => qr/.../,
     #exclude_path_re => qr/.../,
     #include_file_re => qr/.../,
     #exclude_file_re => qr/.../,
     #tie_cache_opts => {...} # currently not implemented
     ro => 0,
 );

 # when content_as_yaml is 0:
 $conf->get('/foo/bar'); # 3
 $conf->get('/foo/baz'); # "hello, world!", newlines stripped
 $conf->get('/foo/binary'); # "\xff\xfe\n", newlines not stripped in binaries
 $conf->get('/foo/flag'); # 1, all zero byte files is assumed to mean True

 # when content_as_yaml is 1:
 $conf->get('/foo/bar'); # 3
 $conf->get('/foo/baz'); # "hello, world!", YAML parser also strips newlines
 $conf->get('/foo/flag'); # undef

 $conf->cd('/foo');
 $conf->set('bar', 10); # same as set('/foo/bar', 10);
 $conf->save(); # writes back to directory

=head1 DESCRIPTION

=cut

use Moose;
extends 'Config::Tree::Base';
use Fcntl ':mode';
use File::Path;
use File::Slurp;
use Tie::Cache;
use YAML::XS;

=head1 ATTRIBUTES

=cut

has path => (is => 'rw');
has allow_symlink => (is => 'rw', default => 0);
has check_owner => (is => 'rw', default => 1);
has content_as_yaml => (is => 'rw', default => 0);

has include_file_re => (is => 'rw');
has exclude_file_re => (is => 'rw', default => sub { qr/\A#|~\z/ });

has _read_config_cache => (is => 'rw');
has _read_config_cache_path => (is => 'rw', default => '');
has _mtime => (is => 'rw');

=head1 METHODS

=head2 new(%args)

Construct a new Config::Tree::Dir object. Arguments.

=over 4

=item *

C<path>. Required. Path to config directory.

=item *

C<ro>. Optional, default is 0. Whether we should disallow set() and save().

=item *

C<allow_symlink>. Optional, default is 0. When is set to 0, then all symlinks
will be ignored. This is related to security when superuser/root is dealing with
user-created config dirs.

=item *

C<check_owner>. Optional, default is 1. When set to 1, then all files/dirs in
the config directory must either be created by superuser/root or by config dir
owner, otherwise it will be ignored. This is related to security when
superuser/root is dealing with user-created config dirs.

=item *

C<exclude_path_re>. Optional. When set, config path matching the regex will not
be retrieved. See also: C<include_path_re>.

=item *

C<include_path_re>. Optional. When set, only config path matching the regex will
be retrieved. Takes precedence over C<exclude_path_re>.

=item *

C<exclude_file_re>. Optional. Default is qr/\A#|~\z/ (backup files). When set, files
with name matching the regex will not be read. See also: C<include_file_re>.

=item *

C<include_file_re>. Optional. When set, only files with name matching the regex
will be read. Takes precedence over C<exclude_file_re>.

=item *

C<content_as_yaml>. Optional, default is 0. When set to 1, all files are assumed
to be YAML documents and will be parsed. Otherwise, these conventions are used
when retrieving file contents:

- all trailing newlines ("\x0d", "\x0a") will be stripped, unless the file is a
  binary file (a binary file is defined as a file containing other than ASCII
  [\x09\x0a\x0d\x20-\x277].

- zero-length files will be retrieved as 1. This is useful for flag files (which
  indicated active/true when exist and nonactive/false when do not).

=back

=cut

sub BUILD {
    my ($self) = @_;
    die "path must be specified" unless defined($self->path);
}

# read a file. fspath0 is an "absolute" path relative to config dir. so if config
# dir is at '/home/steven/conf' and fspath is '/foo/bar', then the file searched
# is '/home/steven/conf/foo/bar.'

sub _read_file {
    my ($self, $fspath0) = @_;
    die "_read_file: fspath0 must start with / and cannot contain .. or .!"
      if $fspath0 !~ m!^/! || $fspath0 =~ m!/\.\.?(\z|/)!;
    my $fspath = $self->path. $fspath0;
    my $fc = read_file($fspath);
    if ($self->content_as_yaml) {
        eval { $fc = Load($fc) };
        if ($@) {
            warn "_read_file: $fspath is not a valid YAML document, setting to undef instead";
            return;
        }
    } else {
        my $binary = $fc =~ /[^\x09\x0a\x0d\x20-\x7f]/;
        if ($fc eq '') {
            $fc = 1;
        } elsif (!$binary) {
            $fc =~ s/[\x0a\x0d]+\z//s;
        }
    }
    $fc;
}

# recursively read all config files/subdirs

sub _read_config0 {
    my ($self, $fspath0) = @_;
    die "_read_file: fspath0 `$fspath0` must start with / and cannot contain .. or .!"
      if $fspath0 !~ m!^/! || $fspath0 =~ m!/\.\.?(\z|/)!;
    my $fspath = $self->path. $fspath0;

    my $res = {};
    if (!$self->allow_symlink && (-l $fspath)) {
        warn "_read_config0: $fspath is a symlink, skipped";
        return $res;
    }
    die "_read_config0: $fspath is not a directory" unless -d $fspath;
    my ($confdir_owner, $owner);
    if ($self->check_owner) {
        $confdir_owner = (stat $self->path)[4];
        $owner = (stat $fspath)[4];
        if ($owner != 0 && $owner != $confdir_owner) {
            warn "_read_config0: $fspath is not owned by root/confdir owner, skipped";
            return $res;
        }
    }
    local *D;
    unless (opendir D, $fspath) {
        warn "_read_config0: $fspath cannot be read: $!";
        return $res;
    }
    for my $e (readdir D) {
        next if $e eq '.' || $e eq '..';
        next if $self->file_is_excluded($e);
        my @st = stat "$fspath/$e";
        unless (@st) {
            warn "_read_config0: $fspath/$e can't be stat'ed, skipped";
            next;
        }
        #if (!$self->allow_symlink && ($st[2] & S_IFLNK)) {
        if (!$self->allow_symlink && (-l "$fspath/$e")) {
            warn "_read_config0: $fspath/$e is a symlink, skipped";
            next;
        }
        if ($self->check_owner) {
            $owner = $st[4];
            if ($owner != 0 && $owner != $confdir_owner) {
                warn "_read_config0: $fspath/$e is not owned by root/confdir owner, skipped";
                next;
            }
        }
        #if ($st[2] & 0100000) {
        my $fspath0b = $fspath0 . ($fspath0 =~ m!/$! ? $e : "/$e");
        if (-d "$fspath/$e") {
            $res->{$e} = $self->_read_config0($fspath0b);
        } else {
            $res->{$e} = $self->_read_file($fspath0b);
        }
    }
    closedir D;
    $res;
}

sub _read_config {
    my ($self, $fspath0) = @_;
    die "_read_config: fspath0 `$fspath0` must start with / and cannot contain .. or .!"
      if $fspath0 !~ m!^/! || $fspath0 =~ m!/\.\.?(\z|/)!;
    my $fspath = $self->path . $fspath0;
    if ($self->_read_config_cache_path eq $fspath) {
        return $self->_read_config_cache;
    } else {
        my $res = $self->_read_config0($fspath0);
        $self->_read_config_cache_path($fspath);
        $self->_read_config_cache($res);
        $self->_mtime(time());
        return $res;
    }
}

=head2 file_is_excluded

=cut

sub file_is_excluded {
    my ($self, $filename) = @_;
    if ($self->include_file_re && $filename !~ $self->include_file_re) {
        #print "$filename is not included (".$self->include_file_re.")\n";
        return 1;
    }
    if ($self->exclude_file_re && $filename =~ $self->exclude_file_re) {
        #print "$filename is excluded (".$self->exclude_file_re.")\n";
        return 1;
    }
    0;
}

=head2 get_tree_for

=cut

sub get_tree_for {
    my ($self, $wanted_tree_path) = @_;

    #print "get_tree_for($wanted_tree_path)\n";

    die "get_tree_for: path `".$self->path."` is not a directory" unless -d $self->path;

    $wanted_tree_path = $self->normalize_path($wanted_tree_path);

    my $tree;

    my @p = grep {length} split m!/+!, $wanted_tree_path;
    my $fspath0 = "/";
    my $fspath = $self->path;
    my @p2;
    for (@p) {
        last unless (-e $fspath);
        next if $self->file_is_excluded($_);
        if (!$self->allow_symlink && (-l $fspath)) {
            warn "get_tree_for: $fspath is a symlink, skipped";
            last;
        }
        my ($confdir_owner, $owner);
        if ($self->check_owner) {
            $confdir_owner = (stat $self->path)[4];
            $owner = (stat $fspath)[4];
            if ($owner != 0 && $owner != $confdir_owner) {
                warn "get_tree_for: $fspath is not owned by root/confdir owner";
            }
        }
        last unless (-d $fspath);
        $fspath0 .= ($fspath0 =~ m!/$! ? $_ : "/$_");
        $fspath .= "/$_";
        push @p2, $_;
    }

    if (-d $fspath) {
        $tree = $self->_read_config($fspath0);
    } else {
        if ((-f $fspath) && $self->content_as_yaml) {
            my $fc = $self->_read_file($fspath0);
            if (ref($fc) eq 'HASH') {
                $tree = $fc;
            } elsif (defined(pop @p2)) {
                $fspath0 = "/" . join("/", @p2);
                $tree = $self->_read_config($fspath0);
            } else {
                $tree = undef;
            }
        } else {
            if (defined(pop @p2)) {
                $fspath0 = "/" . join("/", @p2);
                $tree = $self->_read_config($fspath0);
            } else {
                $tree = undef;
            }
        }
    }

    ("/".join("/", @p2), $tree, $self->_mtime, $fspath0);
}

sub _format_validation_error {
    my ($self, $res, $tree_path) = @_;
    sprintf("%sconfig dir `%s/%s` has %d error(s): `%s`",
            ($self->modified ? "modified " : ""),
            $self->path,
            $tree_path,
            scalar(@{ $res->{errors} }),
            join(", ", @{ $res->{errors} }));
}

=head2 set($path, $val)

Set config variable.

Will immediately create necessary subdirectories and write to file.

Example: set("/a/b/c", 1) will create a/ and a/b/ subdirectories, and file
a/b/c containing "1". If a already exists as a file, it will be removed

When $val is a reference and content_as_yaml is 1, a YAML dump will be written
to the file.

=cut

sub _set_or_unset {
    my ($self, $is_set, $tree_path, $val) = @_;
    die "_set_or_unset: config is read-only!" if $self->ro;

    $tree_path = $self->normalize_path($tree_path);
    my @p = grep {length} split m!/+!, $tree_path;

    die "_set_or_unset: cannot set value for /" unless @p;
    my $n = pop @p;
    my $fspath0 = "/";
    my $fspath = $self->path;
    for (my $i=0; $i<=@p; $i++) {
        if (!$self->allow_symlink && (-l $fspath)) {
            warn "_set_or_unset: $fspath is a symlink, removing ...";
            unlink $fspath or die "set(): can't unlink $fspath: $!";
        }
        if ((-f $fspath) && $self->content_as_yaml) {
            my $tree = $self->_read_file($fspath0);
            if (ref($tree) ne 'HASH') { $tree = {} }
            unlink $fspath or die "_set_or_unset: can't unlink $fspath: $!";
            my $oldval = $self->_set_in_tree(
                $tree,
                "/".join(map {$p[$_]} $i+1..(@p-1)).$n,
                $is_set ? $val : undef);
            write_file($fspath,
                       "# Written by Config::Tree::Dir on ".scalar(localtime)."\n" .
                       Dump($tree));
            return $oldval;
        }
        if ((-e $fspath) && !(-d $fspath)) {
            unlink $fspath or die "_set_or_unset: can't unlink $fspath: $!";
        }
        unless (-d $fspath) {
            #print "mkdir($fspath)\n";
            mkdir $fspath, 0755 or die "_set_or_unset: can't mkdir $fspath: $!";
        }
        do { $fspath0 .= ($fspath0 =~ m!/$! ? $p[$i] : "/$p[$i]"); $fspath .= "/$p[$i]" } if $i<@p;
    }

    $fspath0 .= "/$n"; $fspath .= "/$n";
    my $oldval;
    if (-e $fspath) {
        if (-f $fspath) {
            if (!(-l $fspath) || $self->allow_symlink) {
                # XXX check_owner
                $oldval = $self->_read_file($fspath0);
            }
        }
        rmtree($fspath) or die "_set_or_unset: can't rmtree `$fspath`: $!";
    }
    if ($is_set) {
        if (!defined($val) && !$self->content_as_yaml) {
            warn "_set_or_unset: Setting undef is not possible when content_as_yaml=0, setting to 0 instead";
            $val = 0;
        }
        write_file($fspath, ($self->content_as_yaml ? Dump($val) : $val));
    }

    # flush cache
    if (index($fspath, $self->_read_config_cache_path) == 0) {
        $self->_read_config_cache_path('');
    }

    $oldval;
}

sub set {
    my ($self, $tree_path, $val) = @_;
    $self->_set_or_unset(1, $tree_path, $val);
}

=head2 unset($path)

Unset config variable.

=cut

sub unset {
    my ($self, $tree_path) = @_;
    $self->_set_or_unset(0, $tree_path);
}

=head2 save()

Does nothing. All changes are immediately written by set() or unset().

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
