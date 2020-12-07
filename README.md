Quickly set up and tear down a livestream environment for a limited amount of visitors using a DigitalOcean Droplet. All relevant data is kept in RAM and no logs are created aside from statistics on the stream (but not the visitors).

# Prerequisites

1. An account with DigitalOcean. If you do not have one you can use this [Affiliate Link](https://m.do.co/c/da5afaa104b4) to get some starting credits.
2. Control over the DNS for a domain or subdomain. You need the capability to set the DNS A record for the domain and a wildcard for all subdomains of that domain. Example: live.example.org and *.live.example.org
3. A working docker installation is required for generating configuration files. Only the generated files are required for running the script. So you can do the setup on one machine with docker and then copy the files to another machine and run the script there without docker.
4. Powershell (preinstalled or modern - I have tested 5.1 and 7.1 on Windows 10)

# Setup

Run `setup.cmd`. This will ask a number of questions and create files in the `.secret` subfolder. These files contain secret keys and values and should not be shared. To run the script on a machine without docker, copy this subfolder to the target.

# Usage

Just run `start.cmd` with the `.secret` folder present. The script will start and set up the DO droplet and open a local port to establish an rtmp connection to the server.

To stop the livestreaming system and free the cloud resources, just close the powershell window or press Ctrl-C.

Note: While the script does its best to free the resources it is possible that these requests are interrupted and the droplets will not be deleted. It is recommended to set a cost limit and email warning on DO to prevent costs silently piling up.

# Contributions

PRs are welcome, but as this is just a pet project please do not expect a lot of activity or responsiveness from my side.