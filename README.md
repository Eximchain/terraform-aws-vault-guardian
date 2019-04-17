# terraform-aws-vault-guardian
Terraform Infrastructure to run vault-guardian app

# Updating Certificates

Ensure the new certificates are in the S3 bucket and run the following on each vault instance:

```sh
$ sudo /opt/vault/bin/update-https-certs.sh
```