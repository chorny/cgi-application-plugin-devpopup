package CGI::Application::Plugin::DevPopup;

use warnings;
use strict;

our $VERSION = '0.01';

use base 'Exporter';
use HTML::Template;
use CGI::Application 4.01;

our @EXPORT = qw/ devpopup /;

my ( $head, $script, $template );                       # html stuff for our screen

sub import
{
    my $caller = scalar(caller);
    $caller->add_callback( 'postrun', \&_devpopup_output );
    $caller->new_hook('devpopup_report');
    goto &Exporter::import;
}

sub devpopup
{
    my $app = shift;                                    # a cgiapp object
    my $dp  = $app->param('__CAP_DEVPOPUP');
    unless ($dp)
    {
        $dp = bless [], __PACKAGE__;
        $app->param( '__CAP_DEVPOPUP' => $dp );
    }
    return $dp;
}

sub add_report
{
    my $self   = shift;                                 # a devpopup object
    my %params = @_;
    push @$self, \%params;                              # no validation just yet. Hey, this is 0.01!
}

sub _devpopup_output
{
    my ( $self, $outputref ) = @_;

    return unless $self->header_type eq 'header';       # don't operate on redirects or 'none'
    my %props = $self->header_props;
    my ($type) = grep /type/i, keys %props;
    return if defined $type and                         # no type defaults to html, so we have work to do.
      $props{$type} !~ /html/i;                         # else skip any other types.

    
    $self->call_hook( 'devpopup_report', $outputref );  # process our callback hook

    my $devpopup = $self->devpopup;
    my $tmpl = HTML::Template->new(
                                    scalarref         => \$template,
                                    die_on_bad_params => 0,
                                    loop_context_vars => 1,
                                  );
    $tmpl->param(
                  reports   => $devpopup,
                  app_class => ref($self),
                  runmode   => $self->get_current_runmode,
                );
    
    my $o = _escape_js($tmpl->output);
    my $h = _escape_js($head);
    my $j = _escape_js($script . join($/, map { $_->{script} } grep exists $_->{script},  @$devpopup) );

    my $js = qq{
	<script language="javascript">
	var devpopup_window = window.open("", "devpopup_window", "height=400,width=600");
	devpopup_window.document.write("$h");
	devpopup_window.document.write("$j");
	devpopup_window.document.write("\t<");
	devpopup_window.document.write("/script>");
	devpopup_window.document.write("$o");
	devpopup_window.document.close();
	devpopup_window.focus();
	</script>
	};

    # insert the js code before the body close,
    # if one exists
    if ( $$outputref =~ m!</body>!i )
    {
        $$outputref =~ s!</body>!$js\n</body>!i;
    }
    else
    {
        $$outputref .= $js;
    }
}

sub _escape_js
{
    my $j = shift;
    $j =~ s/\\/\\\\/g;
    $j =~ s/"/\\"/g;
    $j =~ s/\n/\\n" + \n\t"/g;
    $j;
}

$head = <<HEAD;
<?xml version="1.0"?>
<!DOCTYPE html PUBLIC "-//W3C//DTD XHTML 1.0 Transitional//EN"
    "http://www.w3.org/TR/xhtml1/DTD/xhtml1-transitional.dtd">

<html xmlns="http://www.w3.org/1999/xhtml">
<head>
	<title>Devpopup results</title>
	<style type="text/css">
		div.report { border: dotted 1px black; margin: 1em;}
		div.report h2 { color: #000; background-color: #ddd; padding:.2em; margin-top:0;}
		div.report_full, div.report_summary { padding: 0em 1em; }
		a:hover, div.report h2:hover { cursor: pointer; background-color: #eee; }
		a { text-decoration: underline }
	</style>
HEAD

$script = <<JS;
	<script type="text/javascript">
		function swap(id1,id2)
		{
			var d1 = document.getElementById(id1);
			var d2 = document.getElementById(id2);
			var s = d1.style.display;
			d1.style.display = d2.style.display;
			d2.style.display = s;
		}
JS

$template = <<TMPL;
</head>
<body>
<h1>Devpopup report for <tmpl_var app_class> -&gt; <tmpl_var runmode></h1>
<div id="titles">
<ul>
<tmpl_loop reports>
    <li><a onclick="swap('#DPS<tmpl_var __counter__>','#DPR<tmpl_var __counter__>')"><tmpl_var title></a> - <tmpl_var summary></li>
</tmpl_loop>
</ul>

<tmpl_loop reports>
<div id="#DP<tmpl_var __counter__>" class="report">
	<h2 id="#DPH<tmpl_var __counter__>"
	    onclick="swap('#DPS<tmpl_var __counter__>','#DPR<tmpl_var __counter__>')">
		<tmpl_var title>
	</h2>
	<div id="#DPS<tmpl_var __counter__>" class="report_summary">
		<tmpl_var summary>
	</div>
	<div id="#DPR<tmpl_var __counter__>" class="report_full" style="display:none"><tmpl_var report></div>
</div>
</tmpl_loop>

</body>
</html>
TMPL

=head1 NAME

CGI::Application::Plugin::DevPopup - Runtime cgiapp info in a popup window

=head1 VERSION

Version 0.01

=head1 SYNOPSIS

=head2 End user information

This module provides a plugin framework for displaying runtime information
about your CGI::Application app in a popup window. A sample Timing plugin is
provided to show how it works:

    use CGI::Application::Plugin::DevPopup;
    use CGI::Application::Plugin::DevPopup::Timing;

    The rest of your application follows
    ...

Now whenever you access a runmode, a window pops up over your content, showing
information about how long the various stages have taken. Adding other
CAP::DevPopup plugins will get you more information. A HTML::Tidy plugin
showing you how your document conforms to W3C standards is in the works. 

=head2 Developer information

Creating a new plugin for DevPopup is fairly simple. CAP::DevPopup registers a
new callback point (named C<devpopup_report>),  which it uses to collect output
from your plugin. You can add a callback to that point, and return your
formatted output from there. The callback has this signature:

    sub callback($cgiapp_class, $outputref)

You pass your output to the devpopup object by calling

    $cgiapp_class->devpopup->add_report(
                title   => $title,
                summary => $summary,
                report  => $body
	);

You are receiving $outputref, because DevPopup wants to be the last one to be
called in the postrun callback. If you had wanted to act at postrun time, then
please do so with this variable, and not through a callback at postrun.

=head1 EXPORTS

=over 4

=item * devpopup

This method is the only one exported into your module, and can be used to
access the underlying DevPopup object. See below for the methods that this
object exposes.

=back

=head1 METHODS

=over 4

=item * add_report( %fields )

Adds a new report about the current run of the application. The following
fields are supported:

=over 8

=item * title

A short title for your report

=item * summary

An optional one- or two-line summary of your findings

=item * report

Your full output

=item * script

If you have custom javascript, then please pass it in through this field.
Otherwise if it's embedded in your report, it will break the popup window. I
will take care of the surrounding C<<script>> tags, so just the code body is
needed.

=back

=back

=head1 AUTHOR

Rhesa Rozendaal, C<rhesa@cpan.org>

=head1 BUGS

Please report any bugs or feature requests to
C<bug-cgi-application-plugin-devpopup@rt.cpan.org>, or through the web
interface at
L<http://rt.cpan.org/NoAuth/ReportBug.html?Queue=CGI-Application-Plugin-DevPopup>.
I will be notified, and then you'll automatically be notified of progress on
your bug as I make changes.

=head1 ACKNOWLEDGEMENTS

=over

=item Mark Stosberg for the initial idea, and for pushing me to write it.

=item Sam Tregar for providing me with the skeleton cgiapp_postrun.

=back

=head1 COPYRIGHT & LICENSE

Copyright 2005 Rhesa Rozendaal, all rights reserved.

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.

=cut

1;    # End of CGI::Application::Plugin::DevPopup