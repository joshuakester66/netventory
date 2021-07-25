<!DOCTYPE html>
<html>
<head>
<style>
table, th, td {
     border: 1px solid black;
}
tr:nth-child(even) {
        background: #bbffff;
}
</style>
<link rel="stylesheet" type="text/css" href="network_operations.css">
</head>
<head>
<title>ARP</title>
</head>
<body>

<a href="http://netops.wvc-ut.gov"><img style="display:inline;" src="../images/wvc.jpg" alt="West Valley City Logo" width="200" height="60"></a>
<h1 style="display:inline;vertical-align:20px;">ARP</h1>

<?php
$SERVERNAME = "10.10.9.160";
$USERNAME = "php";
$DATABASE = "netventory";
$TABLE = "network_brief_view";

# Create connection
$CONN = new mysqli($SERVERNAME, $USERNAME, $PASSWORD, $DATABASE);
# Check connection
if ($CONN->connect_error) {
    die("Connection failed: " . $CONN->connect_error);
}

$SQL = "SELECT id,ip,hostname,sysname,dns_name,mac,manufacturer,oui,location,model,firmware,serial,rom,type,last_seen,updated FROM $TABLE ORDER BY ip";
$RESULT = $CONN->query($SQL);

if ($RESULT->num_rows > 0) {
    echo "<table><tr><th>IP</th><th>Hostname</th><th>Sysname</th><th>DNS Name</th><th>MAC</th><th>Manufacturer</th><th>OUI</th><th>Location</th><th>Model</th><th>Firmware</th><th>Serial</th><th>ROM</th><th>Type</th><th>Last Seen</th><th>Updated</th></tr>";
    # output data of each row
    while($ROW = $RESULT->fetch_assoc()) {
        echo "<tr><td>".$ROW["id"]."</td><td>".$ROW["ip"]."</td><td>".$ROW["hostname"]."</td><td>".$ROW["sysname"]."</td><td>".$ROW["dns_name"]."</td><td>".$ROW["mac"]."</td><td>".$ROW["manufacturer"]."</td><td>".$ROW["oui"]."</td><td>".$ROW["location"]."</td><td>".$ROW["model"]."</td><td>".$ROW["firmware"]."</td><td>".$ROW["serial"]."</td><td>".$ROW["rom"]."</td><td>".$ROW["type"]."</td><td>".$ROW["last_seen"]."</td><td>".$ROW["updated"]."</td></tr>";
    }
    echo "</table>";
} else {
    echo "0 results";
}
$CONN->close();
?>

<br />
<a href="http://netops.wvc-ut.gov"><img style="display:inline;" src="../images/wvc.jpg" alt="West Valley City Logo" width="200" height="60"></a>

</body>
</html>
