wmic -Utestuser%tstpass //172.16.2.2 "SELECT * FROM Win32_OperatingSystem"



wmic --user "wvcmsdom\jkester" --password "" //10.10.10.111 "SELECT * FROM Win32_OperatingSystem"
