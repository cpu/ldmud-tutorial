# LDMud Tutorial (v0.0.1)

This tutorial sets up a brand new Ubuntu 20.04 Linux server with everything you
need to get started with the latest [LDMud game engine][ldmud] and the simplest
[lp-245][lp-245] example MUD.

This tutorial is opinionated, and is based on Ubuntu, Apache2, Certbot, and
Systemd. If you prefer to mix/match other components feel free but you're on
your own for figuring out the details :-) The goal is to bridge the gap between
the LD documentation and a running MUD server to experiment with.

By the end you'll have a MUD server with:

* A dedicated non-root user to run the MUD under.
* A LDMud binary with the PCRE, TLS and Python features enabled.
* An HTTPS enabled Apache website with a [Let's Encrypt][lets-encrypt]
  certificate that browsers will trust.
* A `systemd` service that starts the MUD automatically and restarts it if it
  crashes.
* A [Certbot][certbot] installation to automatically renew your Let's Encrypt
  certificate.
* All of the configuration to run the [lp-245][lp-245] MUD lib on a telnet port,
  and a TLS port that uses the Let's Encrypt certificate.
* Full Python support with packages isolated to a virtual env and dynamic Python
  simul efun registration handled by [`ldmud-efuns`][ldmud-efuns].

[ldmud]: https://ldmud.eu
[certbot]: https://certbot.eff.org/
[lets-encrypt]: https://letsencrypt.org
[lp-245]: https://github.com/ldmud/ldmud/tree/master/mud/lp-245
[ldmud-efuns]: https://pypi.org/project/ldmud-efuns/

## Prerequisites

This tutorial assumes you:

* Are comfortable with `ssh` and using SSH key authentication.
* Are comfortable with basic Linux command line tools.
* Have a registered domain name that you can use for your server.
* Know what a MUD is, and that you want an LP MUD using LDMud as the game
  driver/engine.

If you aren't familiar with these concepts, consult other resources first! You
will require a registered domain name in order to get a Let's Encrypt
certificate that will be trusted by web browsers and correctly configured MUD
clients.

# Overview

Roughly the setup process will involve:

1. [Creating a Digital Ocean droplet.](#create-digital-ocean-droplet)
2. [Setting up a DNS A record for the droplet.](#setup-dns-a-record)
3. [Setting up the server.](#setup-server)
4. [Setting up the website.](#setup-website)
5. [Building the LDMud game driver.](#setup-driver)
6. [Setting up LDMud Python](#setup-ldmud-python)
7. [Setting up HTTPS and acquiring a certificate.](#setup-https-acquire-certificate)
8. [Setting up a systemd Service, starting the MUD.](#setup-systemd-service-start-mud)
9. [Connecting to the MUD.](#test-connection)

There's only one thing we'll need that isn't installable via `apt-get`:

* A custom [deploy hook][ldmud-deploy-hook] Certbot can use to install
  certificates for our LDMud game.

Let's get started!

[ldmud-deploy-hook]: https://gist.github.com/cpu/bec1601816db34bb8c9efeb3f78b37c5

## Create Digital Ocean Droplet

You can substitute the server provider of your choice. In my case I'm creating
the smallest available server, making sure to select these configuration
options:

* Ubuntu 20.04 (LTS) x64
* 1 vCPU, 1 GB RAM, 25 GB disk

Make sure you add a SSH key and once the server is created, mark down the IPv4
address of the instance. In my case the IP address is: `167.99.191.167`.

## Setup DNS A Record

Wherever you registered your domain name probably has the option to set DNS
records (A, AAAA, TXT, CNAME, etc). If not, figure out where your authoritative
DNS is configured.

We need to add an "A" record with the IPv4 address of our new server. In my case
that means updating the `lpc.zone` DNS settings to add:

* `@ A 167.99.191.167`

This will point `lpc.zone` to the IP address `167.99.191.167`.

Once you've created the A record, test if you can see the correct IP address
when you query the domain name with the [Google Apps Toolbox's Dig
tool][dig-tool].

[dig-tool]: https://toolbox.googleapps.com/apps/dig/

## Setup Server

Time to set up the server. We'll be doing these steps as `root`.

* Connect to the server as root:
  ```bash
  ssh root@lpc.zone
  ```
* Update all existing software:
  ```bash
  apt-get update -yy && apt-get upgrade -yy && apt-get dist-upgrade -yy
  ```
* Install what we need for the website, building LDMud, and testing our TLS
  port:
  ```bash
  apt-get install -y \
    git build-essential autoconf pkg-config bison \
    libpcre3-dev libssl-dev libpython3-dev python3.8-venv \
    apache2 \
    telnet-ssl
  ```

  You'll need `git` to clone the LDMud repo. We use `build-essential`,
  `autoconf`, `pkg-config` and `bison` to build LDMud. 

  LD's configure script defaults to enabling PCRE support so we install
  `libpcre3-dev` for that. 

  To enable TLS support we install `libssl-dev` (OpenSSL).

  To enable Python support, and to create a virtual env, we install
  `libpython3-dev` and `python3.8-venv`.
* Add a user to run the MUD under (we don't want to run the game as `root`!):
  ```bash
  adduser mud
  ```
* Set up the MUD user for SSH:
  ```bash
  mkdir ~mud/.ssh
  cp ~/.ssh/authorized_keys ~mud/.ssh/
  chown -R mud:mud ~mud/.ssh
  ```
* Reboot the server (to pick up the kernel updates we installed earlier):
  ```bash
  systemctl reboot
  ```

## Setup Website

Let's create a placeholder for a website to advertise our MUD. After waiting for
the server to finish rebooting, reconnect as `root`.

* SSH to the server as `root` again:
  ```bash
  ssh root@lpc.zone
  ```
* First let's create the "webroot" where the website content goes:
  ```
  mkdir /var/www/mud
  ```
* Next create `/var/www/mud/index.html`, either using your editor of choice, or with this
  command:
  ```bash
  cat << EOF > /var/www/mud/index.html
  <html><head><title>Test</title><body><p>Testing</p></body></html>
  EOF
  ```
* Make sure the MUD user can edit the website content:
  ```bash
  chown -R mud:www-data /var/www/mud
  ```
* Next create the Apache "site" for the MUD. You can either create
  `/etc/apache2/sites-available/mud.conf` with your editor of choice and give it
  [this content](resources/mud.conf) (make sure to replace `lpc.zone with your
  domain name!):
  ```
  <VirtualHost *:80>
    ServerName    lpc.zone
    DocumentRoot  /var/www/mud/
  </VirtualHost>
  ```
* Disable the default Apache site:
  ```bash
  a2dissite 000-default
  ```
* Enable our MUD website:
  ```bash
  a2ensite mud
  ```
* Finally, tell Apache to reload the updated configuration:
  ```bash
  systemctl reload apache2
  ```

At this point you should be able to access your website over HTTP (we'll enable
HTTPS shortly) by visiting `http://lpc.zone` (_replacing `lpc.zone` with your
domain name_).

## Setup Driver

Now we're ready to set up the LDMud game driver. For this we'll use the `mud`
user we created and **not `root`**.

* First, connect to the server as the `mud` user:
  ```bash
  ssh mud@lpc.zone
  ```
* Make a directory for the game, and the game's copies of the TLS cert/key:
  ```bash
  mkdir -p game/tls
  ```
* Make a directory for Python bits:
  ```bash
  mkdir game/python
  ```
* Clone the game driver/lib.
  ```bash
  git clone https://github.com/ldmud/ldmud.git
  ```
* Make a symlink in the game directory to the lp-245 lib in the driver source:
  ```bash
  ln -s /home/mud/ldmud/mud/lp-245/ /home/mud/game/lib
  ```
* Change into the driver directory:
  ```bash
  cd ldmud
  ```
* Change into the driver source directory and install the driver with TLS and Python
  support, with the prefix set to the game directory we made in the `mud` user's
  home dir:
  ```bash
  cd src
  ./autogen.sh
  ./configure \
    --enable-use-tls=ssl \
    --enable-use-python \
    --prefix=$HOME/game
  make install-all
  ```
  Using `--enable-use-tls=ssl` when running `configure` is how we tell LD to use
  the `libssl-dev` package we installed earlier to provide TLS support.

  Providing `--enable-use-python` is how we tell LD to use the `libpython3-dev`
  package we installed earlier to embed Python support.

  Providing `--prefix` lets us choose where `make install-all` will copy the
  installation files for LD.

* Create a simple script for running LD in `/home/mud/game/start.sh` with your
  favourite editor, adding [this content](resources/start.sh):
  ```bash
  #!/usr/bin/env bash

  set -eo pipefail

  DOMAIN=lpc.zone
  MUD_ROOT=/home/mud/game
  TELNET_PORT=4242

  TLS_PORT=4141
  TLS_KEY="$MUD_ROOT/tls/$DOMAIN.key"
  TLS_CERT="$MUD_ROOT/tls/$DOMAIN.crt"
  TLS_ISSUER="$MUD_ROOT/tls/$DOMAIN.issuer.crt"

  PYTHON_VENV="$MUD_ROOT/python/.venv"
  PYTHON_STARTUP="$MUD_ROOT/python/startup.py"

  source "$PYTHON_VENV/bin/activate"
  $MUD_ROOT/bin/ldmud \
    -D"TLS_PORT=$TLS_PORT" \
    --tls-key="${TLS_KEY}" \
    --tls-cert="${TLS_CERT}" \
    --tls-trustfile="${TLS_ISSUER}" \
    --python-script="$PYTHON_STARTUP" \
    --hard-malloc-limit 0 \
    $TLS_PORT \
    $TELNET_PORT
  ```
* Make the startup script executable:
  ```bash
  chmod +x /home/mud/game/start.sh
  ```

We now have the game driver installed to `/home/mud/game/bin/ldmud` and the
lp-245 lib installed to `/home/mud/game/lib`.

The startup script in `/home/mud/game/start.sh` does a few important things:

* It activates the Python virtual env we're going to create next.
* It passes `-D"TLS_PORT=$TLS_PORT"` to the driver, so we get a `TLS_PORT`
  `#define` that LPC code can use to figure out what port is being used for TLS.
* It passes `--tls-key`, `--tls-cert` and `--tls-trustfile` pointing at the
  location the Certbot deploy hook will put certificate related files.
* It passes `--python-script` to tell LD where our `startup.py` is. The
  `ldmud-efuns` package will do the rest of the work from there.
* It passes `--hard-malloc-limit=0` to disable the malloc limit.
* Finally, it passes `$TELNET_PORT` and `$TLS_PORT` to have LD listen on both
  port 4242 and port 4141.

If you're curious, you can look at [this commit][tls-port-commit] to see the
minimal changes made to the lp-245 lib's `obj/master.c` and `obj/player.c` to
support a dedicated TLS port. In short:

* We update `connect()` in `obj/master.c` to check if the user connected to the
  TLS port, and if so, to init the connection and call a `tls_init` callback in
  the player ob.
* We update `obj/player.c` to provide the `tls_init` callback. If TLS was set up
  successfully it calls the normal `logon()` to continue the standard login
  process. We also add a simple `tls` action command.
* We also _move_ a `write()` that was in `connect()` in `master.c` to the
  `logon()` in `player.c` - we don't want to write output while setting up TLS!

[tls-port-commit]: https://github.com/ldmud/ldmud/commit/64b3588a13fb0c761da62d6deb56dfa380b03c6f

## Setup LDMud Python

We want to set up a [Python venv][venv] that we can use to make an isolated
Python environment for our LDMud game. We'll also set up a `startup.py` that
makes it easy to add new Python simul-efuns.

* Connect as the `mud` user:
  ```bash
  ssh mud@lpc.zone
  ```
* Change to the Python dir we created, and create a `venv` in
  `/home/mud/game/python/.venv` by running:
  ```bash
  cd ~/game/python
  python3 -m venv .venv
  ```
* Immediately activate the venv so we can install [ldmud-efuns][ldmud-efuns]
  inside of it:
  ```bash
  source .venv/bin/activate
  pip3 install ldmud-efuns
  ```

* Next create a `startup.py` for LDMud to use that invokes the `ldmud-efuns`
  startup. Create `/home/mud/game/python/startup.py` with the [following
  content](resources/startup.py) using your favourite editor:
  ```python
  import sys
  from ldmudefuns.startup import startup

  print(f"[python] startup.py processing startup.py {sys.version}")
  startup()
  ```

[venv]: https://docs.python.org/3/library/venv.html
[ldmud-efuns]: https://pypi.org/project/ldmud-efuns/

## Setup HTTPS, Acquire Certificate

Now let's get a TLS certificate to use for HTTPS and for the game's TLS
port. We'll use [Certbot][certbot] for this via the recommended [Snap][snap]
installation instructions for [Apache/Ubuntu 20.x][certbot-apache-install]. If
you hate Snap or want to complicate your life, choose an alternative ACME client
from [the list on the Let's Encrypt website][acme-clients] and adapt these
instructions. The [acme.sh][acme-sh] and [Lego][lego] clients are both popular
alternatives.

[snap]: https://ubuntu.com/core/docs/snaps-in-ubuntu-core
[certbot-apache-install]: https://certbot.eff.org/instructions?ws=apache&os=ubuntufocal
[acme-clients]: https://letsencrypt.org/docs/client-options/
[acme-sh]: https://github.com/acmesh-official/acme.sh
[lego]: https://github.com/go-acme/lego

* We need to be back to `root` for these parts, **not `mud`**, so reconnect:
  ```bash
  ssh root@lpc.zone
  ```
* First, update `snap`
  ```bash
  snap install core
  snap refresh core
  ```
* Next install Certbot:
  ```bash
  snap install --classic certbot
  ln -s /snap/bin/certbot /usr/bin/certbot
  ```
* Next set up a [deploy hook][deploy-hook] that can copy automatically renewed
  certificates into a directory where our MUD user and LDMud can read them.
  We'll get this hook from [a Github gist][ldmud-deploy-hook] and put it in
  `/etc/letsencrypt/renewal-hooks/deploy/ldmud-hook` (_don't forget to give it
  execute permission with `chmod`!_):
  ```bash
  mkdir -p /etc/letsencrypt/renewal-hooks/deploy/
  curl \
    -o /etc/letsencrypt/renewal-hooks/deploy/ldmud-hook \
    https://gist.githubusercontent.com/cpu/bec1601816db34bb8c9efeb3f78b37c5/raw/c73c7a0b5ce47318710227d25defcf5ae38fc209/ldmud-hook.py
  chmod +x /etc/letsencrypt/renewal-hooks/deploy/ldmud-hook
  ```
* Finally, run Certbot in Apache mode to automatically configure our website for
  HTTPS with a valid certificate:
  ```bash
  certbot --apache
  ```
  To finish getting the certificate you'll need to choose whether to enter your
  email (_I highly recommended it_), agree to the Let's Encrypt terms of service
  (_mandatory_), and decide whether to join EFF mailing list (_optional_).

  There should be one domain listed for the website we set up earlier (`lpc.zone`
  in my case). Choose this domain and let Certbot finish setup.

* Our custom renewal hook will run the next time a certificate is generated for
  our domain, so we can either force that to happen now or copy the files
  manually this one time:
  ```bash
  certbot --force-renewal
  ```
  or:
  ```bash
  cp /etc/letsencrypt/live/lpc.zone/fullchain.pem ~mud/game/tls/lpc.zone.crt
  cp /etc/letsencrypt/live/lpc.zone/chain.pem ~mud/game/tls/lpc.zone.issuer.crt
  cp /etc/letsencrypt/live/lpc.zone/privkey.pem ~mud/game/tls/lpc.zone.key
  chown mud:root ~mud/game/tls/*
  ```
  Next time this will all be taken care of for us.

Now we should have:

* An HTTPS enabled website we can visit in our web browser without error at
  `https://lpc.zone`.
* Copies of the certificate/private key in `/home/mud/game/tls`, readable by the
  `mud` user.

[deploy-hook]: https://eff-certbot.readthedocs.io/en/stable/using.html?highlight=hooks#setting-up-automated-renewal

## Setup Systemd Service, Start MUD

Let's go ahead and set up a `systemd` service for the MUD. This will:

1. Make sure the MUD is started when the server is rebooted.
2. Make sure the MUD is restarted if it crashes, or is shut-down from in-game.
3. Give us an easy way to read the driver's log output.

* Still connected as `root` and **not `mud`**:
  ```bash
  ssh root@lpc.zone
  ```
* First, create `/etc/systemd/system/mud.service` file with your editor and add
  [the following content](resources/mud.service):
  ```
  [Unit]
  Description = LDMUD Game
  After = network-online.target

  [Service]
  Type = simple
  User = mud
  Group = mud
  WorkingDirectory = /home/mud/game/lib
  ExecStart = /home/mud/game/start.sh
  Restart=always
  RestartSec=3
  OOMScoreAdjust=-900

  [Install]
  WantedBy = multi-user.target
  ```
  This service file leaves all the heavy lifting to the
  `/home/mud/game/start.sh` script we created earlier.

* Now, tell systemd to reload service definitions, and start the MUD:
  ```bash
  systemctl daemon-reload
  systemctl start mud
  systemctl status mud
  ```

* The MUD should have started successfully and be running according to the
  `status` output. We can also see the log output from the driver with:
  ```bash
  journalctl -e -u mud
  ```
  For example:
  ```
  ldmud-tls start.sh[29708]: [python] startup.py processing startup.py 3.8.10 (default, Mar 15 2022, 12:22:08)
  ldmud-tls start.sh[29708]: [GCC 9.4.0]
  ldmud-tls start.sh[29708]: Registering Python efun python_efun_help
  ldmud-tls start.sh[29708]: Registering Python efun python_reload
  ldmud-tls start.sh[29709]: 2022.04.24 01:35:05 [erq] Amylaar ERQ Apr 23 2022: Path 'erq', debuglevel 0
  ldmud-tls start.sh[29708]: 2022.04.24 01:35:05 LDMud 3.6.5 (3.6.5-15-gcb19cb07) (development)
  ldmud-tls start.sh[29708]: 2022.04.24 01:35:05 Seeding PRNG from /dev/urandom.
  ldmud-tls start.sh[29708]: 2022.04.24 01:35:05 TLS: (OpenSSL) x509 keyfile '/home/mud/game/tls/lpc.zone.key', certfile '/home/mud/game/tls/lpc.zone.crt'
  ldmud-tls start.sh[29708]: 2022.04.24 01:35:05 TLS: (OpenSSL) X509 certificate from '/home/mud/game/tls/lpc.zone.crt': EA:04:B3:5C:28:63:B7:69:0C:A4:FC:0D:02:CE:55:78:80:65:C2:A1
  ldmud-tls start.sh[29708]: 2022.04.24 01:35:05 TLS: (OpenSSL) trusted x509 certificates from '/home/mud/game/tls/lpc.zone.issuer.crt'.
  ldmud-tls start.sh[29708]: 2022.04.24 01:35:05 TLS: Importing built-in default DH parameters.
  ldmud-tls start.sh[29708]: 2022.04.24 01:35:05 Attempting to start erq '/home/mud/game/bin/erq'.
  ldmud-tls start.sh[29708]: 2022.04.24 01:35:05 Hostname 'ldmud-tls' address '127.0.1.1'
  ldmud-tls start.sh[29708]: Loading init file /room/init_file
  ...
  <snipped lots of "Preloading file: xxxxx" output>
  ...
  ldmud-tls ldmud[24353]: 2022.04.23 19:21:14 LDMud ready for users.
  ```

* If everything is working correctly, set the game to start up automatically at
  boot:
  ```bash
  systemctl enable mud
  ```

Our systemd service (`/etc/systemd/system/mud.service`) is set up to run the
game as the `mud` user, from the `/home/mud/game/lib` directory. 

## Test Connection

Finally, we're ready to test connecting to the game! 

* Connect to the server as the `mud` user again since we have installed
  `telnet-ssl` there to be able to do some testing:
  ```bash
  ssh mud@lpc.zone
  ```
* To connect on regular old telnet use:
  ```bash
  telnet localhost 4242
  ```
* To connect on the TLS port use:
  ```bash
  telnet-ssl -z ssl localhost 4141
  ```

Once you've logged in to a character you can use the `tls` command to see the
status of your connection.

On telnet it will say:
```
> tls
You are presently connected via an insecure telnet connection.
```

and on the TLS port it will say something like:
```
> tls
You are presently connected via a TLS secured connection.
Protocol: TLSv1.3 Ciphersuite: TLS_AES_256_GCM_SHA384
```

## What's next?

Now that you've got the basics set up you could consider:

* Replacing the vanilla `lp-245` lib with something of your own! Simply delete
  the symlink at `/home/mud/game/lib` and replace it with a copy of your own
  lib. The `lp-245` lib is _extremely basic_ and doesn't always meet up-to-date
  LPC coding best practices.

* Writing something in your game lib to call
  [efun::tls_refresh_certs][tls_refresh_certs] at least once every ~60d so that
  when Certbot renews your Let's Encrypt certificate, the game picks up the new
  copy without needing to be restarted.

* Writing your own Python package adding simul efuns using `ldmud-efuns`. You can
  install it in your virtualenv and hot-reload changes from in-game. See LD's
  [python][man-python] manual page for tons more information.

* Setting up a simple [DokuWiki][DokuWiki] installation in `/var/www/mud` to use
  as your website.

* Replacing all of these manual commands with scripting or a configuration
  management tool of your choice.

* Tweaking the lib to support `STARTTLS` to upgrade connections on the telnet
  port to use TLS (so clients don't have to know about/use the separate TLS
  port). See LD's [tls][man-tls] manual page for more information.

* Experimenting with TLS compatible MUD clients. [Mudlet][Mudlet], 
  [Blightmud][Blightmud], and [Tintin++][TinTin++] all work wonderfully with
  a dedicated TLS port by following the client-specific configuration to connect
  to that port with TLS.

[tls_refresh_certs]: https://github.com/ldmud/ldmud/blob/master/doc/efun/tls_refresh_certs
[man-python]: https://github.com/ldmud/ldmud/blob/master/doc/concepts/python
[DokuWiki]: https://www.dokuwiki.org/dokuwiki
[man-tls]: https://github.com/ldmud/ldmud/blob/master/doc/concepts/tls
[ldmud-efuns]: https://pypi.org/project/ldmud-efuns/
[Mudlet]: https://www.mudlet.org/
[Blightmud]: https://github.com/blightmud/blightmud
[TinTin++]: https://tintin.mudhalla.net/
