package DDG::Goodie::ConvertLatLon;
# ABSTRACT: Convert between latitudes and longitudes expressed in degrees of arc and decimal

use DDG::Goodie;
use utf8;
use Geo::Coordinates::DecimalDegrees;
use feature 'state';
use HTML::Entities;
use Math::SigFigs qw(:all);
use Math::Round;

zci is_cached => 1;

name 'Convert Latitude and Longitude';
description 'Convert between latitudes and longitudes expressed in degrees of arc and decimal';
primary_example_queries '71º 10\' 3" in decimal';
category 'transformations';
topics 'geography', 'math', 'science';
code_url 'https://github.com/duckduckgo/zeroclickinfo-goodies/blob/master/lib/DDG/Goodie/ConvertLatLon.pm';
attribution github => ['http://github.com/wilkox', 'wilkox'];

triggers any => "convert", "dms", "decimal", "latitude", "longitude", "minutes", "seconds";

#Regexes for latitude/longitude, in either dms or decimal format
# http://msdn.microsoft.com/en-us/library/aa578799.aspx has a good
# overview of the most common representations of latitude/longitude

#Potential Unicode and other representations of "degrees"
my $degQR = qr/
  [º°⁰]|
  ((arc[-]?)?deg(ree)?s?)
  /ix;

#Potential Unicode and other representations of "minutes"
my $minQR = qr/
  ['`ʹ′‵‘’‛]|
  ((arc[-]?)?min(ute)?s?)
  /ix;

#Potential Unicode and other representations of "seconds"
my $secQR = qr/
  ["″″‶“”〝〞‟]|
  $minQR{2}|
  (arc[-]?)?sec(ond)?s?
  /ix;

#Match a decimal or integer number
my $numQR = qr/[\d\.]+/;

#Match a minus sign or attempt at minus sign or word processor
# interpretation of minus sign
my $minusQR = qr/[-−﹣－‒–—‐]/;

#Match a latitude/longitude representation
my $latLonQR = qr/
  (?<minus>$minusQR)?
  (?<degrees>$numQR)$degQR
  ((?<minutes>$numQR)$minQR
  ((?<seconds>$numQR)$secQR)?)?
  (?<cardinal>[NSEW]|(north)|(south)|(east)|(west))?
  /ix;

my %cardinalSign = (
  N => 1,
  S => -1,
  E => 1,
  W => -1,
);

my %cardinalName = (
  n => 'N',
  north => 'N',
  s => 'S',
  south => 'S',
  e => 'E',
  east => 'E',
  w => 'W',
  west => 'W'
);

handle query_nowhitespace => sub {

  return unless $_ =~ /$latLonQR/;

  my $minus = $+{minus};
  my $degrees = $+{degrees};
  my $minutes = $+{minutes};
  my $seconds = $+{seconds};
  my $cardinal = $+{cardinal};

  #Validation: must have minutes if has seconds
  return unless (($minutes && $seconds) || ! $seconds);

  #Validation: can't supply both minus sign and cardinal direction
  return if $minus && $cardinal;

  #Convert cardinal to standardised name if provided
  $cardinal = $cardinalName{lc($cardinal)} if $cardinal;

  #Set the sign
  my $sign;
  if ($cardinal) {
    $sign = $cardinalSign{$cardinal};
  } else {
    $sign = $minus ? -1 : 1;
  }

  #Determine type of conversion (dms -> decimal or decimal -> dms)
  # and perform as appropriate

  #If the degrees are expressed in decimal...
  if ($degrees =~ /\./) {

    #Validation: must not have provided minutes and seconds
    return if $minutes || $seconds;

    #Validation: if only degrees were provided, make sure
    # the user isn't looking for a temperature or trigonometric conversion
    my $rejectQR = qr/temperature|farenheit|celcius|radians/;
    return if $_ =~ /$rejectQR/i;

    #Validation: can't exceed 90 degrees (if latitude) or 180 degrees
    # (if longitude or unknown)
    if ($cardinal && $cardinal =~ /[NS]/) {
      return if abs($degrees) > 90;
    } else {
      return if abs($degrees) > 180;
    }

    #Convert
    (my $dmsDegrees, my $dmsMinutes, my $dmsSeconds, my $dmsSign) = decimal2dms($degrees * $sign);

    #Annoyingly, Geo::Coordinates::DecimalDegrees will sign the degrees as
    # well as providing a sign
    $dmsDegrees = abs($dmsDegrees);

    #If seconds is fractional, take the mantissa
    $dmsSeconds = round($dmsSeconds);

    #Format nicely
    my $formattedDMS = format_dms($dmsDegrees, $dmsMinutes, $dmsSeconds, $dmsSign, $cardinal);
    my $formattedQuery = format_decimal(($degrees * $sign));

    return $formattedDMS, html => wrap_html($formattedQuery, $formattedDMS, 'DMS');

  #Otherwise, we assume type is DMS (even if no
  # minutes/seconds given)
  } else {

    #Validation: must have given at least minutes
    return unless $minutes;

    #Validation: can't have decimal minutes if there are seconds
    return if $minutes =~ /\./ && $seconds;

    #Validation: minutes and seconds can't exceed 60
    return if $minutes >= 60;
    return if $seconds && $seconds >= 60;

    #Apply the sign
    $degrees = $sign * $degrees;

    #Convert
    # Note that unlike decimal2dms, dms2decimal requires a signed degrees
    # and returns a signed degrees (not a separate sign variable)
    my $decDegrees = $seconds ? dms2decimal($degrees, $minutes, $seconds) : dm2decimal($degrees, $minutes);

    #Round to 8 significant figures
    $decDegrees = FormatSigFigs($decDegrees, 8);
    $decDegrees =~ s/\.$//g;

    #Validation: can't exceed 90 degrees (if latitude) or 180 degrees
    # (if longitude or unknown)
    if ($cardinal && $cardinal =~ /[NS]/) {
      return if abs($decDegrees) > 90;
    } else {
      return if abs($decDegrees) > 180;
    }

    #Format nicely
    my $formattedDec = format_decimal($decDegrees);
    my $formattedQuery = format_dms($degrees, $minutes, $seconds, $sign, $cardinal);

    return $formattedDec, html => wrap_html($formattedQuery, $formattedDec, 'decimal');

  }

  return;
};

#Format a degrees-minutes-seconds expression
sub format_dms {

  (my $dmsDegrees, my $dmsMinutes, my $dmsSeconds, my $dmsSign, my $cardinal) = @_;

  my $formatted = abs($dmsDegrees) . '°';
  $formatted .= ' ' . $dmsMinutes . '′' if $dmsMinutes;
  $formatted .= ' ' . $dmsSeconds . '″' if $dmsSeconds;

  #If a cardinal direction was supplied, use the cardinal
  if ($cardinal) {
    $formatted .= ' ' . uc($cardinal);

  #Otherwise, add a minus sign if negative
  } elsif ($dmsSign == -1) {
    $formatted = '−' . $formatted;
  }

  return $formatted;

}

#Format a decimal expression
sub format_decimal {

  (my $decDegrees) = @_;

  my $formatted = abs($decDegrees) . '°';

  #Add a minus sign if negative (decimal format
  # never uses cardial notation)
  if ($decDegrees / abs($decDegrees) == -1) {
    $formatted = '−' . $formatted;
  }

  return $formatted;

}

#CSS and HTML wrapper functions, copied from the
# Conversions Goodie to use the latest and greatest technology
# as implemented in PR #511
sub append_css {
  state $css = share("style.css")->slurp;
  my $html = shift;
  return "<style type='text/css'>$css</style>$html";
}

sub wrap_html {
    my ($query, $result, $toFormat) = @_;
    my $from = encode_entities($query) . " <span class='text--secondary'>" . " in " . encode_entities($toFormat) . ":". "</span>";
    my $to = encode_entities($result);
    return append_css("<div class='zci--conversions text--primary'>$from $to</div>");
}

1;
