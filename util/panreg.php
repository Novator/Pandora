<?php

// The Pandora Registrator updates and returns 'active_nodes' table
// RU: Регистратор Пандоры обновляет и возвращает таблицу 'active_nodes'
// 2012 (c) Michael Galyuk, P2P social network Pandora, free software, GNU GPLv2
// RU: 2012 (c) Михаил Галюк, P2P социальная сеть Пандора, свободное ПО

// Usage: http://robux.biz/panreg.php?node=<node_in_hex>[&ips=<list_of_ip>&time=1&hex=1]
// Examples (register and demote):
// http://a.com/panreg.php?node=a1b2c3&ips=222.111.222.111,2001:0:53aa:64c:1c4c:798c:b284:2af0
// http://a.com/panreg.php?node=a1b2c3&ips=2001:0:53aa:64c:1c4c:798c:b284:2af0
// http://a.com/panreg.php?node=a1b2c3&ips=auto  - add ip autodetect
// http://a.com/panreg.php?node=a1b2c3&ips=none  - leech gets the list
// http://a.com/panreg.php?node=a1b2c3           - demote record


// Detect parameters
$node = $_GET['node'];
$time = $_GET['time'];
$ips = $_GET['ips'];
if (! $ips)
  $ips = $_GET['ip'];
if (! $ips)
  $ips = $_GET['ip4'];
if (! $ips)
  $ips = $_GET['ip6'];
$hex = $_GET['hex'];

// Autodetect user IP
$leech = FALSE;
if ($ips) {
  if ($ips=='none')
    $leech = TRUE;
  if (($leech) or ($ips=='auto'))
    $ips = getenv(REMOTE_ADDR);
}

// Read config parameters
$conf = parse_ini_file('panreg.ini', true);
if (! $conf)
  die('!No config file');
$sql_server = $conf['panreg']['sql_server'];
$db = $conf['panreg']['db'];
$db_user = $conf['panreg']['db_user'];
$db_pass = $conf['panreg']['db_pass'];
$table = $conf['panreg']['table'];
$limit = $conf['panreg']['limit'];
$live = $conf['panreg']['live'];
if (! $sql_server)
  $sql_server = 'localhost';
if (! $db)
  $db = $db_user;
if (! $table)
  $table='active_nodes';

// Connect to DB
$res = mysql_connect($sql_server, $db_user, $db_pass);
if (! $res)
  die('!SQL connection error');
$res = mysql_select_db($db);
if (! $res)
  die('!DB select error');

// Change table
if ($node) {

  // Delete all records
  if ($node=='clear') {
    $res = mysql_query("TRUNCATE $table");
    if ($res)
      die('!Table is clear');
    else
      die('!Truncate table error');
  }

  // Convert HEX node to str
  $node = substr($node, 0, 40);
  if (ctype_xdigit($node)) {
    $node = pack("H*" , $node);
  } else {
    die('!Node is not hex');
  }

  // Check node length
  if (! $node)
    die('!Node is NULL');
  $len = strlen($node);
  if ($len != 20)
    die("!Node length is not 20 (=$len)");

  // Truncate table to limit, to old, and to node
  $filter = "time IS NULL";
  if ($limit)
    $filter = "node NOT IN (SELECT * FROM (SELECT node FROM $table ORDER BY time DESC LIMIT $limit) s )";
  if ($live)
    $filter = "(time>NOW()-INTERVAL 1 YEAR AND time<NOW()-INTERVAL $live) OR ".$filter;
  if (($ips) and (strlen($ips)>0))
    $filter = "node='$node' OR ".$filter;
  $res = mysql_query("DELETE FROM $table WHERE ".$filter);
  if (! $res)
    die('!Truncate table error');

  if ($ips) {
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

    // Process ips list
    foreach ($ips as $ip) {
      // Super node inserts with actual time
      $tim = 'NOW()';
      // Leech node inserts with 2000 year
      if ($leech)
        $tim = "DATE_FORMAT(NOW(),'2000-%m-%d %T')";
      $res = mysql_query("INSERT INTO $table (node,ip,time) VALUES('$node', '$ip', $tim)");
      if (! $res)
        die('!Insert error');
    }
  } else {
    // Delete nodes except the last
    $res = mysql_query("DELETE FROM $table WHERE node='$node' AND node NOT IN (SELECT * FROM (SELECT node FROM $table WHERE node='$node' ORDER BY time DESC LIMIT 1) s )");
    if (! $res)
      die('!Delete excess nodes error');
    // Demoted record is marked with 1996 year
    $res = mysql_query("UPDATE $table SET time=DATE_FORMAT(NOW(),'1996-%m-%d %T') WHERE node='$node'");
    if ($res)
      die('!Node is demoted');
    else
      die('!Demote time error');
  }

}

// Select records
$flds = 'node,ip';
if ($time)
  $flds .= ',time';
if (($node) or (! $time))
  $table .= " WHERE time IS NOT NULL AND time>NOW()-INTERVAL 1 YEAR AND ip IS NOT NULL AND ip != ''";
$sql = mysql_query("SELECT $flds FROM $table ORDER BY time DESC LIMIT $limit");
if (! $sql)
  die('!Tab select error');

// If empty table
if (mysql_num_rows($sql)==0)
  die('!');

// Show records
while ($row=mysql_fetch_array($sql)):
  $node = $row['node'];
  if ($hex)
    $node = bin2hex($node);
  else
    $node = base64_encode($node);
  $line = $node.'|';
  $ip = $row['ip'];
  if ($ip) {
    $ip = inet_ntop($ip);
    if ($ip)
      $line .= $ip;
  }
  if ($time)
    $line .= '|'.$row['time'];
  echo $line."<br>";
endwhile;
?>
