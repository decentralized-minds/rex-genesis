
# REX

## For registration in genesis:
1. Keygen - create new account and mnemonic

```
make keygen
```

2. Init - get all the configurations set

```
make init
```

3. Mine one proof

```
make mine
```

4. Have your [github token](https://docs.github.com/en/github/authenticating-to-github/keeping-your-account-and-data-secure/creating-a-personal-access-token) in 0L directory. 

```
cp your/path/github_token.txt ~/.OL/
```

5. Register

```
make register
```

# Wait for everyone to register

1. Coordinator changes set_layout.toml, and does `make layout`

# Do Genesis
1. Build the genesis transaction
```
export NODE_ENV=prod
make genesis
```

2. Create a config file for node
```
make node-file
```
