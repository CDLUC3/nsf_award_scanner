# NSF Awards API Harvester

This small Ruby/Sinatra app is an example of a system that works with the (DMPHub)
[https://github.com/CDLUC3/dmphub]. It retrieves a list of DMP metadata from the hub and then queries the NSF Awards API by title to find matches. If matches are found, it compare the title of the award to the title of the plan along with the name and affiliations oof any known authors or investigators.

To install:
- Clone this repository (you must have Ruby 2.4+ installed)
- Run `bundle install`
- Generate the following files in the application's root directory: `processed.yml` (which should contain an empty array - `[]`) and `findings.log`.
- You should also create a `config.yml` that contains the following:
```yaml
dmphub:
  client_uid: [my_client_uid]
  client_secret: [my_client_secret]
  user_agent: [my_client_name]
  base_path: 'http://localhost:3000'
  token_path: '/oauth/token'
  index_path: '/api/v1/data_management_plans'
  update_path: '/api/v1/data_management_plans/%{doi}'

nsf:
  base_path: 'https://api.nsf.gov'
  awards_path: '/services/v1/awards.json'
```

The `client_uid`, `client_secret` and `user_agent` must match the values in the DMPHub's `oauth_applications` table. Then update the base path to point to your DMPHub.
