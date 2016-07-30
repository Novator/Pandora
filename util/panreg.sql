DROP TABLE IF EXISTS `active_nodes`;

CREATE TABLE `active_nodes` (
  `ip` varchar(16) NOT NULL,
  `node` varchar(22) NOT NULL,
  `time` datetime NOT NULL CURRENT_TIMESTAMP
);

INSERT INTO `active_nodes` VALUES ('1234','A1B2C3','2016-05-26 14:45:55');
