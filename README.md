# F5 Distributed Cloud Example Scripts

Simple scripts to demonstrate API interactions with F5 Distributed Cloud for common maintenance tasks.

Scripts:

- **[all_ce_sites_update.sh](./all_ce_sites_update.sh)**: will query a list of all sites, then call ce_site_upgrade.sh to update SW and OS on every site.

- **[ce_site_upgrade.sh](./ce_site_update.sh)**: can be used to upgrade individual sites SW and OS.

- **[api_cred_cleanup.sh](./api_cred_cleanup.sh)**: will query a list of expired API credentials and revoke / delete.  Does not touch kube configs.

- **[service_cred_cleanup.sh](./service_cred_cleanup.sh)**: similiar to api credential cleanup, but for service credentials.

- **[cdn_cleanup.sh](./cdn_cleanup.sh)**: cleans up / removes content distribution objects in all namespaces.

- **[orphaned_object_purge.sh](./orphaned_object_purge.sh)**: cleans up objects without any references.

- **[old_object_purge.sh](./old_object_purge.sh)**: allows deletion of objects over than a specified date. [Default: 180 Days]

- **[all_ce_reboot_audit.sh](./all_ce_reboot_audit.sh)**: outputs a list of Custome Edge Sites/Nodes and their latest (re)boot date-time.

- **[application_backup.sh](./application_backup.sh)**: will back up all objects in Shared & Application Namespaces:

  - HTTP Load Balancers
  - TCP Load Balancers
  - Origin Pools
  - Service Policies
  - Application Firewalls
  - App Settings
  - API Definitions
  - Custom Routes
  - Certificates

To Run:

```bash
./scriptname.sh <API TOKEN> <TENANT Name> [--days=n]
```

Example:

```bash
./all_ce_sites_update.sh abcdefg8675309= customer-tenant
```
