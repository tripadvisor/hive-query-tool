package App::HiveQueryTool::Utils;
use DateTime;

# returns a string representing date in the format MM-DD-YYYY HH:MM:SS EST
# for the given epoch
sub getDate_mdy_hms_timezone {
  my $epoch_time = shift || time;
  my $dt = DateTime->from_epoch(epoch => $epoch_time, time_zone => 'local');
  return $dt->mdy() . " " . $dt->hms() . " " . $dt->time_zone_short_name();
}
1;
