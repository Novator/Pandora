-- MySQL dump for Pandora Registrator
-- 2012 (c) Michael Galyuk, P2P social network Pandora, GNU GPLv2
-- Use the command to [re]create a table:
-- mysql -u ivan -p12345 -h mysql.local.host.ru -f database < ./panreg.sql

DROP TABLE IF EXISTS `active_nodes`;

CREATE TABLE `active_nodes` (
  `node` varchar(20) NOT NULL,
  `ip` varchar(16) NOT NULL,
  `time` datetime
);

-- INSERT INTO `active_nodes` VALUES ('A1B2C3', '1234','2016-05-26 14:45:55');
