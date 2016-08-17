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
// http://a.com/panreg.php?node=a1b2c3&ips=none  - read a list by leech
// http://a.com/panreg.php?node=a1b2c3           - demote record
// http://a.com/panreg.php?hex=1&time=1          - all nodes in hex format with time
// http://a.com/panreg.php?node=a1b2c3&ips=none&trace=1  - show mysql trace info


// Detect GET-parameters
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
$trace = $_GET['trace'];

// Autodetect user IP
$leech = FALSE;
if ($ips) {
  if ($ips=='none')
    $leech = TRUE;
  if (($leech) or ($ips=='auto'))
    $ips = getenv(REMOTE_ADDR);
}

// Read ini-file parameters
$conf = parse_ini_file('panreg.ini', true);
if (! $conf)
  die('!No config file');
$sql_server = $conf['panreg']['sql_server'];
$db = $conf['panreg']['db'];
$db_user = $conf['panreg']['db_user'];
$db_pass = $conf['panreg']['db_pass'];
$table = $conf['panreg']['table'];
$limit = $conf['panreg']['limit'];
$alive_time = $conf['panreg']['alive_time'];
$erase_time = $conf['panreg']['erase_time'];
if (! $sql_server)
  $sql_server = 'localhost';
if (! $db)
  $db = $db_user;
if (! $table)
  $table='active_nodes';

// Show MySQL error and die
function die_mysql($mes,$query=NULL) {
  global $trace;
  if ($trace)
    if ($query)
      $mes .= ' ['.htmlspecialchars($query).']';
    $mes .= ': '.htmlspecialchars(mysql_error());
  die($mes);
}

// Connect to DB
$res = mysql_connect($sql_server, $db_user, $db_pass);
if (! $res)
  die_mysql('!SQL connection error');
$res = mysql_select_db($db);
if (! $res)
  die_mysql('!DB select error');

// Change table
if ($node) {

  // Delete all records
  if ($node=='clear') {
    $res = mysql_query("TRUNCATE $table");
    if ($res)
      die('!Table is clear');
    else
      die_mysql('!Truncate table error');
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

  $node = mysql_real_escape_string($node);

  // MySQL formula for calc old year time
  function old_now($year) {
    return "DATE_FORMAT(NOW(),'".$year."-%m-%d %T')";
  }

  // If ips sets, it's a node adding, else deleting
  if ($ips) {
    // Convert IP human view to binary
    $ips = explode(",", $ips);
    foreach ($ips as $i => $val) {
      $ip = inet_pton($val);
      if ($ip)
        $ips[$i] = mysql_real_escape_string($ip);
      else
        unset($ips[$i]);
    }

    if (count($ips)==0)
      die('!Bad IP');

    // Delete nodes when: ips specified, time expired or limit exceeds
    $filter = '';
    if (($ips) and (strlen($ips)>0))
      $filter = "node='$node'";
    $now2000 = old_now(2000);
    if ($erase_time) {
      if (strlen($filter)>0)
        $filter .= ' OR ';
      $filter .= "(time>NOW()-INTERVAL 1 YEAR AND time<NOW()-INTERVAL $erase_time)";
      $now2001 = old_now(2001);
      $filter .= " OR (YEAR(time)=2000 AND ((time<$now2000-INTERVAL $erase_time) OR (time>$now2001-INTERVAL $erase_time)))";
      $now1996 = old_now(1996);
      $now1997 = old_now(1997);
      $filter .= " OR (YEAR(time)=1996 AND ((time<$now1996-INTERVAL $erase_time) OR (time>$now1997-INTERVAL $erase_time)))";
    }
    if ($limit) {
      if (strlen($filter)>0)
        $filter .= ' OR ';
      $filter .= "node NOT IN (SELECT * FROM (SELECT node FROM $table ORDER BY time DESC LIMIT $limit) s )";
    }
    if (strlen($filter)>0) {
      $res = mysql_query("DELETE FROM $table WHERE ".$filter);
      if (! $res)
        die_mysql('!Delete error', $filter);
    }

    // Insert by ips list
    foreach ($ips as $ip) {
      // Super node inserts with actual time
      $tim = 'NOW()';
      // Leech node inserts with 2000 year
      if ($leech)
        $tim = $now2000;
      $res = mysql_query("INSERT INTO $table (node,ip,time) VALUES('$node', '$ip', $tim)");
      if (! $res)
        die_mysql('!Insert error');
    }
  } else {
    // Delete excess nodes (except the newest)
    $query = "DELETE FROM $table WHERE node='$node' AND node NOT IN (SELECT * FROM (SELECT node FROM $table WHERE node='$node' ORDER BY time DESC LIMIT 1) s )";
    $res = mysql_query($query);
    if (! $res)
      die_mysql('!Delete excess nodes error', $query);
    // Demoted record marks with 1996 year
    $filter = '';
    if ($alive_time)
      $filter = " OR (time>NOW()-INTERVAL 1 YEAR AND time<NOW()-INTERVAL $alive_time)";
    $now1996 = old_now(1996);
    $res = mysql_query("UPDATE $table SET time=$now1996 WHERE node='$node'".$filter);
    if ($res)
      die('!Nodes are demoted');
    else
      die_mysql('!Demote error', $filter);
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
  die_mysql('!Tab select error', $table);

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
