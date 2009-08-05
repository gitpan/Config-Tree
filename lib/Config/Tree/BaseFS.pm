package Config::Tree::BaseFS;

=head1 NAME

Config::Tree::BaseFS - Base class for Config::Tree classes which access filesystem

=head1 SYNOPSIS

 # Moose-speak
 extends 'Config::Tree::BaseFS';

=head1 DESCRIPTION

This base class provides some (mostly internal) methods which deals with
reading/writing files/directories.

Currently L<Config::Tree::File> and L<Config::Tree::Dir> derive from this class.

=cut

use Moose;
extends 'Config::Tree::Base';

use File::Slurp;
use Fcntl;

=head1 ATTRIBUTES

=cut

=head2 path (rw)

The path to config file (for Config::Tree::File) or directory (for
Config::Tree::Dir). Maybe relative or absolute path.

=cut

has path => (is => 'rw');

=head2 allow_symlink (rw, default 0)

Whether to allow symlinks. Possible values are 0 (does not allow symlinks at
all), 1 (allow symlinks if owner matches), 2 (allow symlinks). Default is 1. Due
to symlink attack issue, make sure you know exactly what you are doing if you
turn this to 2 if you read other user's files/directories.

=cut

has allow_symlink => (is => 'rw', default => 1);

=head2 allow_different_owner (rw, default 0)

Whether to allow writing to files/directories which have different owner as the
running user. By default this is 0, to protect root from writing to
user-controlled directories. Although this module uses safe writing to avoid
symlink attacks (when allow_symlink is 0/1 anyway), due to other issues, it is
not recommended for root to write to user-controlled directories. Make sure you
know exactly what you are doing if you turn this on.

=cut

has allow_different_owner => (is => 'rw', default => 0);

=head2 file_mode (rw, default 0644)

What permission mode to create new files.

=cut

has file_mode => (is => 'rw', default => 0644);

=head2 dir_mode (rw, default 0755)

What permission mode to create new directories.

=cut

has dir_mode => (is => 'rw', default => 0755);

=head2 yaml_module (ro, default 'YAML::XS')

Which YAML module to use. Default is 'YAML::XS', but will fall back to 'YAML'
(YAML.pm) if the first is unavailable. You can use either 'YAML::XS', 'YAML',
'YAML::Syck', or 'YAML::Tiny'.

=cut

has yaml_module => (is => 'ro', default => 'YAML::XS');

=head2 must_exist (rw, default 0)

If set to 1, then the file/dir must exist and an error is thrown if it doesn't.

=cut

has must_exist => (is => 'rw', default => 0);

=head1 METHODS

=cut

sub BUILD {
    my ($self) = @_;

    die "path must be specified" unless defined($self->path);

    my $m = $self->yaml_module;
    if ($m eq 'YAML::XS') {
        eval 'use YAML::XS';
    } elsif ($m eq 'YAML') {
        eval 'use YAML';
    } elsif ($m eq 'YAML::Syck') {
        eval 'use YAML::Syck';
    } elsif ($m eq 'YAML::Tiny') {
        eval 'use YAML::Tiny qw(Dump Load)';
    } else {
        die "Unknown YAML module `".$self->yaml_module."`, use either ".
            "YAML, YAML::Syck, YAML::Tiny, or YAML::XS";
    }
    die $@ if $@;
}

sub _check_symlink {
    my ($self, $fspath) = @_;
    #print "_check_symlink($fspath)\n";
    return if $self->allow_symlink >= 2;

    if (-l $fspath) {
        my $cond = 0;
        if ($self->allow_symlink == 1) {
            my @st1 = lstat $fspath;
            my @st2 = stat $fspath;
            $cond = $st1[4] == $st2[4];
        }
        if (!$cond) {
            die "symlink `$fspath` not allowed";
        }
    }
}

# read file. $fspath0 is path relative to $self->path. checks against symlinks
# and different owner if necessary.

# XXX max_size to protect root from reading very large user's file?

sub _safe_read_file {
    my ($self, $fspath0) = @_;

    $fspath0 = "" if !defined($fspath0);

    my @tocheck;
    if ($fspath0 eq '') {
        push @tocheck, '';
    } else {
        die "_safe_read_file: fspath0 must start with / and not contain ../.!"
            if $fspath0 !~ m!^/! || $fspath0 =~ m!/\.\.?(\z|/)!;
        push @tocheck, '';
        push @tocheck, grep {length} split m!/+!, $fspath0;
    }

    # instead of checking intermediate directories and then reading the file, we
    # first open the filehandle *and then* check intermediate directories, to
    # avoid state change between checking and reading.

    local *F;
    my $fspath = $self->path . $fspath0;
    unless (-f $fspath) {
        die "_safe_read_file: `$fspath` does not exist or is not a file";
    }
    open F, $fspath or die "_safe_read_file: Can't read `$fspath`: $!";

    # check symlinks
    $fspath = $self->path;
    for (@tocheck) {
        $fspath .= (length($_) ? "/$_" : $_);
        $self->_check_symlink($fspath);
    }

    # check different owner
    unless ($self->allow_different_owner) {
        my @st = stat $fspath;
        $st[4] == $> or die "_safe_read_file: file `$fspath` is owned by ".
            "different user ($st[4]), not by running user ($>)";
    }

    local $/;
    my $file_content = <F>;
    close F;
    $file_content;
}

sub _safe_read_yaml {
    my ($self, $fspath0) = @_;
    my $file_content = $self->_safe_read_file($fspath0);
    eval { $file_content = Load($file_content) };
    if ($@) {
        warn "Warning: file " . $self->path . $fspath0 .
            " is not a valid YAML document, assuming empty file";
        return;
    }
    $file_content;
}

# remove old file if exists, create new file at $fspath0, which is a path
# relative to $self->path. creates intermediate directories. checks against
# symlinks and different owner if necessary.

sub _safe_mkfile {
    my ($self, $fspath0, $file_content) = @_;
    #print "_safe_mkfile($fspath0, $file_content)\n";

    $fspath0 = '' if !defined($fspath0);
    my $fspath = $self->path;

    my @tocheck;
    if (length($fspath0)) {
        die "_safe_mkfile($fspath0): fspath0 must start with / and not contain ../.!"
            if $fspath0 !~ m!^/! || $fspath0 =~ m!/\.\.?(\z|/)!;
        @tocheck = grep {length} split m!/+!, $fspath0;
        die "_safe_mkfile: invalid fspath0 `$fspath0`" unless @tocheck;
        my $fn = pop @tocheck;

        # check and create intermediate directories
        for ('', @tocheck) {
            $fspath .= (length($_) ? "/$_" : $_);
            if ((-f $fspath) || (-l $fspath)) {
                unlink $fspath or die "_safe_mkfile: Can't unlink `$fspath`: $!";
            }
            unless (-d $fspath) {
                mkdir $fspath, $self->dir_mode or
                    die "_safe_mkfile: Can't mkdir `$fspath`: $!";
            }
            unless ($self->allow_different_owner) {
                my @st = stat $fspath;
                $st[4] == $> or die "_safe_mkfile: dir `$fspath` is owned by ".
                    "different user ($st[4]), not by running user ($>)";
            }
        }
        $fspath .= "/$fn";
    }

    local *F;
    unlink $fspath;
    #print "sysopen($fspath)\n";
    sysopen(F, $fspath, O_WRONLY | O_EXCL | O_CREAT)
        or die "_safe_mkfile: can't create `$fspath`: $!";
    chmod $self->file_mode, $fspath;

    # as in _safe_read_file(), we check symlinks after we get a filehandle, to
    # avoid state change between checking and opening the file.

    $fspath = $self->path;
    @tocheck = ('', grep {length} split m!/+!, $self->path);
    for (@tocheck) {
        $fspath .= $_;
        $self->_check_symlink($fspath);
    }

    print F $file_content;
    close F or die "_safe_write_file: can't write to `$fspath`: $!";
    return; # XXX we haven't implemented returning old content
}

sub _safe_mkyaml {
    my ($self, $fspath0, $data) = @_;
    $self->_safe_mkfile($fspath0, Dump($data));
}

=head1 SEE ALSO

L<Config::Tree::Base>, L<Config::Tree::File>, L<Config::Tree::Dir>

=head1 AUTHOR

Steven Haryanto, C<< <stevenharyanto at gmail.com> >>

=head1 COPYRIGHT & LICENSE

Copyright 2009 Steven Haryanto, all rights reserved.

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.


=cut

__PACKAGE__->meta->make_immutable;
1;
