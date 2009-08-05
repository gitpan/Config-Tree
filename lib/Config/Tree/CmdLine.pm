package Config::Tree::CmdLine;

=head1 NAME

Config::Tree::CmdLine - Read configuration tree from command line options

=head1 SYNOPSIS

 # READING CONFIG FROM COMMAND LINE

 # in shell:

 % perl script.pl --foo/bar=3
 % perl script.pl --foo='{bar: 3}'; # same thing
 % perl script.pl '{bar: 3}'; # same thing, since ui.order of foo is 0

 # in script.pl:

 use Config::Tree::CmdLine;

 my $conf = Config::Tree::CmdLine->new(
     schema => [hash=>{keys=>{
         foo=>[hash=>{ keys=>{bar=>"int"}, "ui.order"=>0, "ui.description"=>"Foo is blah" }],
         baz=>[str=>{ "ui.order"=>1, "ui.description"=>"Baz is blah..." }],
     }}],
     # when_invalid => ...,
     # include_path_re => qr/.../,
     # exclude_path_re => qr/.../,
     # must_exist => 0|1,
     # special_options => {...},
     ro    => 0,
 );
 my $val = $conf->get('/foo/bar'); # 3
 $conf->cd('/foo');
 $conf->set('bar', 10); # same as set('/foo/bar', 10);


 # DISPLAYING HELP

 # in shell:
 % perl script.pl --help; # will display help using information from schema

=head1 DESCRIPTION

=cut

use Moose;
extends 'Config::Tree::Base';
use Data::Schema;
use File::Slurp;
use List::MoreUtils qw/any/;
use YAML::XS; # YAML.pm sucks: too strict for simple values, requiring ---, newline, etc

=head1 ATTRIBUTES

=cut

has _tree => (is => 'rw');
has _mtime => (is => 'rw');
has _loaded => (is => 'rw', default => 0);
has special_options => (is => 'rw');
has short_options => (is => 'rw'); # hashref, letter => long equivalent
has stop_after_first_arg => (is => 'rw', default => 0);
has argv => (is => 'rw');

=head1 METHODS

=head2 new(%args)

Construct a new Config::Tree::CmdLine object. Arguments.

=over 4

=item *

C<ro>. Optional, default is 0. Whether we should disallow set() and save().

=item *

C<when_invalid>. Optional, default is 'die'. What to do when a command line
option is unknown in schema or does not validate schema. Choices: 'die', 'warn',
'quiet'. Will do nothing if no schema is supplied.

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

C<special_options>. Optional. Normally each command line option will be added to
the config tree. However, if a hashref is supplied for this property, and an
option name matches the key in the hashref, then the supplied special
instructions will be used. This is used for example to display help/usage, add
synonyms, etc.

Default value for C<special_options> is:

 {help => { schema=>'bool', sub=>{$self->usage(); exit 0} }

The code in C<sub> will be called with option value as the first argument and
$self as the second argument, and should return nothing or a hashref containing
option names and values which will be added to config tree. Another example for
special option:

 {
  help    => ...,
  debug   => { schema=>'bool', sub=>sub {{log_level=>"debug"}} }
  verbose => { schema=>'bool', sub=>sub {{log_level=>"info"}} }
  quiet   => { schema=>'bool', sub=>sub {{log_level=>"error"}} }
 }

In other words, specifying --debug, --verbose, and --quiet will set log_level
accordingly. This might be a preferred syntax over the slightly longer
--log_level=debug, etc.

=item *

C<short_options>. Optional. A hashref which map letter to long name equivalent.
Example:

 {h => "help", d => "debug", v => "verbose"}

This means, specifying -d will be the same as --debug, and so on.

=item *

C<stop_after_first_arg>. Optional. Default is 1. If enabled, then command line
options processing will stop as soon as first non-option (i.e., argument) is
encountered. Under stop_after_first_arg=1:

 % script.pl --foo 1 3 --bar 2

will result in config tree {foo=>1} and @ARGV (3, '--bar', 2). Under
stop_after_first_arg=0, the same command line will result in config tree
{foo=>1, bar=>2} and @ARGV (3).

=item *

C<argv>. Optional, an arrayref. Instead of the default @ARGV, process command
line on this array instead.

=back

=cut

sub BUILD {
    my ($self) = @_;
    if (!$self->special_options) {
        $self->special_options(
            { help => { schema=>'bool', sub=>sub {print $self->usage(), "\n"; exit 0} } }
        );
    }

    # immediately load
    $self->get_tree_for('/');
    $self->name("cmdline") unless $self->name;
}

# tree is a tree, vars is a hashref containing name=>val pairs. name can contain
# path separators and it will be added to the right branch.
sub __add_to_tree {
    my ($tree, $vars) = @_;

    foreach my $name (keys %$vars) {
        my $val = $vars->{$name};
        my $t = $tree;
        my @path = grep {length} split m!/+!, $name;
        my $n = pop @path;
        for (@path) {
            if (!exists $t->{$_}) {
                $t->{$_} = {};
                $t = $t->{$_};
            } else {
                die "Command line option conflict with previous one(s): $name";
            }
        }
        if (!exists($t->{$n})) {
            $t->{$n} = $val;
        } else {
            die "Command line option conflict: $name";
        }
    }
}

sub _get_tree {
    my ($self) = @_;

    unless ($self->_loaded) {
        my $tree = {};
        my @argv = $self->argv ? @{ $self->argv } : @ARGV;
        my $schema = $self->schema;
        my $key_schemas = $self->_get_all_key_schemas;

        my $i = 0;
        my @non_opts;
        while ($i < @argv) {
            my $a = $argv[$i];
            $i++;
            unless ($a =~ /^-/) {
                if ($self->stop_after_first_arg) {
                    push @non_opts, @argv[$i-1..$#argv];
                    last;
                } else {
                    push @non_opts, $a;
                    next;
                }
            }
            do { push @non_opts, @argv[$i .. $#argv]; last } if $a eq '--';
            my ($name, $eq, $val);
            if ($a =~ /^--/) {
                ($name, $eq, $val) = $a =~ m!^--/?(\w+(?:/\w+)*)(=)?(.*)!s
                    or die "Invalid command line option: $a";
            } else {
                $a =~ /^-(.)/;
                if ($self->short_options && $self->short_options->{$1}) {
                    $name = $self->short_options->{$1};
                } else {
                    die "Unknown short option: $a";
                }
            }

            # find in special options
            my $ss;
            if ($self->special_options && ($ss = $self->special_options->{$name})) {
                if ($ss->{schema} && ref($ss->{schema}) ne 'HASH') {
                    $ss->{schema} = $self->validator->normalize_schema($ss->{schema});
                }
                # XXX validate with schema ss?
            }

            # find in key schema
            my $p = $name =~ m!^/! ? $name : "/$name";
            my $ks = $key_schemas->{$p};
            my $found = $ss || $ks;

            my $takes_arg =
                ($ss && $ss->{schema} && $ss->{schema}{type} =~ /^(bool|boolean)$/) ? 0 :
                ($ks && $ks->{type} =~ /^(bool|boolean)$/) ? 0 : 1;

            # --nofoo (or --foo/nobar) for boolean
            my ($m1, $m2) = $p =~ m!(.*)/no(\w+)$!;
            if (defined($m2) && !$ks && $key_schemas->{"$m1/$m2"} &&
                $key_schemas->{"$m1/$m2"}{type} =~ /^(?:bool|boolean)$/) {
                $name = "$m1/$m2"; $name =~ s!^/!!;
                $val = 0;
                $found++;
            }
            # --foo followed by a non-opt, becomes --foo=NONOPT
            elsif ($takes_arg && !$eq && $i < @argv && $argv[$i] !~ /^--/) {
                $val = $argv[$i];
                $i++;
            }

            if ($schema && !$found) {
                if ($self->when_invalid eq 'die') {
                    die "Unknown option: $a";
                } elsif ($self->when_invalid eq 'warn') {
                    warn "Unknown option: $a";
                }
            }

            if (length($val)) {
                eval { $val = Load($val) };
                die "YAML parse error in command line option $a: $@" if $@;
            } else {
                # --foo followed by other opt, or --foo at the end => --foo=1
                $val = 1;
            }

            my $to_add;
            if ($ss) {
                $to_add = $ss->{sub}->($val, $self) || {};
            } else {
                $to_add = {$name=>$val};
            }
            __add_to_tree($tree, $to_add);
        }

        # add args to tree if ui.order attribute is specified
        my %indexes_found;
        for (keys %$key_schemas) {
            my $ks = $key_schemas->{$_};
            my $order = $ks->{attr_hashes}[0]{"ui.order"};
            next unless defined($order);
            next if $order >= @non_opts;
            die "Duplicate ui.order ($order) in keys schema: $_" if $indexes_found{$order};
            $indexes_found{$order} = $_;
        }
        for (sort {$b<=>$a} keys %indexes_found) {
            __add_to_tree($tree, {$indexes_found{$_} => $non_opts[$_]});
            splice @non_opts, $_, 1;
        }

        $self->_tree($tree);
        $self->_mtime(time);
        $self->_loaded(1);

        if ($self->argv) {
            $self->argv(\@non_opts);
        } else {
            @ARGV = @non_opts;
        }

    }
    ($self->_tree, $self->_mtime);
}

=head2 usage()

Prints usage information. Requires schema be specified.

=cut

sub usage {
    my ($self, $key_schemas) = @_;
    $key_schemas ||= $self->_get_all_key_schemas;
    if (!$self->schema) { return "Sorry, no help available.\n" }
    my $v = $self->validator;
    my $schema = $v->normalize_schema($self->schema);
    my $u = '';

    my $tmp = $schema->{attr_hashes}[0]{"ui.description"};
    if (defined($tmp)) {
        my $app = $0; $app =~ s!.+/!!;
        $u .= "$app - $tmp\n\n";
    }

    $u .= "Options (* denotes required options):\n";
    for my $k (sort keys %$key_schemas) {
        my ($s, $sopt) = @{ $key_schemas->{$k} };
        my $desc = "[" . $v->get_type_handler($s->{type})->type_in_english($s) . "]";
        $tmp = $s->{attr_hashes}[0]{"ui.order"};
        $desc .= " [or arg ".($tmp+1)."]" if defined($tmp);
        $tmp = $s->{attr_hashes}[0]{"ui.description"};
        $desc .= " $tmp" if defined($tmp);
        $k =~ s!^/!!;
        $u .= sprintf "  --%-12s %s\n", $k . ($sopt->{required} ? "*" : ""), $desc;
    }

    $u;
}

# search schema for hashes and then list all its key schemas, recursively. as
# well as normalize the schemas into third form. return an empty list if there
# is no schema or no keys schemas.

sub _get_all_key_schemas {
    my ($self, $prefix, $schema, $res) = @_;

    $prefix ||= "";
    $schema ||= $self->schema;
    $res ||= {};

    if ($schema) {
        my $v = $self->validator;
        my $s = $v->normalize_schema($schema);
        my $mr = $v->merge_attr_hashes($s->{attr_hashes});
        for my $ah (@{ $mr->{result} }) {
            next unless ref($ah->{keys}) eq 'HASH';
            for my $hk (keys %{ $ah->{keys} }) {
                my $ss = $v->normalize_schema($ah->{keys}{$hk});
                my $k = $hk; $k =~ s/^[*+.^!-]//;
                next unless $k =~ /^\w+$/;
                my $pk = "$prefix/$k";
                next if exists $res->{$pk};
                my $required = 0;
                if (($ah->{required_keys} && any {$_ eq $k} @{ $ah->{required_keys} }) ||
                    ($ah->{required_keys_regex} && $k =~ /$ah->{required_keys_regex}/)) {
                    $required = 1;
                }
                $res->{$pk} = [$ss, {required=>$required}];
                $self->_get_all_key_schemas($pk, $ss, $res);
            }
        }
    }
    $res;
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
