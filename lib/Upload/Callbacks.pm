#
# nautilus-flickr-uploader - upload pics to Flickr from Nautilus
# Copyright (C) 2009, 2010  Juan J. Martinez <jjm@usebox.net>
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
package Upload::Callbacks;

use strict;
use warnings;

use vars qw( $gladexml $upload_thread );

use Gtk2::Gdk::Keysyms;
use YAML 'DumpFile';

sub Init
{
	$gladexml = $Upload::gladexml;
	$upload_thread = undef;
}

sub SaveConfiguration()
{
	# get current configuration from the GUI and store it in a file
	my $conf = $main::config;

	$conf->{'privacy'} = 'public';
	$conf->{'family'} = 'no';
	$conf->{'friends'} = 'no';

	my $radio = $gladexml->get_widget( 'RadioPrivate' );
	if( $radio->get_active( ) )
	{
		$conf->{'privacy'} = 'private';
	}

	my $family = $gladexml->get_widget( 'PrivateFamily' );
	if( $family->get_active( ) )
	{
		$conf->{'family'} = 'yes';
	}

	my $friends = $gladexml->get_widget( 'PrivateFriends' );
	if( $friends->get_active( ) )
	{
		$conf->{'friends'} = 'yes';
	}

	my $spin = $gladexml->get_widget( 'SizeSpinButton' );
	$conf->{'size'} = scalar( $spin->get_value( ) );

	$conf->{'resize'} = 'no';
	my $resize = $gladexml->get_widget( 'ResizeCheckButton' );
	if( $resize->get_active( ) )
	{
		$conf->{'resize'} = 'yes';
	}

	DumpFile( $main::config_file,  \%$conf ) or
		warn 'Warning: failed to write de configuration';
}

sub on_UploadDialog_close
{
	Gtk2->main_quit;

	SaveConfiguration( );
}

sub on_ResizeCheckButton_toggled
{
	my $check = $gladexml->get_widget( 'ResizeCheckButton' );
	my $spin = $gladexml->get_widget( 'SizeSpinButton' );
	my $pixels = $gladexml->get_widget( 'PixelsLabel' );

	$spin->set_sensitive( $check->get_active );
	$pixels->set_sensitive( $check->get_active );
}

sub on_PhotoView_key_release_event
{
	my ( $widget, $event ) = @_;

	if( $event->keyval == $Gtk2::Gdk::Keysyms{Delete} )
	{
		my $list = $gladexml->get_widget( 'PhotoView' );

		my @selected = $list->get_selected_indices( );
		if( scalar( @selected ) )
		{
			@selected = sort { $b <=> $a } @selected;
			foreach( @selected )
			{
				splice( @{$list->{data}}, $_, 1 );
			}
            
            # disable OK button if there aren't photos to upload
            if( !scalar( @{$list->{data}} ) )
            {
                my $ok = $gladexml->get_widget( 'OkButton' );
                $ok->set_sensitive( 0 );
            }
		}
	}
}

sub on_ChangeUserButton_clicked
{
	if( !$Account::gladexml )
	{
		Account::Init( );
	}
}

sub on_OkButton_clicked
{
	my $list = $gladexml->get_widget( 'PhotoView' );

	if( !scalar( @{$list->{data}} ) )
	{
		on_UploadDialog_close( );
		return;
	}

	my $ok = $gladexml->get_widget( 'OkButton' );
	$ok->set_sensitive( 0 );

	my $box = $gladexml->get_widget( 'MainBox' );
	$box->set_sensitive( 0 );

	my $progressBar = $gladexml->get_widget( 'ProgressBar' );
	$progressBar->show( );

	# this thread uploads the picures on demand
	if( !$upload_thread )
	{
	    $upload_thread = threads->create( 'Upload::Thread' );
	    $upload_thread->detach( );
	}

	Glib::Idle->add( \&Upload::UploadFiles, $#{$list->{data}} );
}

sub on_PhotoView_drag_data_received
{
	my ($widget, $context, $widget_x, $widget_y, $data, $info, $time) = @_;
	my @uris = $data->get_uris( );

	foreach( @uris )
	{
		# unscape URIs
		s/%([0-9A-Fa-f]{2})/chr(hex($1))/eg;
		warn "Warning: unsupported URI: $_" unless s/file:\/\///;
	}

	@Upload::FILES = Upload::ExpandDirectories( @uris );

	my $progressBar = $gladexml->get_widget( 'ProgressBar' );
	$progressBar->show( );

	Glib::Idle->add( \&Upload::LoadPhotos, $#Upload::FILES );
}

sub on_RadioPublic_toggled
{
	my $widget = shift;
	my $private = !$widget->get_active( );

	my $friends = $gladexml->get_widget( 'PrivateFriends' );
	$friends->set_sensitive( $private );
	my $family = $gladexml->get_widget( 'PrivateFamily' );
	$family->set_sensitive( $private );
}

1 ; 
