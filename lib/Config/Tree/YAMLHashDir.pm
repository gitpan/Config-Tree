package Config::Tree::YAMLHashDir;

=head1 NAME

Config::Tree::YAMLHashDir - Read configuration tree from a directory of YAML files containing (derivative) hash

=head1 SYNOPSIS

 # in confdir/templates/server:
 services:
   # for security, the default setting for all servers is to have no services
   # enabled, except for dns resolver.
   http: No
   ftp: No
   dns_server: No
   dns_resolver: Yes
   mysql: No

 # in confdir/templates/http_server:
 - server
 - services:
     http: Yes

 # in confdir/templates/dns_server:
 - server
 - services:
     dns_server: Yes

 # in confdir/templates/powerdns_server:
 - dns_server
 - services:
     # we are using mysql backend for powerdns, so we need mysql service too
     mysql: Yes

 # in confdir/dns1:
 - templates/powerdns_server
 - templates/http_server
 - ip: 1.2.3.4

 # in confdir/dns2:
 - templates/dns_server
 - ip: 1.2.3.5

 # in script.pl:

 use Config::Tree::YAMLHashDir;
 my $conf = Config::Tree::YAMLHashDir->new(
     path => '/path/to/confdir',
     #see Config::Tree::Dir for other options
 );

 $conf->get('/dns2/ip'); # 1.2.3.5
 $conf->get('/dns2/services'); # {http=>0, ftp=>0, dns_server=>1, dns_resolver=>1. mysql=>0}
 $conf->get('/dns1/services'); # {http=>0, ftp=>0, dns_server=>1, dns_resolver=>1, mysql=>1}

=head1 DESCRIPTION

CT::YAMLHashDir is a subclass of CT::Dir. All files in config dir must be YAML
files, and the YAML documents must be hashes. However, if YAML document is an
array, then it is further parsed like this: for each element, if element is
string than it is assumed to be the config path to another YAML document,
otherwise it must be hash. All resulting hashes will be merged together using
L<Data::PrefixMerge>.

The idea is to allow writing config files that are derived (a la OO) from other
config files. See the above example.

=cut

use Moose;
extends 'Config::Tree::Dir';
use Data::PrefixMerge;
use File::Slurp;
use YAML::XS;

=head1 ATTRIBUTES

=cut

has _merger => (is => 'rw', default => sub { Data::PrefixMerge->new } );

# a hash to avoid recursive reference between YAML files
has _recursing => (is => 'rw', default => sub { {} });

has _files_cache => (is => 'rw', default => sub { {} });

=head1 METHODS

=head2 new(%args)

Construct a new CT::YAMLCacheDir object. See CT::Dir for other arguments. Note
that content_as_yaml is always 1 as all files must be YAML files.

=cut

sub BUILD {
    my ($self) = @_;
    die "path must be specified" unless defined($self->path);
    $self->content_as_yaml(1);
}

override '_read_config', sub {
    my ($self, $fspath0) = @_;
    # XXX _files_cache should've been based on mtime, not reset after each _read_config. but it'll do for now
    # because _read_config is also cached by CT::Dir
    $self->_files_cache({});
    super($fspath0);
};

# read a file
sub _read_file {
    my ($self, $fspath0) = @_;
    die "_read_file: fspath0 must start with / and cannot contain .. or .!"
      if $fspath0 !~ m!^/! || $fspath0 =~ m!/\.\.?(\z|/)!;
    return $self->_files_cache->{$fspath0} if exists $self->_files_cache->{$fspath0};
    #print "_read_file($fspath0)\n";
    my $fspath = $self->path . $fspath0;
    unless (-f $fspath) {
        warn "_read_file($fspath0): $fspath does not exist or is not a file, setting to undef instead";
        return;
    }
    my $h = read_file($fspath);
    eval { $h = Load($h) };
    if ($@) {
        warn "_read_file($fspath0): $fspath is not a valid YAML document, setting to undef instead";
        return;
    }
    if (ref($h) eq 'ARRAY') {
        $self->_recursing->{$fspath0}++;
        my @h;
        my $i=0;
        foreach my $e (@$h) {
            $i++;
            if (ref($e) eq 'HASH') { push @h, $e }
            elsif (!ref($e)) {
                my $fspath0b = $self->normalize_path($e =~ m!^/! ? $e : "$fspath0/../$e");
                if ($self->_recursing->{$fspath0b}) {
                    warn "_read_file($fspath0): element #$i: recursive reference to $fspath0b, skipping this element";
                    next;
                }
                $e = $self->_read_file($fspath0b);
                unless (ref($e) eq 'HASH') {
                    warn "_read_file($fspath0): element #$i: referenced $fspath0b is not a hash, skipping this element";
                    next;
                }
                push @h, $e;
            } else {
                warn "_read_file($fspath0): element #$i: not hash nor string, skipping this element";
                next;
            }
        }
        # merge
        return unless @h;
        $h = $h[0];
        for (my $i=1; $i<@h; $i++) {
            my $res = $self->_merger->merge($h, $h[$i]);
            if (!$res->{success}) {
                die "_read_file: merge BUG: ".$res->{error};
            }
            $h = $res->{result};
        }
        delete $self->_recursing->{$fspath0};
    } elsif (ref($h) ne 'HASH') {
        warn "_read_file($fspath0): $fspath is not a YAML hash, setting to undef instead";
        return;
    }
    $self->_files_cache->{$fspath0} = $h;
}

=head2 set($path, $val)

Not supported at the moment.

=cut

sub set {
    die "Sorry, set() is not supported at the moment for CT::YAMLHashDir";
}

=head2 unset($path)

Not supported at the moment.

=cut

sub unset {
    die "Sorry, unset() is not supported at the moment for CT::YAMLHashDir";
}

=head2 save()

Not supported at the moment.

=cut

sub _save {
    die "Sorry, save() is not supported at the moment for CT::YAMLHashDir";
}

=head1 SEE ALSO

L<Data::PrefixMerge>, L<Config::Tree::Dir>

=head1 AUTHOR

Steven Haryanto, C<< <stevenharyanto at gmail.com> >>

=head1 COPYRIGHT & LICENSE

Copyright 2009 Steven Haryanto, all rights reserved.

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.


=cut

__PACKAGE__->meta->make_immutable;
1;
