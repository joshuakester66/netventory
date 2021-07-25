SELECT ip,COUNT(ip) FROM netventory.device GROUP BY ip HAVING COUNT(ip) > 1;
DELETE c1 FROM netventory.device c1 INNER JOIN netventory.device c2 WHERE c1.id > c2.id AND c1.ip = c2.ip;
