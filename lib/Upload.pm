#
# nautilus-flickr-uploader - upload pics to Flickr from Nautilus
# Copyright (C) 2009-2014  Juan J. Martinez <jjm@usebox.net>
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <http://www.gnu.org/licenses/>.
#
package Upload;

use strict;
use warnings;
use threads;
use threads::shared;

use Encode;
use Time::HiRes qw(sleep);

use Upload::Callbacks;

require Exporter;
use vars qw ( @EXPORT_OK );
@EXPORT_OK = qw ( $gladexml $thread_limit );
use vars qw( $gladexml $sdbus $serviceObject $busy $thread_limit );

use Locale::gettext;

use Net::DBus::GLib;
use Service;

use Gtk2 '-init' ;
use Gtk2::GladeXML;
use Gtk2::Ex::Simple::List;

use File::Basename;
use File::Temp;
use Image::Magick;

use Net::OAuth;
$Net::OAuth::PROTOCOL_VERSION = Net::OAuth::PROTOCOL_VERSION_1_0A;

use LWP::UserAgent;
use LWP::MediaTypes qw( guess_media_type );
use HTTP::Request::Common;
use XML::Simple;

our ( @FILES, $accountVerified, $thumbsOk );

my $FLICKR_API_AUTH = "https://api.flickr.com/services/rest/";
my $FLICKR_API_UPLOAD = "https://up.flickr.com/services/upload/";

my @IDS : shared;
my %thread_queue : shared;
my $thread_mutex : shared;
my $thread_progress : shared;
my $thread_speed : shared;
share($thread_limit);

sub _
{
    return decode( 'utf8', gettext( shift ) );
}

#
# We accept both a directory or a list of images, but we must expand the
# directory before checking the files
#
sub ExpandDirectories
{
    my @list = @_;
    my @exts = ( '.jpg', '.jpeg', '.gif', '.png' );

    # first check if it's a directory
    if( scalar ( @list ) eq 1 && -d $list[0] )
    {
        my $directory = $list[0];
        opendir( DIR, $directory )
            || die ('Failed to open dir' .$directory);
        @list  = readdir( DIR );
        closedir( DIR );

        foreach( @list )
        {
            $_ = $directory .'/' .$_;
        }
    }

    # create a list of images, according to their extension
    my @newList;

    foreach( @list )
    {
        if( -f $_ )
        {
            my ($fname, $path, $ext) = fileparse( lc $_, @exts );
            push( @newList, $_ ) if $ext;
        }
    }

    return @newList;
}

#
# Calculate width/height using a max value
#
sub ResizeValue
{
    my ( $width, $height, $value ) = @_;

    if ( $width > $height )
    {
        $height = ($height * $value) / $width;
        $width = $value;
    }
    else
    {
        $width = ($width * $value) / $height;
        $height = $value;
    }

    return ( $width, $height );
}

#
# Load the photos into our list, using a fancy progress bar
#
sub LoadPhotos
{
    my $index = shift;

    my $progressBar = $gladexml->get_widget( 'ProgressBar' );
    my $speedButton = $gladexml->get_widget( 'SpeedButton' );
    $speedButton->set_label( "0.0 KiB/s" );
    $speedButton->set_sensitive( 0 );

    if( $index < 0 )
    {
        if( $accountVerified )
        {
            my $okButton = $gladexml->get_widget( 'OkButton' );
            $okButton->set_sensitive( 1 );
        }

        $progressBar->set_fraction( 0 );
        $progressBar->set_text( '' );

        my $progress = $gladexml->get_widget( 'progress_hbox' );
        $progress->hide( );

        $thumbsOk = 1;

        $busy = 0;
        my $add = $gladexml->get_widget( 'AddPicButton' );
        $add->set_sensitive( 1 );
        my $change = $gladexml->get_widget( 'ChangeUserButton' );
        $change->set_sensitive( 1 );

        return 0;
    }

    $busy = 1;
    my $add = $gladexml->get_widget( 'AddPicButton' );
    $add->set_sensitive( 0 );
    my $change = $gladexml->get_widget( 'ChangeUserButton' );
    $change->set_sensitive( 0 );

    my $file = $FILES[ $index ];

    $progressBar->set_text( basename( $file ) );

    my $slist = $gladexml->get_widget( 'PhotoView' );

    my $image;
    eval
    {
        # Gtk2::Gdk::Pixbuf->new_from_file is unable to handle UTF filenames
        $image = Gtk2::Gdk::Pixbuf->new_from_file( decode( 'utf8', $file ) );
    };

    if( !$@ && $image )
    {
        my $width = $image->get_width( );
        my $height = $image->get_height( );

        ( $width, $height ) = ResizeValue( $width, $height, 128 );

        $image = $image->scale_simple( $width, $height, 'bilinear' );

        push( @{$slist->{data}}, [ $image, basename( $file ), $file ] );
    }
    else
    {
        warn "Warning: failed to make a thumbnail from $file\n";
    }

    Glib::Idle->add( \&LoadPhotos, $index - 1 );

    return 0;
}

#
# Test flickr account
#
sub TestAccount
{
    my $conf = $main::config;
    my $rest_url = $FLICKR_API_AUTH ."?"
                  ."method=flickr.auth.oauth.checkToken&format=rest&"
                  ."api_key=" .$main::api->{'key'} ."&"
                  ."token=" .$conf->{'token'};
    my $request = Net::OAuth->request("protected resource")->new(
        consumer_key => $main::api->{'key'},
        consumer_secret => $main::api->{'secret'},
        token => $conf->{'token'},
        token_secret => $conf->{'token_secret'},
        request_url => $rest_url,
        request_method => 'GET',
        signature_method => 'HMAC-SHA1',
        timestamp => time(),
        nonce => '.' .time(),
        );

    $request->sign;

    my $lpw = LWP::UserAgent->new();
    $lpw->agent('NFU/'.$conf->{'version'} .' ' .$lpw->_agent);

    my $response = $lpw->get(
        $rest_url,
        Authorization => $request->to_authorization_header,
        );

    my $error_message;
    if ( $response->is_error )
    {
        $error_message = $response->message;
    }
    else
    {
        my $xml = XMLin($response->content);
        if ( $xml->{stat} ne 'ok' )
        {
            $error_message = $xml->{err}->{msg}; 
        }
        elsif ( $xml->{oauth}->{perms} ne 'write' )
        {
            $error_message = 'Not enough permissions, please re-authenticate'; 
        }
    }

    my $account = $gladexml->get_widget( 'UserLabel' );
    
    if( defined $error_message )
    {
        $account->set_text( 'Failed' );

        my $ok = $gladexml->get_widget( 'OkButton' );
        $ok->set_sensitive( 0 );

        my $errorBox = $gladexml->get_widget( 'ErrorBox' );
        $errorBox->show( );
        my $errorLabel = $gladexml->get_widget( 'ErrorLabel' );
        $errorLabel->set_markup( 
            '<small>' ._( "The verification of your Flickr account\nhas failed: " ) 
            .$error_message .'.</small>' );

        warn 'Warning: the verification of your Flickr account has failed';
    }
    else
    {
        my $errorBox = $gladexml->get_widget( 'ErrorBox' );
        $errorBox->hide( );

        $account->set_text( $conf->{username} );
        $accountVerified = 1;

        # if thumbs are OK and there's stuff to upload,
        # then enable the OK button
        my $list = $gladexml->get_widget( 'PhotoView' );
        if( $thumbsOk && scalar ( @{$list->{data}} ) )
        {
            my $okButton = $gladexml->get_widget( 'OkButton' );
            $okButton->set_sensitive( 1 );
        }
    }

    my $change = $gladexml->get_widget( 'ChangeUserButton' );
    $change->set_sensitive( 1 );
}

#
# Thread to upload files in backgroud.
#
sub Thread
{
    while( 1 )
    {
        # there's a picture to upload?
        if( $thread_mutex && %thread_queue )
        {
            $thread_mutex = 0;

            my $tmp_file;
            my $upload_file = $thread_queue{'file'};

            # zero size means don't resize at all
            if( $thread_queue{'resize'} )
            {
                $tmp_file = File::Temp->new(
                    TEMPLATE => 'NFU_resize_XXXXX',
                    UNLINK => 1, TMPDIR => 1 );
                if( $tmp_file )
                {
                    # TODO: error checking
                    my $im = Image::Magick->new( );

                    $im->Read( $upload_file );
                    $im->Resize( geometry => $thread_queue{'resize'} );

                    $upload_file = $tmp_file->filename;
                    $im->Write( file => $tmp_file, filename => $upload_file );
                    close( $tmp_file );
                    undef $im;
                }
                else
                {
                    warn 'Warning: failed to create a temporary file';
                }
            }

            $HTTP::Request::Common::DYNAMIC_FILE_UPLOAD = 1;
            my $lpw = LWP::UserAgent->new(keep_alive=>1);
            $lpw->agent('NFU-SSL/'.$thread_queue{'version'} .' ' .$lpw->_agent);

            # use the filename if the title is empty
            my $title = $thread_queue{'title'} ? 
                $thread_queue{'title'} : basename( $thread_queue{'file'} );

            my $request = Net::OAuth->request("protected resource")->new(
                consumer_key => $thread_queue{'api_key'},
                consumer_secret => $thread_queue{'api_secret'},
                token => $thread_queue{'token'},
                token_secret => $thread_queue{'token_secret'},
                request_url => $FLICKR_API_UPLOAD,
                request_method => 'POST',
                signature_method => 'HMAC-SHA1',
                timestamp => time(),
                nonce => $title .'.' .time(),
                extra_params => {
                    is_family => $thread_queue{'is_family'},
                    is_friend => $thread_queue{'is_friend'},
                    is_public => $thread_queue{'is_public'},
                    tags => $thread_queue{'tags'},
                    title => $title,
                    },
                );

            $request->sign;

            my $post_req = POST(
                $FLICKR_API_UPLOAD,
                Content_Type => 'multipart/form-data',
                Authorization => $request->to_authorization_header,
                Content => [
                    is_family => $thread_queue{'is_family'},
                    is_friend => $thread_queue{'is_friend'},
                    is_public => $thread_queue{'is_public'},
                    tags => encode_utf8( $thread_queue{'tags'} ),
                    title => encode_utf8( $title ),
                    photo => [ $upload_file,
                        basename( $thread_queue{'file'} ),
						"Content-Type" => guess_media_type( $thread_queue{'file'} ),
                     ], ] );

            my $file_size = -s $upload_file;
            my $progress = 0;

            my $partial = 0;
            my $speed_len = 0;
            my $time_now = sub { return sprintf( "%.2f", Time::HiRes::time( ) ); };
            my $now = &$time_now( );

            my $content = $post_req->content( );
            $post_req->content(
                sub {
                    my $chunk = &$content( );

                    if( $chunk )
                    {
                        $partial += length($chunk);
                        if( &$time_now( ) > $now )
                        {
                            if( &$time_now( ) - $now > 1 )
                            {
                                $speed_len = $partial;
                                $thread_speed = $speed_len / 1024;
                                $now = &$time_now( );
                                $partial = 0;
                            }
                        }

                        # throttle
                        if ( $thread_limit && $thread_speed >= $thread_limit )
                        {
                            sleep( ( length($chunk) * $thread_speed / $thread_limit ) / $speed_len );
                        }

                        $progress += length($chunk);
                        $thread_progress = $progress / $file_size;
                        $thread_progress = 1 if $thread_progress > 1;
                    }

                    return $chunk;
                }
            );

            my $response = $lpw->request( $post_req );
            if( $response->is_success )
            {
                my $xml = XMLin($response->content);
                if( !$response->is_success || $xml->{stat} ne 'ok')
                {
                    warn "Warning: failed to upload " .$thread_queue{'title'}
                        .': ' .$xml->{err}->{msg};
                }
                else
                {
                    push( @IDS, $xml->{photoid} );
                }
            }
            else
            {
                warn "Warning: failed to post to Flickr API: " .$response->status_line;
            }

            # we're done
            undef %thread_queue;
            threads->yield( );
        }
        else
        {
            threads->yield( );
        }
    }
}

#
# Check the thread queue each n msecs.
#
sub ThreadPoll
{
    my ($index, $total) = @{$_[0]};

    if( !%thread_queue )
    {
        $thread_speed = 0;
        $thread_progress = 0;

        Glib::Idle->add( \&UploadFiles, $index - 1 );
        return 0;
    }
    else
    {
        if ( $thread_progress )
        {
            my $progressBar = $gladexml->get_widget( 'ProgressBar' );
            $progressBar->set_fraction( (1 / $total) * $thread_progress + ( ( $total - ( $index + 1 ) ) / $total ) );

            my $speedButton = $gladexml->get_widget( 'SpeedButton' );
            $speedButton->set_label( sprintf( "%.1f KiB/s", $thread_speed ) );
        }
    }

    return 1;
}

#
# Upload one file per time.
#
sub UploadFiles
{
    my $index = shift;

    if( $index < 0 )
    {
        my $progressBar = $gladexml->get_widget( 'ProgressBar' );
        $progressBar->set_fraction( 0 );
        $progressBar->set_text( '' );
        my $progress = $gladexml->get_widget( 'progress_hbox' );
        $progress->hide( );

        if( !scalar( @IDS ) )
        {
            my $errorBox = $gladexml->get_widget( 'ErrorBox' );
            $errorBox->show( );
            my $errorLabel = $gladexml->get_widget( 'ErrorLabel' );
            $errorLabel->set_markup( 
                _( '<small>Something went wrong uploading the photos.</small>' ) );

            my $box = $gladexml->get_widget( 'MainBox' );
            $box->set_sensitive( 1 );

            my $add = $gladexml->get_widget( 'AddPicButton' );
            $add->set_sensitive( 1 );

            my $ok = $gladexml->get_widget( 'OkButton' );
            $ok->set_sensitive( 1 );
            return 0;
        }

        Gtk2->main_quit;

        Upload::Callbacks::SaveConfiguration( );

        exec( 'xdg-open', 
            'http://www.flickr.com/tools/uploader_edit.gne?ids='
            . join( ',', @IDS ) );
    }

    my $list = $gladexml->get_widget( 'PhotoView' );
    my $progressBar = $gladexml->get_widget( 'ProgressBar' );

    my $file = $list->{data}->[$index];
    my $total = scalar ( @{$list->{data}} );

    $progressBar->set_text( basename( $file->[2] ) );

    my $new_size = 0;

    my $resize = $gladexml->get_widget( 'ResizeCheckButton' );
    if( $resize->get_active( ) )
    {
        my $spin = $gladexml->get_widget( 'SizeSpinButton' );
        $new_size = scalar( $spin->get_value( ) );
    }

    my $tagsEntry = $gladexml->get_widget( 'TagsEntry' );
    my $tags = $tagsEntry->get_text( );

    my ( $is_public, $is_friend, $is_family ) = ( 1, 0, 0 );

    my $radio = $gladexml->get_widget( "RadioPrivate" );
    if( $radio->get_active( ) )
    {
        $is_public = 0;

        my $friends = $gladexml->get_widget( 'PrivateFriends' );
        $is_friend = $friends->get_active( );

        my $family = $gladexml->get_widget( 'PrivateFamily' );
        $is_family = $family->get_active( );
    }

    # new picture for the upload thread
    %thread_queue = (
        'version' => $main::config->{'version'},
        'api_key' => $main::api->{'key'},
        'api_secret' => $main::api->{'secret'},
        'token' => $main::config->{'token'},
        'token_secret' => $main::config->{'token_secret'},
        'is_public' => $is_public,
        'is_friend' => $is_friend,
        'is_family' => $is_family,
        'tags' => $tags,
        'title' => $file->[1],
        'file' => $file->[2],
        'resize' => $new_size,
        );

    $thread_mutex = 1;
    $thread_speed = 0;
    $thread_progress = 0;

    Glib::Timeout->add( 250, 'Upload::ThreadPoll', [ $index, $total ] );

    return 0;
}

sub Init
{
    $sdbus = Net::DBus::GLib->session;

    my $service;
    eval
    {
        $service = $sdbus->get_service( 'net.usebox.nautilusFlickrUploader' );
    };
    if( !$@ && $service )
    {
        exit( 0 ) if( !@ARGV );

        my $ob = $service->get_object( '/net/usebox/nautilusFlickrUploader',
            'net.usebox.nautilusFlickrUploader.remote' );
        my $res = $ob->add( join( '*', @ARGV ) );
        warn 'remote service failed while submitting files' if !$res;
        exit( $res != 1 );
    }

    $service = $sdbus->export_service( 'net.usebox.nautilusFlickrUploader' );
    $serviceObject = Service->new($service);

    $gladexml = Gtk2::GladeXML->new( './UI/Upload.glade' );

    $accountVerified = 0;
    $thumbsOk = 0;
    $busy = 0;

    Upload::Callbacks::Init( );

    $gladexml->signal_autoconnect_from_package( 'Upload::Callbacks' );

    my $slist = Gtk2::Ex::Simple::List->new_from_treeview (
            $gladexml->get_widget( 'PhotoView' ),
            'image'    => 'pixbuf',
            'name'     => 'text',
            'path'     => 'text',
        );

    $slist->get_column( 2 )->set_visible( 0 );
    $slist->set_column_editable ( 1, 1 );
    $slist->get_selection->set_mode( 'multiple' );

    # we want to receive files from nautilus using drag and drop
    $slist->drag_dest_set( ["drop","motion","highlight"],
        ["copy","private","default","move","link","ask"] );

    my $dndTargetList =Gtk2::TargetList->new( );
    my $atom = Gtk2::Gdk::Atom->new("text/uri-list");

    $dndTargetList->add( $atom, 0, 0 );
    $slist->drag_dest_set_target_list( $dndTargetList );

    @FILES = ExpandDirectories( @ARGV );

    if ( @FILES )
    {
        my $speedButton = $gladexml->get_widget( 'SpeedButton' );
        $speedButton->set_label( "0.0 KiB/s" );
        $speedButton->set_sensitive( 0 );

        Glib::Idle->add( \&LoadPhotos, $#FILES );
    }
    else
    {
        my $progress = $gladexml->get_widget( 'progress_hbox' );
        $progress->hide( );
    }

    # setup the GUI according to the stored configuration
    my $conf = $main::config;

    if( $conf->{'token'} )
    {
        my $account = $gladexml->get_widget( 'UserLabel' );
        $account->set_text( _( 'Authorizing...' ) );

        my $change = $gladexml->get_widget( 'ChangeUserButton' );
        $change->set_sensitive( 0 );

        Glib::Idle->add( \&TestAccount );
    }
    else
    {
        my $account = $gladexml->get_widget( 'UserLabel' );
        $account->set_text( _( 'No account' ) );
    }

    my $friends = $gladexml->get_widget( 'PrivateFriends' );
    $friends->set_sensitive( 0 );
    if ( $conf->{'friends'} eq 'yes' )
    {
        $friends->set_active( 1 );
    }

    my $family = $gladexml->get_widget( 'PrivateFamily' );
    $family->set_sensitive( 0 );
    if ( $conf->{'family'} eq 'yes' )
    {
        $family->set_active( 1 );
    }

    my $radioButton = 'RadioPublic';
    if ( $conf->{'privacy'} eq 'private' )
    {
        $radioButton = 'RadioPrivate';
        $friends->set_sensitive( 1 );
        $family->set_sensitive( 1 );
    }
    my $radio = $gladexml->get_widget( $radioButton );
    $radio->set_active( 1 );

    if( scalar( $conf->{'size'} ) )
    {
        my $spin = $gladexml->get_widget( 'SizeSpinButton' );
        $spin->set_value( scalar( $conf->{'size'} ) );
    }
    if( $conf->{'resize'} eq 'yes' )
    {
        my $resize = $gladexml->get_widget( 'ResizeCheckButton' );
        $resize->set_active( 1 );
    }

    my $errorBox = $gladexml->get_widget( 'ErrorBox' );
    $errorBox->hide( );
}

1 ; 
