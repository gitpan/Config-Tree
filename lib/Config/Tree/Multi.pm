package Config::Tree::Multi;

=head1 NAME

Config::Tree::Multi - Access multiple config trees as a single tree

=head1 SYNOPSIS

 use Config::Tree::Multi;

 # a simple example. config from files and command line options
 my $conf = Config::Tree::Multi->new();
 $conf->add_file('/etc/default/spanel.yaml');
 $conf->add_file('/etc/default/');
 $conf->add_cmdline();


 # a more complex (and real-world) example, with schema and loading config trees
 # on demand

 #   in /usr/share/spanel/default-configs/server.yaml:
 features:
   mysql: Yes
   pgsql: Yes
   smtp: Yes
   pop3: Yes
   imap: Yes
   http: Yes
   ftp: Yes

 #   in /etc/spanel/server.yaml:
 features:
   pgsql: No
 user:
   steven:
     +quota: 500

 #   in /etc/spanel/plans/PLAN1:
 limits:
   bandwidth: 1000 # in GB
   quota: 2000     # in MB
   cgi: Yes
 php_version: 5

 #   in /u/steven/sysetc/plan:
 PLAN1

 #   in /u/steven/sysetc/limits/cgi:
 0

 #   in /u/steven/etc/limits/cgi:
 1

 #   in /u/steven/etc/php_version:
 4

 #   in /u/tommy/sysetc/plan:
 PLAN1

 #   in application:
 my $plans = Config::Tree::Dir->new(path=>'/etc/spanel/plans');
 my $defsrvconf = Config::Tree::File->new(path=>"/usr/share/spanel/default-configs/server.yaml");
 my $srvconf = Config::Tree::File->new(path=>"/etc/spanel/server.yaml");
 my $srvconf_schema = Load(scalar read_file("/usr/share/spanel/config-schemas/server.yaml"));
 my $usrconf_schema = Load(scalar read_file("/usr/share/spanel/config-schemas/user.yaml"));
 my %sysetcs; # perhaps tied with Tie::Cache to limit number of config dirs loaded at once
 my %etcs; #

 my $Config::Tree::Multi->new(
    trees_sub => sub {
        my ($path) = @_;
        if ($path =~ m!^/user/([^/+])(/limits)?(?:/|\z)!) {
            if (!$sysetcs{$1}) { $sysetcs{$1} = Config::Tree::Dir->new(path => "/u/$1/sysetc") }
            if (!$etcs{$1}) { $etcs{$1} = Config::Tree::Dir->new(path => "/u/$1/etc") }
            my $plan = $plans->get( $sysetcs{$1}->get('plan') || 'DEFAULT' );
            return
                ["/", $plan],
                ["/user/$1", $srvconf, "KEEP"],
                ["/", $sysetcs{$1}, "KEEP", $usrconf_schema],
                ($2 ? undef : ["/", $etcs{$1}, undef, $usrconf_schema]);
        } else {
            return
                ["/", $defsrvconf],
                ["/", $srvconf, undef, $srvconf_schema];
        }
    }
 );

 $conf->get('/features/mysql'); # 1
 $conf->get('/features/pgsql'); # 0
 $conf->get('/user/steven/limits/quota'); # 2500
 $conf->get('/user/tommy/limits/quota'); # 2000
 $conf->get('/user/steven/limits/cgi'); # 0
 $conf->get('/user/steven/php_version'); # 4
 $conf->get('/user'); # { steven => { '+quota' => 500 } }

=head1 EXAMPLE EXPLANATION

The long second example deserves some explanation. Spanel is a shared hosting
control panel application. Each user is given different features according to
its hosting plan.

Server configuration is at /etc/spanel/server.yaml (with defaults at
/usr/share/spanel/default-configs/server.yaml).

Configuration for each hosting plan is at /etc/spanel/plans/. Each file in this
directory contains default settings for each plan. Settings in 'limits/' cannot
be overriden by user (for obvious reasons), while other settings can.

Per-user configuration is at /u/<USERNAME>/sysetc/ and /u/<USERNAME>/etc/. User
cannot write to sysetc/ but can write freely to etc/.

Server configuration can also contain per-user configurations in their /user/*
branch (see the above /etc/spanel/server.yaml example).

 $conf->get('/features/mysql'); # 1

In default server configuration (/usr/share/spanel/default-configs/server.yaml),
/features/mysql is enabled (as are many other services).

 $conf->get('/features/pgsql'); # 0

Same as above, but in this case, the server configuration (in
/etc/spanel/server.yaml) disables it.

 $conf->get('/user/steven/limits/quota'); # 2500

For path '/user/*/' first the plan configuration is consulted. steven has plan
PLAN1 (defined in /u/steven/sysetc/plan), so by default it should have 2000 MB
disk quota. But, server configuration (/etc/spanel/server.yaml) overrides it in
its '/user/steven/limits' branch and *adds* 500 MB, so the final quota is 2500
MB.

 $conf->get('/user/tommy/limits/quota'); # 2000

Same as above, but this time there is no override, so tommy's quota is at plan
default, 2000 MB.

 $conf->get('/user/steven/limits/cgi'); # 0

As with the above, plan default is consulted first (which is 1, enabled). Then
admin disables CGI for user steven by putting 0 in /u/steven/sysetc/limits/cgi.
Even though the user might try to override this setting by putting 1 in
/u/steven/etc/limits/cgi, he would not succeed because for '/user/*/limits'
config vars, /u/<USERNAME>/etc/ will not be consulted.

 $conf->get('/user/steven/php_version'); # 4

This time php_version is overriden by the user, which is allowed. But if admin
puts 5 in /u/steven/sysetc/php_version then the user will always run PHP scripts
with PHP5, because of the KEEP merge mode.

I hope these examples illustrate the flexibility that CT::Multi provides. It
combines configuration from multiple sources (files, directories), and allows
some variables to be overridable, and some not. All these are accessed using a
single interface.

 $conf->get('/user'); # { steven => { '+quota' => 500 } }

Since in trees_sub, if requested config path does not match /user/(.+), then it
will only be sourced from default server config and server config. Other
behavior (like returning 'undef', or perhaps the whole per-user configs!) can be
set by modifying trees_sub parameter.


=head1 DESCRIPTION

This module combines several config trees in quite flexible ways. Each tree can
be "mounted" in different "mount point", multiple trees can be merged (with
Data::PrefixMerge) to get the final result. What you have at the end of the day
is a single uniform interface to access all your configuration.

=cut

use Moose;

use Data::Schema;
use Data::PrefixMerge;
use List::Util qw(max);

use Data::Dumper;

use Config::Tree::File;
use Config::Tree::Dir;
#use Config::Tree::Env;
use Config::Tree::CmdLine;
use Config::Tree::Var;
#use Config::Tree::DBI;

extends 'Config::Tree::Base';

=head1 ATTRIBUTES

=cut

has trees => (is => 'rw', default => sub { [] });
has trees_sub => (is => 'rw');
has _merger => (is => 'rw', default => sub { my $dm = Data::PrefixMerge->new; $dm->config->{preserve_keep_prefix} = 1; $dm });
has _merge_cache => (is => 'rw', default => sub { my %tie_cache; tie %tie_cache, 'Tie::Cache', 10; \%tie_cache } );

=head1 METHODS

=head2 new(%args)

Construct object. Arguments:

=over 4

=item *

C<schema>. Optional. When specified, after the tree is retrieved from source, it
will be validated against this schema using Data::Schema. You can also use
schema() property later to set the schema. Will not be used if trees_sub is
defined.

=item *

C<trees_sub>. Optional. Code reference that should return a list of config trees
with their configuration.

The sub will be called by CT::Multi's get_tree_for(), which in turn is called by
every get(). get_tree_for() will then merge the trees into one using
Data::PrefixMerge and return the result for get().

The sub will be called with $tree_path as the parameter and should return the
following:

 ([$path, $config_tree_object, $merge_mode],
  ...
  [$path, $config_tree_object, undef      , $schema]);

For each $config_tree_object returned, CT::Multi's get_tree_for() will call the
get_tree() method of that object (with $path as the argument) and then the
resulting trees will be merged together using Data::PrefixMerge (with
$merge_mode as the default merging mode, defaults to NORMAL if not specified).
The final merged tree is then validated with $schema if specified, and then
returned.

Example:

CT::Multi's get_tree_for('/a/b') is called.

trees_sub is defined and returns:

 (["/", $ct1],
  ["/foo", $ct2, "KEEP"],
  ["/", $ct3, undef, $schema]);

Here's how CT::Multi's get_tree_for() forms the final result:

$ct1->get_tree_for('/') is called and returns:

 ("/",
  {a=>{b=>1, b2=>2}, c=>2},
  mtime)

$ct2->get_tree_for('/foo') is called and returns:

 ("/foo",
  {a=>{b=>{f=>1}, c=>4}},
  mtime)

$ct3->get_tree_for('/') is called and returns:

 ("/a/b",
 {a=>{b=>{f=>2}}},
 mtime)

Result 1 is merged with result 2 with merge mode NORMAL:

 LEFT:         {a=>{b=>1, b2=>2}, c=>2}
 RIGHT:        {a=>{b=>{f=>1}, c=>4}}
 NORMAL MERGE: {a=>{b=>{f=>1}, b2=>2, c=>4}, c=>2}

The last result is merged with result 3 with merge mode KEEP:

 LEFT:       {a=>{b=>{f=>1}, b2=>2, c=>4}, c=>2}
 RIGHT:      {a=>{b=>{f=>2}}}
 KEEP MERGE: {a=>{b=>{f=>1}, b2=>2, c=>4}, c=>2}

So final result returned by CT::Multi's get_tree_for('/a/b') is:

 ("/",
  {a=>{b=>{f=>1}, b2=>2, c=>4}, c=>2},
  mtime)

Note that trees_sub is used for more customized behavior. For simpler behaviour,
you can just use the various add_* methods (like add_file(), add_dir(),
add_cmdline(), etc) to add trees to CT::Multi.

=back

=cut

sub BUILD {
    my ($self) = @_;
    if ($self->trees_sub && ref($self->trees_sub) ne 'CODE') {
        die "trees_sub must be a coderef!";
    }
}

=head2 add_file($path, %opts)

Add Config::Tree::File object to the trees. Options are actually arguments to
CT::File's constructor.

=cut

sub add_file {
    my ($self, $path, %opts) = @_;
    die "add_file: path must be a string containing file name" if ref($path);
    $opts{path} = $path;
    push @{ $self->trees }, ["/", Config::Tree::File->new(%opts)];
}

=head2 add_dir($path, %opts)

Add Config::Tree::Dir object to the trees. Options are actually arguments to
CT::Dir's constructor.

=cut

sub add_dir {
    my ($self, $path, %opts) = @_;
    die "add_dir: path must be a string containing directory name" if ref($path);
    $opts{path} = $path;
    push @{ $self->trees }, ["/", Config::Tree::Dir->new(%opts)];
}

=head2 add_cmdline()

Add Config::Tree::CmdLine object to the trees.

=cut

sub add_cmdline {
    my ($self, %opts) = @_;
    push @{ $self->trees }, ["/", Config::Tree::CmdLine->new(%opts)];
}

=head2 add_var($tree, %opts)

Add Config::Tree::Var object to the trees. Options are actually arguments to the
CT::Var's constructor.

=cut

sub add_var {
    my ($self, $tree, %opts) = @_;
    die "add_var: tree must be a hashref" unless ref($tree) eq 'HASH';
    $opts{tree} = $tree;
    push @{ $self->trees }, ["/", Config::Tree::Var->new(%opts)];
}

=head2 add_config_tree($ct, ...)

Add Config::Tree object.

=cut

sub add_config_tree {
    my ($self, $ct) = @_;
    push @{ $self->trees }, ["/", $ct];
}

=head2 save()

Dies. set() and save() should not be used on CT::Multi. Use set() and
save() on individual tree intead.

=cut

sub save {
    die "save() is not allowed for Config::Tree::Multi, use save() on individual tree instead";
}

=head2 set($path, $val)

Dies. set() and save() should not be used on CT::Multi. Use set() and
save() on individual tree intead.

=cut

sub set {
    die "set() is not allowed for Config::Tree::Multi, use set() on individual tree instead";
}

sub __common_prefix {
    my (@s) = @_;
    return unless @s;
    my $i = 0;
   L1: for ($i=0; $i<length($s[0]); $i++) {
        my $x = substr($s[0], $i, 1);
        for (my $j=1; $j<@s; $j++) {
            last L1 if substr($s[$j], $i, 1) ne $x;
        }
    }
   substr($s[0], 0, $i);
}

sub __get_branch {
    my ($tree, $path) = @_;
    return $tree if $path eq '/';
    for (grep {length} split m!/!, $path) {
        #print "__get_branch(".Dumper($tree).", $path): $_\n";
        if (ref($tree) eq 'HASH') {
            my $t;
            for my $prefix ("", "*", "-", "+", ".", "!") {
                $t = $tree->{"$prefix$_"};
                last if defined($t);
            }
            $tree = $t;
            #print "tree = ".Dumper($tree);
        } elsif (ref($tree) eq 'ARRAY' && /^\d+$/) {
            $tree = $tree->[$_];
        } else {
            last;
        }
    }
    $tree;
}

sub get_tree_for {
    my ($self, $path) = @_;
    my @ctrees;
    if ($self->trees_sub) {
        @ctrees = grep {defined} $self->trees_sub->($path);
    } else {
        @ctrees = grep {defined} @{ $self->trees };
    }

    #print "ctrees: (".scalar(@ctrees)."): ".join(" ", map {"$_->[0]|$_->[1]|$_->[2]"} @ctrees),"\n";

    return ('/', undef, 0) unless @ctrees;

    # call get_tree_for for each CT object to get the actual tree structures
    my @trees;
    for (@ctrees) {
        my ($tpath, $tree, $mtime) = $_->[1]->get_tree_for($_->[0]);
        next unless defined($tree);
        unless ($_->[0] eq $tpath) {
            $tree = __get_branch($tree, "/" . substr($_->[0], length($tpath)));
        }
        next unless defined($tree);
        push @trees, [$_->[0], $_->[1], ($_->[2] || 'NORMAL'), $_->[3], $tree, $mtime];
    }

    #print Dumper \@trees;

    my $cache_key = join(" ", map {"$_->[0]|$_->[1]|$_->[2]|$_->[5]"} @trees);
    my $mtime = max(map {$_->[5]} @trees);
    return ('/', $self->_merge_cache->{$cache_key}, $mtime) if exists($self->_merge_cache->{$cache_key});

    # merge
    my $tree = $trees[0][4];
    for (my $i=1; $i<@trees; $i++) {
        my $tree2 = $trees[$i][4];
        my $mode = $trees[$i-1][2];
        $self->_merger->config->{default_merge_mode} = $mode;
        #print "merge(".Dumper($tree).", ".Dumper($tree2).", $mode) = ".Dumper($self->_merger->merge($tree, $tree2))."\n";
        my $res = $self->_merger->merge($tree, $tree2);
        die "get_in_tree: cannot merge trees: $res->{error}" unless $res->{success};
        $tree = $res->{result};
    }

    my $schema = $trees[-1][3] || $self->schema;
    if ($schema) {
        $self->schema($schema);
        $self->_validate_tree($tree, '/');
    }

    $self->_merge_cache->{$cache_key} = $tree;

    return ('/', $tree, $mtime);
}

sub _format_validation_error {
    my ($self, $res, $path) = @_;
    sprintf("config tree at `%s` has %d error(s): `%s`",
            $path,
            scalar(@{ $res->{errors} }),
            join(", ", @{ $res->{errors} }));
}

=head1 SEE ALSO

Other Config::Tree modules: L<Config::Tree::File>, L<Config::Tree::Dir>, etc.

L<Data::PrefixMerge>

L<Data::Schema>

=head1 AUTHOR

Steven Haryanto, C<< <stevenharyanto at gmail.com> >>

=head1 COPYRIGHT & LICENSE

Copyright 2009 Steven Haryanto, all rights reserved.

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.


=cut

__PACKAGE__->meta->make_immutable;
1;
