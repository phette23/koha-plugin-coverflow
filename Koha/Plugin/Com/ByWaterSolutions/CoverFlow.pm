package Koha::Plugin::Com::ByWaterSolutions::CoverFlow;

## It's good practive to use Modern::Perl
use Modern::Perl;

## Required for all plugins
use base qw(Koha::Plugins::Base);

## We will also need to include any Koha libraries we want to access
use C4::Context;
use C4::Members;
use C4::Auth;
use C4::Reports::Guided;
use MARC::Record;
use C4::Koha qw(GetNormalizedISBN);
#use Koha::Caches; FIXME not actually being used and causes error in some version
use JSON;
use Business::ISBN;
use JavaScript::Minifier qw(minify);


## Here we set our plugin version
our $VERSION = "{VERSION}";

## Here is our metadata, some keys are required, some are optional
our $metadata = {
    name            => 'CoverFlow plugin',
    author          => 'Kyle M Hall',
    description     => 'Convert a report into a coverflow style widget!',
    date_authored   => '2014-06-29',
    date_updated    => '2014-06-29',
    minimum_version => '3.16',
    maximum_version => undef,
    version         => $VERSION,
};

## This is the minimum code required for a plugin's 'new' method
## More can be added, but none should be removed
sub new {
    my ( $class, $args ) = @_;

    ## We need to add our metadata here so our base class can access it
    $args->{'metadata'} = $metadata;
    $args->{'metadata'}->{'class'} = $class;

    ## Here, we call the 'new' method for our base class
    ## This runs some additional magic and checking
    ## and returns our actual $self
    my $self = $class->SUPER::new($args);

    return $self;
}

## The existance of a 'tool' subroutine means the plugin is capable
## of running a tool. The difference between a tool and a report is
## primarily semantic, but in general any plugin that modifies the
## Koha database should be considered a tool
sub report {
    my ( $self, $args ) = @_;

    my $cgi = $self->{'cgi'};

    my $template = $self->get_template( { file => 'report.tt' } );

    my $json = get_report( { cgi => $cgi } );
    my $data = from_json($json);

    $template->param(
            'data'      => $data,
            coverlinks  => $self->retrieve_data('coverlinks'),
            showtitle   => $self->retrieve_data('showtitle'),
            size_limit  => $self->retrieve_data('size_limit'),
            title_limit => $self->retrieve_data('title_limit'),
            use_coce => $self->retrieve_data('use_coce'),
            );

    print $cgi->header(
        {
            -type     => 'text/html',
            -charset  => 'UTF-8',
            -encoding => "UTF-8"
        }
    );
    print $template->output();
}

## If your tool is complicated enough to needs it's own setting/configuration
## you will want to add a 'configure' method to your plugin like so.
## Here I am throwing all the logic into the 'configure' method, but it could
## be split up like the 'report' method is.
sub configure {
    my ( $self, $args ) = @_;
    my $cgi = $self->{'cgi'};

    unless ( $cgi->param('save') ) {
        my $template = $self->get_template( { file => 'configure.tt' } );

        ## Grab the values we already have for our settings, if any exist
        $template->param(
                mapping => $self->retrieve_data('mapping'),
                coverlinks => $self->retrieve_data('coverlinks'),
                showtitle => $self->retrieve_data('showtitle'),
                custom_image => $self->retrieve_data('custom_image'),
                size_limit => $self->retrieve_data('size_limit'),
                title_limit => $self->retrieve_data('title_limit'),
                use_coce => $self->retrieve_data('use_coce'),
                );


        print $cgi->header(
            {
                -type     => 'text/html',
                -charset  => 'UTF-8',
                -encoding => "UTF-8"
            }
        );
        print $template->output();
    }
    else {
        my $coverlinks = $cgi->param('coverlinks') ? 1:0;
        my $use_coce = $cgi->param('use_coce') ? 1:0;
        my $showtitle = $cgi->param('showtitle') ? 1:0;
        my $custom_image = $cgi->param('custom_image');
        $self->store_data(
            {
                mapping            => $cgi->param('mapping'),
                coverlinks         => $coverlinks,
                showtitle          => $showtitle,
                custom_image       => $custom_image,
                size_limit         => $cgi->param('size_limit'),
                title_limit        => $cgi->param('title_limit'),
                last_configured_by => C4::Context->userenv->{'number'},
                use_coce => $use_coce,
            }
        );

        my $error = q{};
        my $yaml  = $cgi->param('mapping') . "\n\n";
        if ( $yaml =~ /\S/ ) {
            my $mapping;
            eval { $mapping = YAML::Load($yaml); };
            my $error = $@;
            if ($error) {
                my $template =
                  $self->get_template( { file => 'configure.tt' } );
                $template->param(
                    error   => $error,
                    mapping => $self->retrieve_data('mapping'),
                );
                print $cgi->header(
                    {
                        -type     => 'text/html',
                        -charset  => 'UTF-8',
                        -encoding => "UTF-8"
                    }
                );
                print $template->output();
            }
            else {
                $self->update_opacuserjs($mapping, $custom_image);
                $self->go_home();
            }
        }
    }
}

## This is the 'install' method. Any database tables or other setup that should
## be done when the plugin if first installed should be executed in this method.
## The installation method should always return true if the installation succeeded
## or false if it failed.
sub install() {
    my ( $self, $args ) = @_;

    my $OPACUserCSS = C4::Context->preference('OPACUserCSS');
    $OPACUserCSS =~ s/\/\* CSS for Koha CoverFlow Plugin.*End of CSS for Koha CoverFlow Plugin \*\///gs;
    $OPACUserCSS .= q(
/* CSS for Koha CoverFlow Plugin 
   This CSS was added automatically by installing the CoverFlow plugin
   Please do not modify */
.coverflow {
    height:160px;
    margin-left:25px;
    width:850px;
}

.coverflow img,.coverflow .item {
    -moz-border-radius:10px;
    -moz-box-shadow:0 5px 5px #777;
    -o-border-radius:10px;
    -webkit-border-radius:10px;
    -webkit-box-shadow:0 5px 5px #777;
    border-radius:10px;
    box-shadow:0 5px 5px #777;
    height:100%;
    width:100%;
}

.itemTitle {
    padding-top:30px;
}

.coverflow .selectedItem {
    -moz-box-shadow:0 4px 10px #0071BC;
    -webkit-box-shadow:0 4px 10px #0071BC;
    border:1px solid #0071BC;
    box-shadow:0 4px 10px #0071BC;
}
/* End of CSS for Koha CoverFlow Plugin */
    );
    C4::Context->set_preference( 'OPACUserCSS', $OPACUserCSS );

    return 1;
}

## This method will be run just before the plugin files are deleted
## when a plugin is uninstalled. It is good practice to clean up
## after ourselves!
sub uninstall() {
    my ( $self, $args ) = @_;
}

sub get_report {
    my ($params) = @_;

    my $report_id   = $params->{'id'};
    my $report_name = $params->{'name'};
    my $sql_params  = $params->{'sql_params'};
    my @sql_params;

    my $cgi = $params->{'cgi'};
    if ($cgi) {
        $report_id   ||= $cgi->param('id');
        $report_name ||= $cgi->param('name');
        @sql_params  = $cgi->multi_param('sql_params');
    }

    my $report_rec = get_saved_report(
        $report_name ? { 'name' => $report_name } : { 'id' => $report_id } );
    if ( !$report_rec ) { die "There is no such report.\n"; }

    #die "Sorry this report is not public\n" unless $report_rec->{public};

     $sql_params ||= \@sql_params;
     my $cache;#        = Koha::Caches->get_instance();
     my $cache_active;# = $cache->is_cache_active;
     my ( $cache_key, $json_text );
#    if ($cache_active) {
#        $cache_key =
#            "opac:report:"
#          . ( $report_name ? "name:$report_name" : "id:$report_id" )
#          . join( '-', @sql_params );
#        $json_text = $cache->get_from_cache($cache_key);
#    }

    unless ($json_text) {
        my $offset = 0;
        my $limit  = C4::Context->preference("SvcMaxReportRows") || 10;
        my $sql    = $report_rec->{savedsql};

        # convert SQL parameters to placeholders
        $sql =~ s/(<<.*?>>)/\?/g;

        my ( $sth, $errors ) =
          execute_query( $sql, $offset, $limit, $sql_params );
        if ($sth) {
            my $lines;
            $lines = $sth->fetchall_arrayref( {} );
            map { $_->{isbn} = GetNormalizedISBN( $_->{isbn} ) } @$lines;
            $json_text = to_json($lines);

#            if ($cache_active) {
#                $cache->set_in_cache( $cache_key, $json_text,
#                    { expiry => $report_rec->{cache_expiry} } );
#            }
        }
        else {
            $json_text = to_json($errors);
        }
    }

    return $json_text;
}

sub update_opacuserjs {
    my ($self, $mapping, $custom_image) = @_;

    my $opacuserjs = C4::Context->preference('opacuserjs');
    $opacuserjs =~ s/\n\/\* JS for Koha CoverFlow Plugin.*End of JS for Koha CoverFlow Plugin \*\///gs;

    my $template = $self->get_template( { file => 'opacuserjs.tt' } );
    $template->param( 'mapping' => $mapping );
    $template->param( 'custom_image' => $custom_image );

    my $coverflow_js = $template->output();

    $coverflow_js = minify( input => $coverflow_js );

    $coverflow_js = qq|\n/* JS for Koha CoverFlow Plugin 
   This JS was added automatically by installing the CoverFlow plugin
   Please do not modify */|
      . $coverflow_js
      . q|/* End of JS for Koha CoverFlow Plugin */|;


    $opacuserjs .= $coverflow_js;
    C4::Context->set_preference( 'opacuserjs', $opacuserjs );
}

1;
