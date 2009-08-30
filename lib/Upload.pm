#
# nautilus-flickr-uploader - upload pics to Flickr from Nautilus
# Copyright (C) 2009  Juan J. Martinez <jjm@usebox.net>
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

use Upload::Callbacks;

require Exporter;
use vars qw ( @EXPORT_OK );
@EXPORT_OK = qw ( $gladexml );
use vars qw( $gladexml );

use Locale::gettext;

use Gtk2 '-init' ;
use Gtk2::GladeXML;
use Gtk2::SimpleList;

use File::Basename;
use File::Temp;
use Image::Magick;

use Flickr::API;
use XML::Parser::Lite::Tree;
use LWP::UserAgent;

our ( @FILES, $accountVerified, $thumbsOk, @IDS );

sub _
{
	return gettext( shift );
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

	if( $index < 0 )
	{
		if( $accountVerified )
		{
			my $okButton = $gladexml->get_widget( 'OkButton' );
			$okButton->set_sensitive( 1 );
		}

		$progressBar->set_fraction( 0 );
		$progressBar->set_text( '' );
		$progressBar->hide( );

		$thumbsOk = 1;

		return 0;
	}

	my $file = $FILES[ $index ];

	$progressBar->set_text( basename( $file ) );

	my $slist = $gladexml->get_widget( 'PhotoView' );

	my $image;
	eval
	{
		$image = Gtk2::Gdk::Pixbuf->new_from_file( $file );
	};

	if( !$@ && $image )
	{
		my $width = $image->get_width( );
		my $height = $image->get_height( );

		( $width, $height ) = ResizeValue( $width, $height, 128 );

		$image = $image->scale_simple( $width, $height, 'bilinear' );

		push( @{$slist->{data}}, [ $image, basename( $file ), $file ] );

		$progressBar->set_fraction( ( scalar( @FILES ) - $index ) / scalar( @FILES ) );
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
	my $api = Flickr::API->new( $main::api );
	my $response = $api->execute_method( 'flickr.auth.checkToken',
		{ "auth_token" => $conf->{'token'} } );

	my $account = $gladexml->get_widget( 'UserLabel' );

	if( !$response->is_success || $response->{error_code} )
	{
		$account->set_text( 'Failed' );

		my $ok = $gladexml->get_widget( 'OkButton' );
		$ok->set_sensitive( 0 );

		my $errorBox = $gladexml->get_widget( 'ErrorBox' );
		$errorBox->show( );
		my $errorLabel = $gladexml->get_widget( 'ErrorLabel' );
		$errorLabel->set_markup( 
			'<small>' ._( "The verification of you Flickr account\nhas failed: " ) 
			.$response->{error_message} .'.</small>' );

		warn 'Warning: the verification of your Flickr account has failed';
	}
	else
	{
		my $errorBox = $gladexml->get_widget( 'ErrorBox' );
		$errorBox->hide( );

		$account->set_text( $conf->{username} );
		$accountVerified = 1;

		# if thumbs are OK, the enable the OK button
		if( $thumbsOk )
		{
			my $okButton = $gladexml->get_widget( 'OkButton' );
			$okButton->set_sensitive( 1 );
		}
	}

	my $change = $gladexml->get_widget( 'ChangeUserButton' );
	$change->set_sensitive( 1 );
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
		$progressBar->hide( );

		if( !scalar( @IDS ) )
		{
			my $errorBox = $gladexml->get_widget( 'ErrorBox' );
			$errorBox->show( );
			my $errorLabel = $gladexml->get_widget( 'ErrorLabel' );
			$errorLabel->set_markup( 
				_( '<small>Something went wrong uploading the photos.</small>' ) );
			return 0;
		}

		Gtk2->main_quit;

		Upload::Callbacks::SaveConfiguration( );

		exec( 'xdg-open', 
			'http://www.flickr.com/tools/uploader_edit.gne?ids='
			. join( ',', @IDS ) );
	}

	my $tmp_file;

	my $list = $gladexml->get_widget( 'PhotoView' );
	my $progressBar = $gladexml->get_widget( 'ProgressBar' );

	my $file = $list->{data}->[$index];
	my $total = scalar ( @{$list->{data}} );
	my $upload_file = $file->[2];

	$progressBar->set_text( $file->[1] );

	my $resize = $gladexml->get_widget( 'ResizeCheckButton' );
	if( $resize->get_active( ) )
	{
		$tmp_file = File::Temp->new( UNLINK => 1, TMPDIR => 1 );
		if( $tmp_file )
		{
			# TODO: error checking
			my $im = Image::Magick->new( );
			my $spin = $gladexml->get_widget( 'SizeSpinButton' );
			my $new_size = scalar( $spin->get_value( ) );

			$im->Read( $upload_file );
			$im->Resize( geometry => $new_size );

			$upload_file = $tmp_file->filename;
			$im->Write( file => $tmp_file );
			undef $im;
			close( $tmp_file );
		}
		else
		{
			warn 'Warning: fail to create a temporary file';
		}
	}

	my $tagsEntry = $gladexml->get_widget( 'TagsEntry' );
	my $tags = $tagsEntry->get_text( );

	my ( $is_public, $is_friend, $is_family ) = ( 1, 0, 0 );
	my $radio = $gladexml->get_widget( "RadioFamily" );
	if( $radio->get_active( ) )
	{
		( $is_public, $is_friend, $is_family ) = ( 0, 0, 1 );
	}
	$radio = $gladexml->get_widget( "RadioFriends" );
	if( $radio->get_active( ) )
	{
		( $is_public, $is_friend, $is_family ) = ( 0, 1, 0 );
	}

	my $lpw = LWP::UserAgent->new();

	my $signature = Digest::MD5::md5_hex(
		$main::api->{'secret'} .'api_key' .$main::api->{'key'}
		.'auth_token' .$main::config->{'token'}
		.'is_family' .$is_family
		.'is_friend' .$is_friend
		.'is_public' .$is_public
		.'tags' .$tags
		.'title' .$file->[1] );

	my $response = $lpw->post(
		'http://api.flickr.com/services/upload/',
		Content_Type => 'multipart/form-data',
		Content => [
			api_sig => $signature,
			api_key => $main::api->{'key'},
			auth_token => $main::config->{'token'},
			title => $file->[1],
			is_family => $is_family,
			is_public => $is_public,
			is_friend => $is_friend,
			tags => $tags,
			photo => [ $upload_file ] ] );

	my $xml = XML::Parser::Lite::Tree::instance( )->parse( $response->content );

	if( !$response->is_success ||
		$xml->{children}[1]{attributes}{stat} ne 'ok')
	{
		warn "Warning: failed to upload " .$file->[1];
	}
	else
	{
		push( @IDS, $xml->{children}[1]{children}[1]{children}[0]{content} );
	}

	$progressBar->set_fraction( ( $total - $index ) / $total );

	Glib::Idle->add( \&UploadFiles, $index-1 );

	return 0;
}

sub Init
{
	$gladexml = Gtk2::GladeXML->new( './UI/Upload.glade' );

	$accountVerified = 0;
	$thumbsOk = 0;

	Upload::Callbacks::Init( );

	$gladexml->signal_autoconnect_from_package( 'Upload::Callbacks' );

	my $slist = Gtk2::SimpleList->new_from_treeview (
	            $gladexml->get_widget( 'PhotoView' ),
	            'image'    => 'pixbuf',
		    'name'     => 'text',
		    'path'     => 'text' );

	$slist->get_column( 2 )->set_visible( 0 );

	@FILES = ExpandDirectories( @ARGV );

	# TODO: login

	Glib::Idle->add( \&LoadPhotos, $#FILES );

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

	my $radioButton = 'RadioPublic';
	if ( $conf->{'privacy'} eq 'friends' )
	{
		$radioButton = 'RadioFriends';
	}
	elsif ( $conf->{'privacy'} eq 'family' )
	{
		$radioButton = 'RadioFamily';
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
