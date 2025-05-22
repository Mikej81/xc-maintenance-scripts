# F5 Distributed Cloud Example Scripts

Simple scripts to demonstrate API interactions with F5 Distributed Cloud

Scripts:

- get_ce_sites.sh: will query a list of all sites, then call ce_site_upgrade.sh to update SW and OS on every site.

- ce_site_upgrade.sh: can be used to upgrade individual sites SW and OS.

- api_cred_cleanup.sh: will query a list of expired API credentials and revoke / delete.  Does not touch kube configs.

- service_cred_cleanup.sh: similiar to api credential cleanup, but for service credentials.

- cdn_cleanup.sh: cleans up content distribution objects.

To Run:

```bash
./scriptname.sh <API TOKEN> <TENANT Name>
```

Example:

```bash
./get_ce_sites.sh abcdefg8675309= customer-tenant
```
