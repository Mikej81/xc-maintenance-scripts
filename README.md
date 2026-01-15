# F5 Distributed Cloud Example Scripts

Simple scripts to demonstrate API interactions with F5 Distributed Cloud for common maintenance tasks.

Scripts:

- **[all_ce_sites_update.sh](./all_ce_sites_update.sh)**: will query a list of all sites, then call ce_site_upgrade.sh to update SW and OS on every site.

- **[ce_site_upgrade.sh](./ce_site_update.sh)**: can be used to upgrade individual sites SW and OS.

- **[api_cred_cleanup.sh](./api_cred_cleanup.sh)**: will query a list of expired API credentials and revoke / delete.  Does not touch kube configs.

- **[service_cred_cleanup.sh](./service_cred_cleanup.sh)**: similiar to api credential cleanup, but for service credentials.

- **[cdn_cleanup.sh](./cdn_cleanup.sh)**: cleans up / removes content distribution objects in all namespaces.

- **[orphaned_object_purge.sh](./orphaned_object_purge.sh)**: cleans up objects without any references.

- **[orphaned_object_audit.sh](./orphaned_object_audit.sh)**: audits objects without any references (without deleting). Supports filtering by object type.

- **[old_object_purge.sh](./old_object_purge.sh)**: allows deletion of objects older than a specified date. [Default: 180 Days]

- **[all_ce_reboot_audit.sh](./all_ce_reboot_audit.sh)**: outputs a list of Custome Edge Sites/Nodes and their latest (re)boot date-time.

- **[user_audit.sh](./user_audit.sh)**: audits all users showing roles, last login, and status. Supports filtering by inactive days and CSV export.

- **[application_backup.sh](./application_backup.sh)**: will back up all objects in Shared & Application Namespaces:

  - HTTP Load Balancers
  - TCP Load Balancers
  - HTTP Connect & DRP
  - Origin Pools
  - Health Checks
  - Service Policies
  - Application Firewalls
  - User Identifications
  - App Settings
  - API Definitions
  - Custom Routes
  - Certificates
  - Root CA Certificate/Bundles
  - Virtual Sites

To Run:

```bash
./scriptname.sh <API TOKEN> <TENANT Name> [OPTIONS]
```

Options (script-specific):

| Script | Option | Description |
|--------|--------|-------------|
| old_object_purge.sh | `--days=N` | Delete objects older than N days (default: 180) |
| orphaned_object_audit.sh | `--type=TYPE` | Filter by object type: `origin_pool`, `app_firewall`, `service_policy`, `app_setting`, `api_definition`, `http_loadbalancer` |
| user_audit.sh | `--inactive-days=N` | Only show users inactive for more than N days |
| user_audit.sh | `--format=FORMAT` | Output format: `table` (default), `csv` |

Examples:

```bash
# Update all CE sites
./all_ce_sites_update.sh abcdefg8675309= customer-tenant

# Purge objects older than 90 days
./old_object_purge.sh abcdefg8675309= customer-tenant --days=90

# Audit all orphaned objects
./orphaned_object_audit.sh abcdefg8675309= customer-tenant

# Audit only orphaned service policies
./orphaned_object_audit.sh abcdefg8675309= customer-tenant --type=service_policy

# Audit all users
./user_audit.sh abcdefg8675309= customer-tenant

# Audit users inactive for more than 90 days
./user_audit.sh abcdefg8675309= customer-tenant --inactive-days=90

# Export user audit to CSV
./user_audit.sh abcdefg8675309= customer-tenant --format=csv > users.csv
```
