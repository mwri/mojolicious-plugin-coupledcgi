# Mojolicious::Plugin::CoupledCGI - Mojolicious CGI script implementation

Mojolicious CGI process. Inherits from Mojolicious::Plugin and
Mojo::EventEmitter, and uses Mojolicious::Plugin::ForkCoupled, adding
behaviour appropriate for a CGI script. This means reading the headers from
the CGI script, and setting them, followed by the data itself.

## Contents

1. [Synopsis](#synopsis).
2. [Methods](#methods).
   1. [config_cgi](#config_cgi).
   2. [child](#child).
   3. [path](#path).
   4. [env](#env).
3. [Environment variables](#environment-variables).
4. [Author](#author).

## Synopsis

Example Mojolicious lite app implementing gitweb:

```perl
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
foreach my $file ('git-favicon.png', 'git-logo.png', 'gitweb.css', 'gitweb.js') {
    app->routes->get('/static/'.$file => sub {
        shift->reply->static($file);
    });
}

app->start;
```

In a non Mojolicious lite a CGI script can be registered the same way:

```perl
$app->cgi(
    'path' => '/gitweb',
    'cmd'  => '/usr/share/gitweb/gitweb.cgi',
    'env'  => {
        'GIT_PROJECT_ROOT' => '/var/lib/git',
    },
);
```

When the plugin is registered, defaults can be set, which will be overridden
if the same parameter is used when the specific CGI script is configured:

```perl
$app->plugin('Mojolicious::Plugin::CoupledCGI' => {
    'env'  => {
        'GIT_PROJECT_ROOT' => '/var/lib/git',
    },
});

$app->cgi(
    'path' => '/gitweb',
    'cmd'  => '/usr/share/gitweb/gitweb.cgi',
);
```

A CGI script can be configured without the plugin being registered (you must
pass the controller though):

```perl
Mojolicious::Plugin::CoupledCGI->config_cgi(
    'ctrlr' => $c,
    'path'  => '/gitweb',
    'cmd'   => '/usr/share/gitweb/gitweb.cgi',
    'env'   => {
        'GIT_PROJECT_ROOT' => '/var/lib/git',
    },
);
```

See 'config_cgi' for a full list of all the parameters supported.

## Methods

### config_cgi

```perl
my $cgi = Mojolicious::Plugin::CoupledCGI->config_cgi(
    'ctrlr' => $c,
    'path'  => '/gitweb',
    'cmd'   => '/usr/share/gitweb/gitweb.cgi',
    'env'   => {
        'GIT_PROJECT_ROOT' => '/var/lib/git',
    },
);
```

The following options are supported:

  * ctrlr - the Mojolicious controller, required if invoked directly (not via the plugin).
  * path - the URL path that will invoke the CGI script.
  * cmd - the CGI script full path, also accepts an array ref, in which case this is taken as the command followed by arguments.
  * quash_stderr - any STDERR output from the CGI script is dropped.
  * merge_stderr - any STDERR output from the CGI script is merged with the STDOUT output.
  * pre_exec_cb - a CODEREF, or array reference of CODEREFs, which will be executed by the child process before exec.
  * env - a hash reference of environment variables that will be set for the CGI script, besides the default ones (see below).

### child

Return the 'child' (the underlying Mojo::MyFork object).

### path

Return the path (the URL of the CGI script).

### env

Return the static environment setup for the CGI script.

## Environment variables

Certain environment variables are set for the CGI script, so that it can
function correctly. Mostly these are those specified in RFC 3875, but also
others. You can set arbitrary environment variables in addition using the
'env' parameter to 'config_cgi' (or the 'cgi' helper if the plugin is
registered).

The following environment variables are set, but will be overridden if
specified using the 'env' parameter:

  * PATH - The UNIX shell path.
  * SERVER_SOFTWARE - The server software.

The request headers are added as environment variables by prepending "HTTP_"
and changing dashes to underscores, thus "Content-Type" becomes
"HTTP_CONTENT_TYPE".

Finally the following are added:

  * CONTENT_LENGTH - the length of the request body, if there is one.
  * CONTENT_TYPE - set to the content type (from the request header).
  * GATEWAY_INTERFACE - set to "CGI/1.1".
  * PATH_INFO - the excess URL path, after tge CGI script (see RFC 3875).
  * QUERY_STRING - the query string, if there is one.
  * REMOTE_ADDR - the remote address (of the client).
  * LOCAL_ADDR - the local address (of the server).
  * REMOTE_HOST - the remote hostname (of the client).
  * REQUEST_METHOD - the request method.
  * SERVER_NAME - the virtual name of the server.
  * SCRIPT_FILENAME - the CGI script filename.
  * SERVER_PORT - the local port (of the server).
  * SERVER_PROTOCOL - the protocol name and version (e.g. "HTTP/1.1").
  * REMOTE_PORT - the report port (of the client).
  * REQUEST_URI - the request
  * REQUEST_URI - the path and query string (e.g. "/path/script?foo=bar").

## Author

Copyright (C) 2015-2016 Michael Wright <mjw@methodanalysis.com>.
