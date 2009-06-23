package Config::Tree::YAMLHashFile;

=head1 NAME

Config::Tree::YAMLHashFile - Read configuration tree from a YAML file containing multiple hashes that can be based on one another

=head1 SYNOPSIS

 # in config.yaml:
 server: {services: {http: No, ftp: No, dns_resolver: Yes, dns_server: No, mysql: No}}
 dns_server: [server, {services: {dns_server: Yes}}]
 powerdns_server: [dns_server, {services: {mysql: Yes}}]

 dns1: [powerdns_server, {ip: 1.2.3.4}]
 dns2: [dns_server, {ip: 1.2.3.5}]

 # in script.pl:

 use Config::Tree::YAMLHashFile;

 my $conf = Config::Tree::YAMLHashFile->new(
     path  => '/path/to/config.yaml',
     # see Config::Tree::File for other options
 );

 $conf->get('/dns2/ip'); # 1.2.3.5
 $conf->get('/dns2/services/mysql'); # 0
 $conf->get('/dns1/services/mysql'); # 1


=head1 DESCRIPTION

CT::YAMLHashFile has the same idea as L<Config::Tree::YAMLHashDir>, except that
all hashes are stored in a top-level structure in single file.

=cut

use Moose;
extends 'Config::Tree::File';
use File::Slurp;
use Data::PrefixMerge;

=head1 ATTRIBUTES

=cut

has _merger => (is => 'rw', default => sub { Data::PrefixMerge->new });
has _recursing => (is => 'rw', default => sub { {} });

=head1 METHODS

=cut

sub BUILD {
    my ($self) = @_;
    die "path must be specified" unless defined($self->path);
}

sub _resolve_key {
    my ($self, $k) = @_;
    my $hh = $self->_tree;
    #print "_resolve_key($k)\n";
    if (!exists($hh->{$k})) {
        warn "_resolve_key: unknown key `$k`";
        return;
    }
    my $h = $hh->{$k};
    return unless defined($h);
    return if ref($h) eq 'HASH';

    if (ref($h) eq 'ARRAY') {
        $self->_recursing->{$k}++;
        my @tomerge;
        my $i = 0;
        for my $e (@$h) {
            $i++;
            if (ref($e) eq 'HASH') {
                push @tomerge, $e;
            } elsif (!ref($e)) {
                if ($self->_recursing->{$e}) {
                    warn "_resolve_key($k): recursive reference to key $e, skipped";
                    next;
                }
                $self->_resolve_key($e);
                push @tomerge, $hh->{$e} if defined($hh->{$e});
            } else {
                warn "_resolve_key($k): element $i: not a hash or string, skipped";
                next;
            }
        }
        my $merged = @tomerge ? $tomerge[0] : undef;
        for (my $i=1; $i<@tomerge; $i++) {
            my $res = $self->_merger->merge($merged, $tomerge[$i]);
            if (!$res->{success}) {
                die "_resolve_key($k): merge BUG: ".$res->{error};
            }
            #print "merge ".Dump($merged)." with ".Dump($tomerge[$i])." = ".Dump($res)."\n";
            $merged = $res->{result};
        }
        $hh->{$k} = $merged;
        delete $self->_recursing->{$k};
    } else {
        warn "_resolve_key($k): not a hash/array, ignoring";
        delete $hh->{$k};
    }
}

sub _load_file {
    my ($self) = @_;
    my $hh = $self->_safe_read_yaml("");
    die "config must be hashref" unless ref($hh) eq 'HASH';
    $self->_tree($hh);
    $self->_resolve_key($_) for keys %$hh;
    $hh;
}

=head2 set($path, $val)

Not supported at the moment.

=cut

sub set {
    die "Sorry, set() is not supported at the moment for CT::YAMLHashFile";
}

=head2 unset($path, $val)

Not supported at the moment.

=cut

sub unset {
    die "Sorry, unset() is not supported at the moment for CT::YAMLHashFile";
}

=head2 save()

Not supported at the moment.

=cut

sub save {
    die "Sorry, save() is not supported at the moment for CT::YAMLHashFile";
}

=head1 SEE ALSO

L<Config::Tree::YAMLHashDir>

=head1 AUTHOR

Steven Haryanto, C<< <stevenharyanto at gmail.com> >>

=head1 COPYRIGHT & LICENSE

Copyright 2009 Steven Haryanto, all rights reserved.

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.


=cut

__PACKAGE__->meta->make_immutable;
1;
