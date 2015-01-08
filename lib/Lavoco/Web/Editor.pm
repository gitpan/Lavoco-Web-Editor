package Lavoco::Web::Editor;

use 5.006;

use Moose;

use Data::Dumper;
use DateTime;
use Email::Stuffer;
use Encode;
use File::Slurp;
use FindBin qw($Bin);
use JSON;
use Log::AutoDump;
use Plack::Handler::FCGI;
use Plack::Request;
use Template;
use Term::ANSIColor;
use Time::HiRes qw(gettimeofday);

$Data::Dumper::Sortkeys = 1;

=head1 NAME

Lavoco::Web::Editor - Experimental framework with two constraints: FastCGI and Template::Toolkit to edit flat files.

=head1 VERSION

Version 0.01

=cut

our $VERSION = '0.01';

$VERSION = eval $VERSION;

=head1 SYNOPSIS

Framework to run small web app to edit flat files, running as a FastCGI application.

 use Lavoco::Web::Editor;
 
 my $editor = Lavoco::Web::Editor->new( name => 'Example editor' );
 
 my $action = lc( $ARGV[0] );   # (start|stop|restart)
 
 $editor->$action;

=cut

=head1 METHODS

=head2 Class Methods

=head3 new

Creates a new instance of the web-app editor object.

=head2 Attributes

=cut

has  name      => ( is => 'rw', isa => 'Str',  default => 'App' );
has  processes => ( is => 'rw', isa => 'Int',  default => 5         );
has  base      => ( is => 'rw', isa => 'Str',  lazy => 1, builder => '_build_base'      );
has _pid       => ( is => 'rw', isa => 'Str',  lazy => 1, builder => '_build__pid'      );
has _socket    => ( is => 'rw', isa => 'Str',  lazy => 1, builder => '_build__socket'   );
has  templates => ( is => 'rw', isa => 'Str',  lazy => 1, builder => '_build_templates' );
has  filename  => ( is => 'rw', isa => 'Str',  lazy => 1, builder => '_build_filename'  );
has  config    => ( is => 'rw', isa => 'HashRef' );

sub _build_base
{
    return $Bin;
}

sub _build__pid
{
    my $self = shift;

    return $self->base . '/editor.pid';
}

sub _build__socket
{
    my $self = shift;

    return $self->base . '/editor.sock';
}

sub _build_templates
{
    my $self = shift;

    return $self->base . '/editor-templates';
}

sub _build_filename
{
    my $self = shift;

    return $self->base . '/editor.json';
}

=head3 name

The identifier for the web-app, used as the FastCGI-process title.

=head3 base

The base directory of the application, detected using L<FindBin>.

=head3 processes

Number of FastCGI process to spawn, 5 by default.

=head3 templates

The directory containing the TT templates, by default it's C<$app-E<gt>base . '/editor-templates'>.

=head3 filename

Filename for the config file, default is C<app.json> and only JSON is currently supported.

=head3 config

The config as a hash-reference.

=head2 Instance Methods

=head3 start

Starts the FastCGI daemon.  Performs basic checks of your environment and dies if there's a problem.

=cut

sub start
{
    my $self = shift;

    if ( -e $self->_pid )
    {
        print "PID file " . $self->_pid . " already exists, I think you should kill that first, or specify a new pid file with the -p option\n";
        
        return $self;
    }

    $self->_init;

    print "Building FastCGI engine...\n";
    
    my $server = Plack::Handler::FCGI->new(
        nproc      =>   $self->processes,
        listen     => [ $self->_socket ],
        pid        =>   $self->_pid,
        detach     =>   1,
        proc_title =>   $self->name,
    );
    
    $server->run( $self->_handler );
}

sub _init
{
    my ( $self, %args ) = @_;

    ###############################
    # make sure there's a log dir #
    ###############################

    printf( "%-50s", "Checking logs directory");

    my $log_dir = $self->base . '/logs';

    if ( ! -e $log_dir || ! -d $log_dir )
    {
        _print_red( "[ FAIL ]\n" );
        print $log_dir . " does not exist, or it's not a folder.\nExiting...\n";
        exit;
    }

    _print_green( "[  OK  ]\n" );

    #####################################
    # make sure there's a templates dir #
    #####################################

    printf( "%-50s", "Checking templates directory");

    if ( ! -e $self->templates || ! -d $self->templates )
    {
        _print_red( "[ FAIL ]\n" );
        print $self->templates . " does not exist, or it's not a folder.\nExiting...\n";
        exit;
    }

    _print_green( "[  OK  ]\n" );

    ###########################
    # make sure 404.tt exists #
    ###########################

    printf( "%-50s", "Checking 404 template");

    my $template_404_file = $self->templates . '/404.tt';

    if ( ! -e $template_404_file )
    {
        _print_red( "[ FAIL ]\n" );
        print $template_404_file . " does not exist.\nExiting...\n";
        exit;
    }

    _print_green( "[  OK  ]\n" );

    ########################
    # load the config file #
    ########################

    printf( "%-50s", "Checking config");

    if ( ! -e $self->filename )
    {
        _print_red( "[ FAIL ]\n" );
        print $self->filename . " does not exist.\nExiting...\n";
        exit;
    }

    my $string = read_file( $self->filename, { binmode => ':utf8' } );

    my $config = undef;

    eval {
        $config = decode_json $string;
    };

    if ( $@ )
    {
        _print_red( "[ FAIL ]\n" );
        print "Config file error...\n" . $@ . "Exiting...\n";
        exit;
    }

    ###################################
    # basic checks on the config file #
    ###################################





    _print_green( "[  OK  ]\n" );

    return $self;
}

sub _print_green 
{
    my $string = shift;
    print color 'bold green'; 
    print $string;
    print color 'reset';
}

sub _print_orange 
{
    my $string = shift;
    print color 'bold orange'; 
    print $string;
    print color 'reset';
}

sub _print_red 
{
    my $string = shift;
    print color 'bold red'; 
    print $string;
    print color 'reset';
}

=head3 stop

Stops the FastCGI daemon.

=cut

sub stop
{
    my $self = shift;

    if ( ! -e $self->_pid )
    {
        return $self;
    }
    
    open( my $fh, "<", $self->_pid ) or die "Cannot open pidfile: $!";

    my @pids = <$fh>;

    close $fh;

    chomp( $pids[0] );

    print "Killing pid $pids[0] ...\n"; 

    kill 15, $pids[0];

    return $self;
}

=head3 restart

Restarts the FastCGI daemon, with a 1 second delay between stopping and starting.

=cut

sub restart
{
    my $self = shift;
    
    $self->stop;

    sleep 1;

    $self->start;

    return $self;
}

=head1 CONFIGURATION

The editor app should be a simple Perl script in a folder with the following structure:

 editor.pl      # see the synopsis
 editor.json    # see below
 editor.pid     # generated, to control the process
 editor.sock    # generated, to accept incoming FastCGI connections
 logs/
 editor-templates/
     404.tt

The config file is read for each and every request, this makes adding new pages easy, without the need to restart the application - you could even edit it's own files.

The config file should be placed in the C<base> directory of your editor application.

See the C<examples> directory for a sample JSON config file, something like the following...

 {
   
    ...
 }

The entire config hash is available in all templates via C<[% app.config %]>, there are only a couple of mandatory/reserved attributes.

=cut

# returns a code-ref for the FCGI handler/server.

sub _handler
{
    my $self = shift;

    return sub {

        ##############
        # initialise #
        ##############

        my $req = Plack::Request->new( shift );

        my %stash = (
            app      => $self,
            req      => $req,
            now      => DateTime->now,
            started  => join( '.', gettimeofday ),
        );

        my $log = Log::AutoDump->new( base_dir => $stash{ app }->base . '/logs', filename => 'editor.log' );

        $log->debug("Started");

        my $path = $req->uri->path;

        $log->debug( "Requested path: " . $path ); 

        $stash{ app }->_reload_config( log => $log );

        ################
        # do something #
        ################



        ##############################
        # responding with a template #
        ##############################

        my $res = $req->new_response;

        $res->status( 200 );

        my $tt = Template->new( ENCODING => 'UTF-8', INCLUDE_PATH => $stash{ app }->templates );

        $log->debug("Processing template: " . $stash{ app }->templates . "/" . $stash{ page }->{ template } );

        my $body = '';

        $tt->process( $stash{ page }->{ template }, \%stash, \$body ) or $log->debug( $tt->error );

        $res->content_type('text/html; charset=utf-8');

        $res->body( encode( "UTF-8", $body ) );

        #########
        # stats #
        #########

        $stash{ took } = join( '.', gettimeofday ) - $stash{ started };
        
        $log->debug( "The stash contains...", \%stash );
        
        $log->debug( "Took " . sprintf("%.5f", $stash{ took } ) . " seconds");

        #######################################
        # cleanup (circular references, etc.) #
        #######################################

        # need to do deep pages too!

        delete $stash{ page }->{ parents } if exists $stash{ page };

        return $res->finalize;
    }
}

sub _reload_config
{
    my ( $self, %args ) = @_;

    my $log = $args{ log };    

    $log->debug( "Opening config file: " . $self->filename );

    my $string = read_file( $self->filename, { binmode => ':utf8' } );

    my $config = undef;

    eval {
        $self->config( decode_json $string );
    };

    $log->debug( $@ ) if $@;

    return $self;
}

=head1 TODO




=head1 AUTHOR

Rob Brown, C<< <rob at intelcompute.com> >>

=head1 LICENSE AND COPYRIGHT

Copyright 2014 Rob Brown.

This program is free software; you can redistribute it and/or modify it
under the terms of either: the GNU General Public License as published
by the Free Software Foundation; or the Artistic License.

See http://dev.perl.org/licenses/ for more information.

=cut

1;

