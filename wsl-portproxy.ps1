$wslIp = wsl hostname -I | ForEach-Object { $_.Trim() }
netsh interface portproxy reset
netsh interface portproxy add v4tov4 listenaddress=0.0.0.0 listenport=2222 connectaddress=$wslIp connectport=22