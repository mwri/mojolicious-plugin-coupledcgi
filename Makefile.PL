#!/usr/bin/perl


use strict;
use warnings;

use ExtUtils::MakeMaker;


WriteMakefile(
	'NAME'         => 'Mojolicious::Plugin::CoupledCGI',
	'VERSION_FROM' => 'lib/Mojolicious/Plugin/CoupledCGI.pm',
	'TESTS'        => 't',
);
