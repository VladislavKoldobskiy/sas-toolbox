# sas-toolbox

Some scripts that I coded for automating SAS deployment routines.

## add-firewall-rules.sh
Adds/removes client access rules to firewalld.

Options:
* ``--role <...>`` - one of "metadata", "compute", "midtier" or "aio" for all-in-one installs; defines rule set to apply
* ``--zone <...>`` - firewall zone to modify (default public)
* ``--level <...>`` - SAS configuration level (1..9, default 1)
* ``--trust <...>`` - add network address to "trusted" firewall zone
* ``--uninstall`` - remove created rules from firewalld

## integrity.sh
Simple git wrapper (plus huge gitignore) to track SASConfig directory changes.

Options:
* ``init`` - run this after initial setup; will create .gitignore and set git configuration options
* ``status`` or ``check`` - runs ``git status``
* ``commit`` - runs ``git add .`` followed by ``git commit``. Will pop up a prompt to describe your changes
* ``restore`` or ``reset`` - runs ``git reset --hard``

## lasrctl.sh
Command-line control for LASR so it can survive SASServer12 restarts.

Usage: ``lasrctl.sh start|stop``

## stratum.sh
Automates Content Pack deployment in SAS Risk Stratum solutions.
Supports Stratum Core, GCM, MRM, IFRS9 and IFRS17 content packs.

Options:
* ``--role <...>`` - "compute", "midtier" or "aio" for all-in-one installs; defines machine role
* ``--solution <...>`` - one of "gcm", "mrm", "core", "ifrs9" or "ifrs17". Solution (content pack) name to install
* ``--metaserver <...>`` - SAS Metadata Server host name (default localhost)
* ``--rgfserver <...>`` - RGF DB Server host name (default localhost)
* ``--level <...>`` - SAS configuration level (1..9, default 1)
* ``--rgfadmin-pwd <...>`` - cleartext password for ``rgfadmin`` UNIX host account (default Orion123)
* ``--rgfdbuser-pwd <...>`` - cleartext password for ``rgfdbuser`` PostgreSQL account (default Orion123)
* ``--passwords <...>`` - cleartext password for both ``rgfadmin`` and ``rgfdbuser``, useful if they are going to be identical
