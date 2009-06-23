package Config::Tree::CmdLine;

=head1 NAME

Config::Tree::CmdLine - Read configuration tree from command line options

=head1 SYNOPSIS

 # in shell:

 % perl script.pl --foo/bar=3
 % perl script.pl --foo='{bar=>3}'; # same thing

 # in script.pl:

 use Config::Tree::CmdLine;

 my $conf = Config::Tree::CmdLine->new(
     # schema => ...,
     # when_invalid => ...,
     # include_path_re => qr/.../,
     # exclude_path_re => qr/.../,
     ro    => 0,
 );
 my $val = $conf->get('/foo/bar'); # 3
 $conf->cd('/foo');
 $conf->set('bar', 10); # same as set('/foo/bar', 10);


=head1 DESCRIPTION

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

=head1 METHODS

=head2 new(%args)

Construct a new Config::Tree::CmdLine object. Arguments.

=over 4

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
    # immediately load
    $self->get_tree_for('/');
    $self->name("cmdline") unless $self->name;
}

sub _get_tree {
    my ($self) = @_;

    unless ($self->_loaded) {
        my $tree = {};

        my $i = 0;
        my @non_opts;
        while ($i < @ARGV) {
            my $a = $ARGV[$i];
            $i++;
            do { push @non_opts, $a; next } unless $a =~ /^--/;
            do { push @non_opts, @ARGV[$i .. $#ARGV]; last } if $a eq '--';
            my ($name, $eq, $val) = $a =~ m!^--/?(\w+(?:/\w+)*)(=)?(.*)!s
                or die "Invalid command line option: $a";


            # --foo followed by a non-opt, becomes --foo=NONOPT
            if (!$eq && $i < @ARGV && $ARGV[$i] !~ /^--/) {
                $val = $ARGV[$i];
                $i++;
            }
            if (length($val)) {
                eval { $val = Load($val) };
                die "Invalid command line option: $a ($@)" if $@;
            } else {
                # --foo followed by other opt, or --foo at the end => --foo=1
                $val = 1;
            }

            if ($name eq 'help') {
                print $self->usage();
                print "\n";
                exit 0;
            }

            my $t = $tree;
            my @path = grep {length} split m!/+!, $name;
            my $n = pop @path;
            for (@path) {
                if (!exists $t->{$_}) {
                    $t->{$_} = {};
                    $t = $t->{$_};
                } else {
                    die "Command line option conflict with previous one(s): $a";
                }
            }
            if (!exists($t->{$n})) {
                $t->{$n} = $val;
            } else {
                die "Command line option conflict: $a";
            }
        }

        $self->_tree($tree);
        $self->_mtime(time);
        $self->_loaded(1);

        @ARGV = @non_opts;
    }
    ($self->_tree, $self->_mtime);
}

=head2 usage()

Prints usage information. Requires schema be specified.

=cut

sub usage {
    my ($self) = @_;
    if (!$self->schema) {
        return "Sorry, help is not available.";
    }
    my $v = $self->validator;
    my $s = $v->normalize_schema($self->schema);
    my $ah = $v->merge_attr_hashes($s->{attr_hashes});
    my $h1 = $ah->{result}[0]{keys};
    if (!$h1) { return "Sorry, no options is known." }
    my $u = '';
    $u .= "Options:\n";
    for my $k (sort keys %$h1) {
        next unless $k =~ /^\w+$/;
        my $h2 = $v->normalize_schema($h1->{$k});
        $u .= " --$k ($h2->{type})";
        $u .= "  ".$h1->{"$k.usage"} if $h1->{"$k.usage"};
        $u .= "\n";
    }
    $u;
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
