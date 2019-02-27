# ---------------------------------------------------------------------------------------------------------------------
# REQUIRED PARAMETERS
# You must provide a value for each of these parameters.
# ---------------------------------------------------------------------------------------------------------------------
variable "aws_region" {
  description = "AWS region to launch servers."
}

variable "availability_zone" {
  description = "AWS availability zone to launch the transaction executor and eximchain node in"
}

variable "cert_owner" {
  description = "The OS user to be made the owner of the local copy of the vault certificates. Should usually be set to the user operating the tool."
}

variable "network_id" {
  description = "The network ID of the eximchain network to join"
  default     = 513
}

variable "node_volume_size" {
  description = "The size of the storage drive on the eximchain node"
  default     = 50
}

# ---------------------------------------------------------------------------------------------------------------------
# OPTIONAL PARAMETERS
# These parameters have reasonable defaults.
# ---------------------------------------------------------------------------------------------------------------------
variable "public_key_path" {
  description = "The path to the public key that will be used to SSH the instances in this region."
  default     = ""
}

variable "public_key" {
  description = "The path to the public key that will be used to SSH the instances in this region. Will override public_key_path if set."
  default     = ""
}

variable "private_key" {
  description = "The private key that will be used to SSH the instances in this region. Will use the agent if empty"
  default     = ""
}

variable "vault_port" {
  description = "The port that vault will be accessible on."
  default     = 8200
}

variable "disable_authentication" {
  description = "Whether or not the tx executor should disable token authentication. Should be a either 'true' or 'false' in string form."
  default     = "false"
}

variable "node_availability_zones" {
  description = "AWS availability zones to distribute the eximchain nodes amongst. Must name at least two. Defaults to distributing nodes across AZs."
  default     = []
}

variable "node_count" {
  description = "The number of eximchain nodes to launch."
  default     = 1
}

variable "ethconnect_api_cidrs" {
  description = "List of CIDRs to grant access to the ethconnect API."
  default     = []
}

variable "ethconnect_api_security_groups" {
  description = "List of security groups to grant access to the ethconnect API."
  default     = []
}

variable "rpc_api_cidrs" {
  description = "List of CIDRs to grant access to the rpc API."
  default     = []
}

variable "rpc_api_security_groups" {
  description = "List of security groups to grant access to the rpc API."
  default     = []
}

variable "force_destroy_s3_buckets" {
  description = "Whether or not to force destroy s3 buckets. Set to true for an easily destroyed test environment. DO NOT set to true for a production environment."
  default     = false
}

variable "ethconnect_webhook_port" {
  description = "The port to run the ethconnect webhook API on."
  default     = "8088"
}

variable "ethconnect_max_in_flight" {
  description = "The maximum number of requests in flight between Kafka and Eximchain at any time."
  default     = "25"
}

variable "ethconnect_max_tx_wait_time" {
  description = "The maximum number of seconds to wait for a successful transaction before timeout and retry."
  default     = "60"
}

variable "ethconnect_always_manage_nonce" {
  description = "Whether ethconnect should always manage the nonce on its own. Should be a string reading 'true' or 'false'."
  default     = "false"
}

variable "ccloud_broker" {
  description = "The broker for the confluence cloud cluster to use for ethconnect."
  default     = ""
}

variable "ccloud_api_key" {
  description = "The API key for the confluence cloud cluster to use for ethconnect."
  default     = ""
}

variable "ccloud_api_secret" {
  description = "The API secret for the confluence cloud cluster to use for ethconnect."
  default     = ""
}

variable "mongo_connection_url" {
  description = "Connection string for use with the mgo driver to connect to the MongoDB store to use for receipts."
  default     = ""
}

variable "mongo_database_name" {
  description = "Name of the MongoDB database to use for receipts."
  default     = ""
}

variable "mongo_collection_name" {
  description = "Name of the MongoDB collection to use for receipts. Does not need to exist in the database already."
  default     = ""
}

variable "mongo_max_receipts" {
  description = "Number of receipts to retain in the MongoDB store."
  default     = ""
}

variable "mongo_query_limit" {
  description = "Max number of receipts to retrieve at once."
  default     = ""
}

variable "guardian_ami" {
  description = "AMI ID to use for transaction executor servers. Defaults to getting the most recently built version from Eximchain"
  default     = ""
}

variable "guardian_instance_type" {
  description = "The EC2 instance type to use for eximchain nodes"
  default     = "t2.medium"
}

variable "vault_consul_ami" {
  description = "AMI ID to use for vault and consul servers. Defaults to getting the most recently built version from Eximchain"
  default     = ""
}

variable "vault_cluster_size" {
  description = "The number of instances to use in the vault cluster"
  default     = 3
}

variable "vault_instance_type" {
  description = "The EC2 instance type to use for vault nodes"
  default     = "t2.micro"
}

variable "consul_cluster_size" {
  description = "The number of instances to use in the consul cluster"
  default     = 3
}

variable "consul_instance_type" {
  description = "The EC2 instance type to use for consul nodes"
  default     = "t2.micro"
}

variable "cert_org_name" {
  description = "The organization to associate with the vault certificates."
  default     = "Example Co."
}

variable "vpc_cidr" {
  description = "The cidr range to use for the VPC."
  default     = "10.0.0.0/16"
}

variable "enable_https" {
  description = "Boolean string controlling whether to enable HTTPS connections.  If true, subdomain_name and root_domain are required."
  default     = "false"
}

variable "subdomain_name" {
  description = "Required if using HTTPS; the [value] in the final '[value].[root_domain]` DNS name."
  default     = ""
}

variable "root_domain" {
  description = "Required if using HTTPS; the [root_domain] in the final '[value].[root_domain]' DNS name, should end in a TLD (e.g. eximchain.com)."
  default     = ""
}