package Mojolicious::Plugin::CoupledCGI;

use base 'Mojolicious::Plugin', 'Mojo::EventEmitter';


=head1 NAME

Mojolicious::Plugin::CoupledCGI - Mojolicious CGI script implementation

=head1 DESCRIPTION

Mojolicious CGI process. Inherits from L<Mojolicious::Plugin> and
L<Mojo::EventEmitter>, and uses L<Mojolicious::Plugin::ForkCoupled>,
adding behaviour appropriate for a CGI script. This means reading
the headers from the CGI script, and setting them, followed by
the data itself.

=head1 SYNOPSIS

Example Mojolicious lite app implementing gitweb:

    use Mojolicious::Lite;
    use Mojolicious::Plugin::CoupledCGI;
    
    app->plugin('Mojolicious::Plugin::CoupledCGI');
    
    app->cgi(
        'path' => '/gitweb',
        'cmd'  => '/usr/share/gitweb/gitweb.cgi',
        'env'  => {
            'GIT_PROJECT_ROOT' => '/var/lib/git',
            },
        );
    
    app->static->paths->[0] = '/usr/share/gitweb/static';
    foreach my $file (
            'git-favicon.png', 'git-logo.png', 'gitweb.css', 'gitweb.js'
            ) {
        app->routes->get('/static/'.$file => sub {
            shift->reply->static($file);
        });
    }
    
    app->start;

In a non Mojolicious lite a CGI script can be registered the same way:

    $app->cgi(
        'path' => '/gitweb',
        'cmd'  => '/usr/share/gitweb/gitweb.cgi',
        'env'  => {
            'GIT_PROJECT_ROOT' => '/var/lib/git',
            },
        );

When the plugin is registered, defaults can be set, which will be overridden
if the same parameter is used when the specific CGI script is configured:

    $app->plugin('Mojolicious::Plugin::CoupledCGI' => {
        'env'  => {
            'GIT_PROJECT_ROOT' => '/var/lib/git',
            },
		});
    
    $app->cgi(
        'path' => '/gitweb',
        'cmd'  => '/usr/share/gitweb/gitweb.cgi',
        );

A CGI script can be configured without the plugin being registered (you must pass
the controller though):

    Mojolicious::Plugin::CoupledCGI->config_cgi(
        'ctrlr' => $c,
        'path'  => '/gitweb',
        'cmd'   => '/usr/share/gitweb/gitweb.cgi',
        'env'   => {
            'GIT_PROJECT_ROOT' => '/var/lib/git',
            },
        );

See L<'config_cgi'> for a full list of all the parameters supported.

=head1 METHODS

=cut


use strict;
use warnings;


use Mojolicious::Plugin::ForkCoupled;
use Socket;


our $VERSION = '1.0.0';


sub register {

	my $self     = shift;
	my $app      = shift;
	my $defaults = shift;

	$app->helper('cgi' => sub {
		my $ctrlr = shift;
		my %args  = @_;
		$self->config_cgi(
			%$defaults,
			%args,
			'ctrlr' => $ctrlr,
			);
	});

}


sub new {

	my $class = shift;
	my %args  = @_;

	return bless {}, $class;

}


=head2 config_cgi

    my $cgi = Mojolicious::Plugin::CoupledCGI->config_cgi(
        'ctrlr' => $c,
        'path'  => '/gitweb',
        'cmd'   => '/usr/share/gitweb/gitweb.cgi',
        'env'   => {
            'GIT_PROJECT_ROOT' => '/var/lib/git',
            },
        );

=over 4

=item * ctrlr - the Mojolicious controller, required if invoked directly
(not via the plugin).

=item * path - the URL path that will invoke the CGI script.

=item * cmd - the CGI script full path, also accepts an array ref, in
which case this is taken as the command followed by arguments.

=item * quash_stderr - any STDERR output from the CGI script is dropped.

=item * merge_stderr - any STDERR output from the CGI script is merged
with the STDOUT output.

=item * pre_exec_cb - a CODEREF, or array reference of CODEREFs, which
will be executed by the child process before exec.

=item * env - a hash reference of environment variables that will be set
for the CGI script, besides the default ones (see below).

=back

=cut


sub config_cgi {

	my $self = shift;
	my %args = @_;

	$self->{'_path'}     = $args{'path'};
	$self->{'_path_ext'} = $args{'path_ext'} || 0;
	$self->{'_env'}      = $args{'env'};
	$self->{'_args'}     = \%args;

	my $ctrlr = $args{'ctrlr'};
	my $app   = $ctrlr->app;

	$args{'pre_exec_cb'} = defined $args{'pre_exec_cb'}
		? ref $args{'pre_exec_cb'} ne 'ARRAY'
			? [ $args{'pre_exec_cb'} ]
			: $args{'pre_exec_cb'}
		: [];

	my $super_route = defined $args{'route'}
		? $args{'route'}
		: $app->routes;

	push @{$self->{'_args'}->{'pre_exec_cb'}}, \&_set_cgi_env;
	$self->{'_args'}->{'ref'} = $self;

	$super_route->any($args{'path'} => sub {
		$_[0]->stash('path_info', '');
		$self->_cgi_invocation(@_);
	});
	if ($self->{'_path_ext'}) {
		$super_route->any($args{'path'}.'*path_info' => sub {
			$self->_cgi_invocation(@_);
		});
	}

	return $self;

}


sub _cgi_invocation {

	my $self  = shift;
	my $ctrlr = shift;

	my $app = $ctrlr->app;
	my $log = $app->log;

	$ctrlr->render_later;

	$self->{'_args'}->{'ctrlr'} = $ctrlr;

	my $child = Mojolicious::Plugin::ForkCoupled->new->fork_exec(%{$self->{'_args'}});

	my $all_hdrs_rcvd  = 0;
	my $some_hdrs_rcvd = 0;
	$child->on('read_stdout' => sub {
		my ($self, $stream, $data) = @_;
		if (!$ctrlr->tx) {
			$child->abort;
			return;
		}
		if ($all_hdrs_rcvd) {
			$ctrlr->write($data);
		} else {
			while (my ($hdr, $hdrval, $more) = $data =~ /^(\S+):\s*(\S.*?)\r?\n(.*)/s) {
				$some_hdrs_rcvd = 1;
				$ctrlr->res->headers->header($hdr => $hdrval);
				$data = $more;
			}
			if ($data) {
				$all_hdrs_rcvd = 1;
				$log->warn($self->cmd.' ['.$self->pid.']: malformed HTTP header or no empty line after')
					if $data !~ /^\r?\n/ && $some_hdrs_rcvd;
				$log->warn($self->cmd.' ['.$self->pid.']: no HTTP headers received')
					if !$some_hdrs_rcvd;
				$data =~ s/^\r?\n//;
				$ctrlr->write($data);
			}
		}
	});

	$child->on('read_stderr' => sub {
		my ($self, $stream, $data) = @_;
		chomp $data;
		foreach my $line (split /^/, $data) {
			chomp $line;
			$log->error($child->cmd.' ['.$child->pid.']: STDERR: '.$line)
		}
	});

	$child->on('finish_stdout' => sub {
		if ($ctrlr->tx) {
			$ctrlr->finish;
		} else {
			$log->error($child->cmd.' ['.$child->pid.']: Client disconnected while CGI running');
		}
	});

}


sub _set_cgi_env {

	my $child = shift;

	my $self     = $child->ref;
	my $ctrlr    = $child->ctrlr;
	my $tx       = $ctrlr->tx;
	my $req      = $tx->req;
	my $req_hdrs = $req->headers;

	my $path_info       = $ctrlr->stash('path_info');
	my $remote_hostname = gethostbyaddr(inet_aton($tx->remote_address), AF_INET);

	my $script_name = $req->url->to_abs->path;
	$script_name =~ s/\/?${path_info}$//;

	no strict 'refs';
	my $server_software = ref($self).'/'.${ref($self).'::VERSION'};
	use strict 'refs';

	my $request_uri = $req->url->to_abs->path;
	$request_uri .= '?'.$req->url->query->to_string if $req->url->query->to_string;

	my %hdrs_env;
	foreach my $hdr (@{$req_hdrs->names}) {
		my $hdrval = $req_hdrs->header($hdr);
		$hdrval =~ s/-/_/g;
		$hdrs_env{'HTTP_'.uc($hdr)} = $hdrval;
	}

	my %cgi_env = (
		'PATH'                  => '/bin:/usr/bin',
		'SERVER_SOFTWARE'       => $server_software,
		%{$self->env},
		%hdrs_env,
		'CONTENT_LENGTH'        => defined $req->body ? length $req->body : 0,
		'CONTENT_TYPE'          => $req_hdrs->content_type,
		'GATEWAY_INTERFACE'     => 'CGI/1.1',
		'PATH_INFO'             => '/'.$path_info,
		'QUERY_STRING'          => $req->url->query->to_string,
		'REMOTE_ADDR'           => $tx->remote_address,
		'LOCAL_ADDR'            => $tx->local_address,
		'REMOTE_HOST'           => $remote_hostname || $tx->remote_address,
		'REQUEST_METHOD'        => $req->method,
		'SERVER_NAME'           => $req->url->to_abs->host,
		'SCRIPT_FILENAME'       => $child->cmd,
		'SERVER_PORT'           => $tx->local_port,
		'SERVER_PROTOCOL'       => 'HTTP/'.$req->version,
		'REMOTE_PORT'           => $tx->remote_port,
		'REQUEST_URI'           => $request_uri,
		);

	delete $ENV{$_} foreach grep { !exists $cgi_env{$_} } keys %ENV;

	$ENV{$_} = $cgi_env{$_} foreach keys %cgi_env;

}


=head2 child

Return the 'child' (the underlying L<Mojo::MyFork> object).

=head2 path

Return the path (the URL of the CGI script).

=head2 env

Return the static environment setup for the CGI script.

=cut

sub child { $_[0]->{'_child'} }
sub path  { $_[0]->{'_path'}  }
sub env   { $_[0]->{'_env'}   }


=head2 ENVIRONMENT VARIABLES

Certain environment variables are set for the CGI script, so that it can
function correctly. Mostly these are those specified in RFC 3875, but also
others. You can set arbitrary environment variables in addition using the
'env' parameter to L<'config_cgi'> (or the 'cgi' helper if the plugin is
registered).

The following environment variables are set, but will be overridden if
specified using the 'env' parameter:

=over 4

=item PATH - The UNIX shell path.

=item SERVER_SOFTWARE - The server software.

=back

The request headers are added as environment variables by prepending
"HTTP_" and changing dashes to underscores, thus "Content-Type"
becomes "HTTP_CONTENT_TYPE"

Finally the following are added:

=over 4

=item * CONTENT_LENGTH - the length of the request body, if there is one.

=item * CONTENT_TYPE - set to the content type (from the request header).

=item * GATEWAY_INTERFACE - set to "CGI/1.1".

=item * PATH_INFO - the excess URL path, after tge CGI script (see RFC 3875)

=item * QUERY_STRING - the query string, if there is one.

=item * REMOTE_ADDR - the remote address (of the client).

=item * LOCAL_ADDR - the local address (of the server).

=item * REMOTE_HOST - the remote hostname (of the client).

=item * REQUEST_METHOD - the request method.

=item * SERVER_NAME - the virtual name of the server.

=item * SCRIPT_FILENAME - the CGI script filename.

=item * SERVER_PORT - the local port (of the server).

=item * SERVER_PROTOCOL - the protocol name and version (e.g. "HTTP/1.1").

=item * REMOTE_PORT - the report port (of the client).

=item * REQUEST_URI - the request URI; the path and query string (e.g.
"/path/script?foo=bar").

=back

=head1 AUTHOR

Copyright (C) 2015-2016 Michael Wright <mjw@methodanalysis.com>. All rights reserved.

=cut


1;
