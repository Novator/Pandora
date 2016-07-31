<?php

// The Pandora Registrator updates and returns 'active_nodes' table
// RU: Регистратор Пандоры обновляет и возвращает таблицу 'active_nodes'
// 2012 (c) Michael Galyuk, P2P social network Pandora, free software, GNU GPLv2
// RU: 2012 (c) Михаил Галюк, P2P социальная сеть Пандора, свободное ПО

// Usage: http://robux.biz/panreg.php?node=<node_in_hex>&ips=<list_of_ip>[&del=1&time=1]
// Examples (add and remove):
// http://a.com/panreg.php?node=a1b2c3&ip=2001:0:53aa:64c:1c4c:798c:b284:2af0
// http://a.com/panreg.php?node=a1b2c3&ips=222.111.222.111,2001:0:53aa:64c:1c4c:798c:b284:2af0
// http://a.com/panreg.php?node=a1b2c3&delete=1


// Detect parameters
$node = $_GET['node'];
$time = $_GET['time'];
$delete = $_GET['del'];
if (! $delete)
  $delete = $_GET['delete'];
$ips = $_GET['ips'];
if (! $ips)
  $ips = $_GET['ip'];
if (! $ips)
  $ips = $_GET['ip4'];
if (! $ips)
  $ips = $_GET['ip6'];

// Autodetect user IP
if (! $ips)
  $ips = getenv(REMOTE_ADDR);

// SQL parameters
$sql_server='mysql.local.host.ru';
$db='database';
$db_user='vasya';
$db_pass='12345';
$table='active_nodes';
$limit=70;
//$live='1 MINUTE'
$live='48 HOUR';

// Connect to DB
$res = mysql_connect($sql_server, $db_user, $db_pass);
if (!$res)
  die('!SQL connection error');
$res = mysql_select_db($db);
if (!$res)
  die('!DB select error');

// Parameters setted?
if (($node) and ($ips)) {

  // Convert HEX node to str
  $node = substr($node, 0, 40);
  if (ctype_xdigit($node)) {
    $node = pack("H*" , $node);
  } else {
    die('!Node is not hex');
  }

  // Convert IP human view to binary
  $ips = explode(",", $ips);
  foreach ($ips as $i => $val) {
    $ip = inet_pton($val);
    if ($ip)
      $ips[$i] = $ip;
    else
      unset($ips[$i]);
  }

  if (count($ips)==0)
    die('!Bad IP');

  // Delete old nodes
  $res = mysql_query("DELETE FROM $table WHERE node='$node' OR time<NOW()-INTERVAL $live OR node NOT IN (SELECT * FROM (SELECT node FROM $table ORDER BY time DESC LIMIT $limit) s )");
  //$res = mysql_query("DELETE FROM $table WHERE node='$node' OR time<NOW()-INTERVAL 1 MINUTE OR node NOT IN (SELECT * FROM (SELECT node FROM $table ORDER BY time DESC LIMIT $limit) s )");
  if (!$res)
    die('!Old delete error');

  // Process all ips
  foreach ($ips as $ip) {
    // Delete old nodes
    $res = mysql_query("DELETE FROM $table WHERE node='$node' AND ip='$ip'");
    if (!$res)
      die('!Node delete error');

    if (! $delete) {
      // Insert the node
      $res = mysql_query("INSERT INTO $table (node,ip,time) VALUES('$node', '$ip', NOW())");
      if (!$res)
        die('!Insert error');
    }
  }

  // Exit if delete
  if ($delete)
    die('!Node is deleted');

}

// Select records
$sql = mysql_query("SELECT * FROM $table ORDER BY time DESC LIMIT $limit");
if (!$sql)
  die('!Tab select error');

// Show records
while ($row=mysql_fetch_array($sql)):
  $ip = inet_ntop($row['ip']);
  $line = bin2hex($row['node'])."|".$ip;
  if ($time)
    $line .= '|'.$row['time'];
  echo $line."<br>";
endwhile;
?>
