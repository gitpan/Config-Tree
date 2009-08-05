package Config::Tree;

use vars qw(@ISA @EXPORT);
require Exporter;
@ISA = qw(Exporter);
@EXPORT = qw(get_config);

use Config::Tree::Multi;

=head1 NAME

Config::Tree - Access various configuration as a single Unix filesystem-like tree

=head1 VERSION

Version 0.04

=cut

our $VERSION = '0.04';

=head1 SYNOPSIS

 # in /etc/myapp.yaml:
 foo:
   bar: 1
 baz: 2

 # in ~/.myapp.yaml:
 foo:
   bar: 3
   quux: 4

 # in myapp.pl:
 use Config::Tree;
 my $conf = get_config();
 printf "/foo/bar = %s\n", $conf->get('/foo/bar');
 $conf->cd('/foo');
 printf "/foo/baz = %s\n", $conf->get('baz');
 printf "/quux = %s\n", $conf->get('../quux');

 # in shell:
 % perl myapp.pl --quux=5
 /foo/bar = 3
 /foo/baz = 2
 /quux = 5

 # See Config::Tree::Multi for more detailed usage. You can customize the
 # location of config files, put config in directories, arrange how values from
 # config files can be replaced/protected/reset by further files/command line
 # options, set/save config values, validate config trees using schema,
 # dynamically load ("mount") of config trees, etc.


=head1 DESCRIPTION

Config::Tree (CT) lets you access your various configuration (perl data
structure, config files, config dirs, environment variables, command
line options, even databases) as a single tree using a Unix filesystem-like
interface.

=head1 FUNCTIONS

=head2 get_config([%opts])

Exportable. Return the singleton Config::Tree::Multi object. The first call to
get_config() will create the object, the subsequent calls will just return the
created object.

Available options:

=over 4

=item *

C<appname>. Optional. Files /etc/<appname>.yaml and ~/.<appname>.yaml will be
added to configuration trees. Default is for C<appname> to be extracted from $0.

=back

If you want more customized behaviour (exact paths of files/dirs, whether config
should be read-only or writable, etc) you can create your own Config::Tree
object and then set the singleton to it using set_config(). See documentation
of, e.g., L<Config::Tree::Multi> for more details on creating custom config
tree.

=cut

my $Singleton_Conf;

sub get_config {
    my (%args) = @_;

    if (!$Singleton_Conf) {
        my $conf = Config::Tree::Multi->new();
        $conf->schema($args{schema});
        my $appname = $args{appname};
        if (!defined($appname)) {
            $appname = $0; $appname =~ s!.+/!!; $appname =~ s/\..+$//;
            if (!length($appname)) { $appname = "app" }
        }
        if ($appname ne '-e') {
            $conf->add_file("/etc/$appname.yaml");
            $conf->add_file("$ENV{HOME}/.$appname.yaml");
        }
        $conf->add_cmdline(schema=>$args{schema});
        $Singleton_Conf = $conf;
    }
    $Singleton_Conf;
}

=head2 set_config($ct)

Set the singleton config object to $ct, which is a Config::Tree object.

=cut

sub set_config($) {
    my ($ct) = @_;
    $Singleton_Conf = $ct;
}

=head1 COMPARISON WITH OTHER CONFIG MODULES

There are already a lot of config-related modules on CPAN. Here's the main
highlights of this module:

Things that are like what other modules do:

- Loading and merging config values from multiple sources (config files [YAML],
  config dirs, DBI databases, environment variables, command line options).

Things that are unlike what many other modules do:

- Nested (tree) config, even in command line options.

- Filesystem-like interface: cd(), pushd(), popd(), pwd(),
  get("../relative/path"), get("/abs/path"), mounting config trees to different
  mount points, etc.

- More flexible merging (merging modes). We can individually mark which config
  should be protected from being overriden, added/concatenated, or deleted. This
  is done with Data::PrefixMerge.

- Set/save config values back to storage (config files, directories, and
  databases).

- Validation (using Data::Schema).


=head1 SEE ALSO

Among the many config-related modules on CPAN: L<App::Options>, L<Getopt::Long>.

L<Config::Tree::Multi>, which is the actual class used.

L<Config::Tree::CmdLine> for more information on generating --help message, etc.

=head1 AUTHOR

Steven Haryanto, C<< <stevenharyanto at gmail.com> >>

=head1 BUGS

Please report any bugs or feature requests to C<bug-config-tree at
rt.cpan.org>, or through the web interface at
L<http://rt.cpan.org/NoAuth/ReportBug.html?Queue=Config-Tree>.  I will
be notified, and then you'll automatically be notified of progress on
your bug as I make changes.

=head1 SUPPORT

You can find documentation for this module with the perldoc command.

    perldoc Config::Tree


You can also look for information at:

=over 4

=item * RT: CPAN's request tracker

L<http://rt.cpan.org/NoAuth/Bugs.html?Dist=Config-Tree>

=item * AnnoCPAN: Annotated CPAN documentation

L<http://annocpan.org/dist/Config-Tree>

=item * CPAN Ratings

L<http://cpanratings.perl.org/d/Config-Tree>

=item * Search CPAN

L<http://search.cpan.org/dist/Config-Tree/>

=back


=head1 ACKNOWLEDGEMENTS


=head1 COPYRIGHT & LICENSE

Copyright 2009 Steven Haryanto, all rights reserved.

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.


=cut

1;
