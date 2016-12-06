# dispatch-log

## previous setup

Our previous centralized log for apache vhosts used
[logger(1)][logger]

[logger]: http://man7.org/linux/man-pages/man1/logger.1.html "man"

From `apache conf`:

```apache
  CustomLog "|/usr/bin/logger -t www_vhost_tld_access -p local6.info" combined
  ErrorLog  "|/usr/bin/logger -t www_vhost_tld_error -p local6.info"
```

The php logs were not centralized.

## new setup on the rsyslog source nodes

The new centralized log setup use the [rsyslog imfile module][imfile]
to convert our standard text apache and php log file (and possibly
others) into syslog messages.

[imfile]: http://www.rsyslog.com/doc/v8-stable/configuration/modules/imfile.html "doc"

Apache access `rsyslog.conf` setup (Similar setup exist for apache and
php error):


```bash
  module(load="imfile")
  input (type="imfile"
  File="/space/log2/*access.log"
  Tag="apache-access"
  stateFile="apache-access"
  Severity="info"
  Facility="local7"
  addMetadata="on")
```
  
Then a specific `rsyslog.conf` setup allow to add the originate file
name in syslog record:

```
  $template meta,"%TIMESTAMP% %HOSTNAME% %APP-NAME% %$!metadata!filename% %MSG%\n
  *.* @@127.0.0.1:514;meta
```

The imfile module can't wildcard folder.  That means the many
dispersed log files must be first hard linked to some centralized
place.  This is done via simple script invoked via
[logrorate][logrotate].  After apache reload, all found log files are
linked to a unique folder.  To ensure file name uniqueness, target
name is a concatenation of last folder path component (vhost name) and
filename.

[logrotate]: https://linux.die.net/man/8/logrotate "man"

Here is our [gatherer script](gather-log "local src")
  
## new setup on the syslog-ng central node

[syslog-ng][syslog-ng] is used and all vhost log files collected are
received as a unique log stream after beeing tag splitted
(*apache-access*, *apache-error*, *php-error*).
  
[syslog-ng]: https://linux.die.net/man/8/syslog-ng "man"

To dispatch again log files by vhost we use a specific `syslog-ng`
setup which add all needed information to syslog record allowing a
[dispatch script](dispatch-log "local src") to dynamically recreate original vhost
files.

A typical `syslog-ng` setup looks like:

```c
destination d_dispatch {
  program("/usr/local/bin/dispatch-log"
  template("/space/remote_logs/$HOST/$YEAR/$MONTH/$DAY/${PROGRAM}.d $MSG\n")); };
filter f_host_front { host("front1") or host("front2"); };
filter f_program_apache_access { program("apache-access"); };
log { source(src_lan); filter(f_host_front); filter(f_program_apache_access); destination(d_dispatch); };
```

As the src node already added the vhost file name as first `syslog`
record the script only need to construct a destination path from first
and second field of `syslog` record by wrapping a simple `awk` script:

```awk
BEGIN { path = "^/([[:alnum:]_.-]+/?)+$" }
($1 !~ path) || ($2 !~ path) { exit(2) }
NR == 1 || previous != $1 { system("mkdir -p " $1); previous = $1 }
{
  cmd = substr($0, index($0, $3));
  file = $1 substr($2, length(prefix) + 1);
  if (erase) print cmd > file; else print cmd >> file; fflush()
}
```

Where `prefix` is passed via the (Makefile) wrapper and is the base
path of gathered remote log files.
