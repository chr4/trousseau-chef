trousseau-chef
==============

Small script (configurable by a YAML file), to manage Chef encrypted data bags with
[Trousseau](https://github.com/oleiade/trousseau)

# Description

When using Chefs encrypted data bags, it's a challenge howto syncronize the (unencrypted) JSON files
containing the sensitive information between admin users.
There's some approaches on howto solve this, including encrypted git repositories, which is usually
a big mess.

- Store sensitive information in [Trousseau](https://github.com/oleiade/trousseau) (an encrypted,
  multiuser key-value store using GPG)
- Generate (if required) `data_bag_secrets` automatically (and store them in Trousseau as well)
- Generate Chef data bags from Trousseau information, and syncronize them with the Chef server
- Upload the required `data_bag_secrets` to the servers that need to decrypt the information using
  SSH

# Usage

## Initial setup

Let's say you want to store your SSL certificates securely. First, git clone this repository into
your Chef kitchen.

```shell
$ cd chef-repo
$ git clone https://github.com/chr4/trousseau-chef.git secrets
$ cd secrets
$ bundle install
```

Create a basic configuraton file `config.yaml` for our certificate datastore

```yaml
certificates:
  data_bag:
    cert: "%s.crt"
    key: "%s.key"
```

Now, create a directory and the trousseau store for your certificates

```shell
$ mkdir certificates
$ cd certificates
$ export TROUSSEAU_STORE=trousseau.asc
$ trousseau create you@example.com
```

For convenience, I recommend to set the `TROUSSEAU_STORE` variable automatically when changing to
this directory. You can do so using a tool like [direnv](http://direnv.net/)

```shell
$ cat .direnv
export TROUSSEAU_STORE=trousseau.asc
```

## Store your certificate in Trousseau

```shell
$ trousseau set www.example.com.key --file mycert.key
$ trousseau set www.example.com.crt --file mycert.crt
```

```shell
$ ./generate certificate www.example.com
Updated data_bag_item[certificates:www.example.com]
```

This will generate (and use) `www.example.com/data_bag_secret` to encrypt your data bag.
The `data_bag_secret` can automatically be uploaded to one or more servers using the `--tagret`
parameter to the remote machines `/etc/chef/certificate_data_bag_secret`. "sudo" is required on the
remote machine.

```shell
$ ./generate certificate www.example.com --target 1.app.example.com,2.app.example.com
Updated data_bag_item[certificates:www.example.com]
Copying data_bag_secret to 1.app.example.com
Copying data_bag_secret to 2.app.example.com
```

When generating/uploading a data bag, you can also specify the data bag id manually by using the
`--id` parameter

```shell
$ ./trousseau-chef.rb certificates www.example.com --id example
Updated data_bag_item[certificates:example]
```

For instructions howto syncronize the Trousseau store between machines, please see the [Trousseau
documentation](https://github.com/oleiade/trousseau#importingexporting-to-remote-storage)


That's it! You now have your certificates stored encrypted in Trousseau, and you can update your
data bags and manage the `data_bag_secrets` conveniently!


## Advanced configuration

Of course, you can handle multiple Trousseau stores using the same configuration, as well as adapt
the generation process to your need.

You can use different Trousseau stores instead of the default `#{data_bag_name}/trousseau.asc`

```yaml
certificates:
  trousseau_store: 'certificates.asc'
```

When creating the data bag, you can use `%s` as a placeholder for the item name

```yaml
ssh_keypairs:
  # Manually specify trousseau store
  trousseau_store: "ssh_keypairs.asc"

  # Add a description (displayed when using "./trousseau-chef.rb help"
  description: "Generate ssh keypairs"

  # Customize the data_bag_secret filename. When using the --target flag,
  # the script will upload the data_bag_secret to the remote machine
  data_bag_secret: /etc/chef/my_data_bag_secret

  # Specify how the data bag hash looks like
  # The "%s" placeholder will be replaced with the item name
  #
  # When using "./trousseau-chef.rb ssh_keypairs example",
  # the script will look for the ssh private and public keys in the Trousseau store
  #
  # - example/id_rsa
  # - example/id_rsa.pub
  # - example/id_ed25519
  # - example/id_ed25519.pub
  #
  # If an element is not found in the Trousseau store, it will be skipped.
  data_bag:
    keychain:
      id_rsa: "%s/id_rsa"
      id_rsa.pub: "%s/id_rsa.pub"
      id_ed25519: "%s/id_ed25519"
      id_ed25519.pub: "%s/id_ed25519.pub"
```

See the [example config.yaml](https://github.com/chr4/trousseau-chef/blob/master/config.yaml.example)
for further details.
