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
package Account;

use strict;
use warnings;

use Account::Callbacks;

require Exporter;
use vars qw ( @EXPORT_OK );
@EXPORT_OK = qw ( $gladexml );
use vars qw( $gladexml );

use Gtk2 '-init' ;
use Gtk2::GladeXML;

use Net::OAuth;
$Net::OAuth::PROTOCOL_VERSION = Net::OAuth::PROTOCOL_VERSION_1_0A;

# we want the OAuth lib to parse the non-standard username parameter
use Net::OAuth::AccessTokenResponse;
Net::OAuth::AccessTokenResponse->add_extension_param_pattern( '^username' );
Net::OAuth::AccessTokenResponse->add_required_message_params( 'username' );

use HTTP::Request::Common;

sub Init
{
    $gladexml = Gtk2::GladeXML->new( './UI/Account.glade' );

    Account::Callbacks::Init( );

    $gladexml->signal_autoconnect_from_package( 'Account::Callbacks' );
}

1 ; 
